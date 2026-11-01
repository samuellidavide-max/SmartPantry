"""Scontrini: upload -> OCR -> parsing -> matching -> revisione utente -> conferma -> ledger prezzi + crediti."""
from __future__ import annotations

import datetime as dt
import hashlib
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from psycopg.types.json import Jsonb
from pydantic import BaseModel

from ..auth import current_user
from ..config import settings
from ..db import get_conn
from ..receipts.ocr import OcrError, extract_text
from ..receipts.parser import parse_receipt_text
from ..resolver import resolve_pair
from ..seed import normalize_alias
from ..users import search_center

router = APIRouter(prefix="/v1/receipts", tags=["scontrini"])
UPLOAD_DIR = Path(__file__).resolve().parents[2] / "uploads"
MATCH_OK = 0.55


def match_line(conn, chain_id: int, raw: str) -> tuple[int | None, float, list[dict]]:
    alias = normalize_alias(raw)
    rows = conn.execute("""
        SELECT a.product_id, p.name, max(similarity(a.alias_text, %s)) AS score,
               bool_or(a.alias_text = %s) AS exact
        FROM product_aliases a JOIN products p ON p.id = a.product_id
        WHERE a.chain_id = %s OR a.chain_id IS NULL
        GROUP BY a.product_id, p.name ORDER BY exact DESC, score DESC LIMIT 4""", (alias, alias, chain_id)).fetchall()
    cands = [{"product_id": r["product_id"], "name": r["name"], "score": round(float(r["score"]), 2)} for r in rows]
    if rows and (rows[0]["exact"] or rows[0]["score"] >= MATCH_OK):
        return rows[0]["product_id"], 1.0 if rows[0]["exact"] else float(rows[0]["score"]), cands
    return None, float(rows[0]["score"]) if rows else 0.0, cands


def receipt_out(conn, rid) -> dict:
    r = conn.execute("""SELECT r.*, s.name AS store_name, c.name AS chain_name FROM receipts r
                        LEFT JOIN stores s ON s.id = r.store_id LEFT JOIN chains c ON c.id = s.chain_id
                        WHERE r.id=%s""", (rid,)).fetchone()
    lines = conn.execute("""SELECT l.*, p.name AS product_name FROM receipt_lines l LEFT JOIN products p ON p.id = l.product_id
                            WHERE l.receipt_id=%s ORDER BY l.line_no""", (rid,)).fetchall()
    return {
        "id": str(r["id"]), "status": r["status"], "store_id": r["store_id"], "store_name": r["store_name"],
        "chain_name": r["chain_name"], "purchased_at": r["purchased_at"].isoformat() if r["purchased_at"] else None,
        "total_printed": float(r["total_printed"]) if r["total_printed"] is not None else None,
        "total_parsed": float(r["total_parsed"]) if r["total_parsed"] is not None else None,
        "totals_match": r["total_printed"] is not None and abs(float(r["total_printed"]) - float(r["total_parsed"] or 0)) <= 0.05,
        "credits_awarded": r["credits_awarded"],
        "lines": [{"line_no": l["line_no"], "raw_text": l["raw_text"], "qty": float(l["qty"]),
                   "line_total": float(l["line_total"]), "discount": float(l["discount"]),
                   "product_id": l["product_id"], "product_name": l["product_name"],
                   "match_confidence": l["match_confidence"], "needs_review": l["product_id"] is None,
                   "candidates": l["candidates"] or []} for l in lines],
    }


@router.post("", status_code=201)
async def upload_receipt(image: UploadFile = File(...), store_id: int | None = Form(default=None),
                         user=Depends(current_user), conn=Depends(get_conn)):
    data = await image.read()
    if not data or len(data) > 15 * 1024 * 1024:
        raise HTTPException(422, detail={"code": "invalid_image", "message": "Immagine vuota o oltre 15 MB"})
    today_n = conn.execute("""SELECT count(*) AS n FROM receipts WHERE user_id=%s AND status='validated'
                              AND created_at > now() - interval '1 day'""", (user["id"],)).fetchone()["n"]
    limit = 20 if settings.dev_mode else settings.receipts_per_day   # in sviluppo si prova più volte
    if today_n >= limit:
        raise HTTPException(429, detail={"code": "daily_limit", "message": f"Massimo {limit} scontrini validati al giorno"})
    sha = hashlib.sha256(data).hexdigest()
    if settings.ocr_provider == "demo":                 # in demo la stessa foto di prova può essere riusata
        sha = hashlib.sha256(data + uuid.uuid4().bytes).hexdigest()
    if conn.execute("SELECT 1 FROM receipts WHERE image_sha256=%s", (sha,)).fetchone():
        raise HTTPException(409, detail={"code": "duplicate", "message": "Questo scontrino è già stato caricato"})

    run = conn.execute("""SELECT * FROM optimization_runs WHERE user_id=%s AND started_at IS NOT NULL AND closed_at IS NULL
                          ORDER BY started_at DESC LIMIT 1""", (user["id"],)).fetchone()
    if store_id is None and run:
        store_id = run["chosen_stores"][0]
    if store_id is None:                                # negozio più vicino a casa
        lat, lon, _ = search_center(conn, user)
        near = conn.execute("""SELECT id FROM stores ORDER BY location <-> ST_MakePoint(%s,%s)::geography LIMIT 1""",
                            (lon, lat)).fetchone()
        if not near:
            raise HTTPException(409, detail={"code": "no_stores", "message": "Nessun negozio noto in zona"})
        store_id = near["id"]
    store = conn.execute("SELECT id, chain_id FROM stores WHERE id=%s", (store_id,)).fetchone()
    if not store:
        raise HTTPException(404, detail={"code": "not_found", "message": "Negozio inesistente"})

    try:
        text = extract_text(conn, data, store_id, run, seed=sha[:8])
    except OcrError as e:
        raise HTTPException(503, detail={"code": "ocr_unavailable", "message": str(e)})
    parsed = parse_receipt_text(text)
    if not parsed.lines:
        raise HTTPException(422, detail={"code": "unreadable", "message": "Non riesco a leggere le righe: riprova con più luce"})

    UPLOAD_DIR.mkdir(exist_ok=True)
    key = f"{uuid.uuid4()}.jpg"
    (UPLOAD_DIR / key).write_bytes(data)
    rid = conn.execute("""INSERT INTO receipts(user_id, store_id, status, image_key, image_sha256, purchased_at,
                            total_printed, total_parsed, ocr_raw, optimization_run_id)
                          VALUES (%s,%s,'matched',%s,%s,now(),%s,%s,%s,%s) RETURNING id""",
                       (user["id"], store_id, key, sha, parsed.total_printed, parsed.total_parsed,
                        Jsonb({"text": text, "vat": parsed.vat_number}), run["id"] if run else None)).fetchone()["id"]
    for l in parsed.lines:
        pid, conf, cands = match_line(conn, store["chain_id"], l.raw_text)
        conn.execute("""INSERT INTO receipt_lines(receipt_id, line_no, raw_text, qty, unit_price, line_total, discount,
                          product_id, match_confidence, candidates) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                     (rid, l.line_no, l.raw_text, l.qty, l.unit_price, l.line_total, l.discount, pid, conf,
                      Jsonb(cands) if pid is None else None))
    return receipt_out(conn, rid)


@router.get("/{receipt_id}")
def get_receipt(receipt_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    if not conn.execute("SELECT 1 FROM receipts WHERE id=%s AND user_id=%s", (receipt_id, user["id"])).fetchone():
        raise HTTPException(404, detail={"code": "not_found", "message": "Scontrino non trovato"})
    return receipt_out(conn, receipt_id)


class LineFix(BaseModel):
    product_id: int | None       # None = ignora la riga


@router.patch("/{receipt_id}/lines/{line_no}")
def fix_line(receipt_id: uuid.UUID, line_no: int, body: LineFix, user=Depends(current_user), conn=Depends(get_conn)):
    r = conn.execute("SELECT status FROM receipts WHERE id=%s AND user_id=%s", (receipt_id, user["id"])).fetchone()
    if not r:
        raise HTTPException(404, detail={"code": "not_found", "message": "Scontrino non trovato"})
    if r["status"] == "validated":
        raise HTTPException(409, detail={"code": "already_validated", "message": "Scontrino già confermato"})
    conn.execute("UPDATE receipt_lines SET product_id=%s, match_confidence=1.0 WHERE receipt_id=%s AND line_no=%s",
                 (body.product_id, receipt_id, line_no))
    return receipt_out(conn, receipt_id)


@router.post("/{receipt_id}/confirm")
def confirm(receipt_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    r = conn.execute("SELECT * FROM receipts WHERE id=%s AND user_id=%s FOR UPDATE", (receipt_id, user["id"])).fetchone()
    if not r:
        raise HTTPException(404, detail={"code": "not_found", "message": "Scontrino non trovato"})
    if r["status"] == "validated":
        raise HTTPException(409, detail={"code": "already_validated", "message": "Scontrino già confermato"})
    if r["total_printed"] is not None and abs(float(r["total_printed"]) - float(r["total_parsed"])) > 0.05:
        raise HTTPException(422, detail={"code": "total_mismatch",
                                         "message": "La somma delle righe non corrisponde al totale: riscatta la foto"})
    if r["purchased_at"] and r["purchased_at"] < dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=7):
        raise HTTPException(422, detail={"code": "too_old", "message": "Lo scontrino ha più di 7 giorni"})
    store = conn.execute("SELECT chain_id FROM stores WHERE id=%s", (r["store_id"],)).fetchone()
    lines = conn.execute("SELECT * FROM receipt_lines WHERE receipt_id=%s AND product_id IS NOT NULL", (receipt_id,)).fetchall()
    updated, pairs = 0, set()
    for l in lines:
        paid = round((float(l["line_total"]) - float(l["discount"])) / float(l["qty"]), 2)
        if paid <= 0:
            continue
        conn.execute("""INSERT INTO price_observations(store_id, product_id, source, source_ref, price_regular, observed_at, reported_by)
                        VALUES (%s,%s,'receipt',%s,%s,now(),%s)""", (r["store_id"], l["product_id"], str(receipt_id), paid, user["id"]))
        conn.execute("""INSERT INTO product_aliases(product_id, chain_id, source, alias_text, confidence, confirmed_by_users)
                        VALUES (%s,%s,'receipt',%s,0.8,1)
                        ON CONFLICT (chain_id, source, alias_text) DO UPDATE SET confirmed_by_users = product_aliases.confirmed_by_users + 1""",
                     (l["product_id"], store["chain_id"], normalize_alias(l["raw_text"])))
        pairs.add((r["store_id"], l["product_id"]))
    accepted = 0
    for sid, pid in pairs:
        res = resolve_pair(conn, sid, pid)
        if res and res["source"] == "receipt":
            accepted += 1
        updated += 1
    outliers = conn.execute("SELECT count(*) AS n FROM price_observations WHERE source_ref=%s AND is_outlier",
                            (str(receipt_id),)).fetchone()["n"]
    trust = 0.02 * (len(pairs) - outliers) - 0.05 * outliers
    # crediti e serie settimanale
    credits, bonus = settings.credits_per_receipt, 0
    last = user["last_receipt_at"]
    now = dt.datetime.now(dt.timezone.utc)
    week, last_week = now.isocalendar()[:2], last.isocalendar()[:2] if last else None
    prev_week = (now - dt.timedelta(days=7)).isocalendar()[:2]
    if last_week == week:
        streak = max(1, user["streak_weeks"])
    elif last_week == prev_week:
        streak, bonus = user["streak_weeks"] + 1, settings.credits_streak_bonus
    else:
        streak = 1
    credits += bonus
    conn.execute("""UPDATE users SET credits=credits+%s, streak_weeks=%s, last_receipt_at=now(),
                    trust_score=LEAST(1, GREATEST(0, trust_score + %s)) WHERE id=%s""", (credits, streak, trust, user["id"]))
    conn.execute("INSERT INTO credit_ledger(user_id, delta, reason, receipt_id) VALUES (%s,%s,'receipt_validated',%s)",
                 (user["id"], credits, receipt_id))
    conn.execute("UPDATE receipts SET status='validated', credits_awarded=%s WHERE id=%s", (credits, receipt_id))
    saving = None
    if r["optimization_run_id"]:
        run = conn.execute("SELECT * FROM optimization_runs WHERE id=%s", (r["optimization_run_id"],)).fetchone()
        if run and run["closed_at"] is None:
            saving = float(run["estimated_saving"] or 0)
            conn.execute("UPDATE optimization_runs SET realized_saving=%s, closed_at=now() WHERE id=%s", (saving, run["id"]))
    fresh = conn.execute("SELECT credits FROM users WHERE id=%s", (user["id"],)).fetchone()
    return {"credits_awarded": credits, "streak_bonus": bonus, "streak_weeks": streak, "credits_total": fresh["credits"],
            "prices_submitted": len(pairs), "prices_accepted_now": accepted, "outliers": outliers, "saving_confirmed": saving}
