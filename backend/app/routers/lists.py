from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, HTTPException, Response
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field, model_validator

from ..auth import current_user, is_premium, premium_required
from ..config import settings
from ..db import get_conn
from ..optimizer import OptimizerConfig, ScenarioResult, StoreRef, optimize
from ..pricing import build_cost_matrix, nearby_stores, promo_label, user_cards
from ..users import search_center

router = APIRouter(prefix="/v1", tags=["liste"])

ITEM_SQL = """
    SELECT i.*, coalesce(p.name, g.name) AS label, coalesce(cp.name, cg.name) AS category,
           p.brand, p.generic_product_id AS product_generic_id
    FROM shopping_list_items i
    LEFT JOIN products p ON p.id = i.product_id
    LEFT JOIN generic_products g ON g.id = i.generic_product_id
    LEFT JOIN categories cp ON cp.id = p.category_id
    LEFT JOIN categories cg ON cg.id = g.category_id
    WHERE i.list_id = %s ORDER BY i.position
"""


def get_list(conn, list_id: uuid.UUID, user: dict) -> dict:
    lst = conn.execute("SELECT * FROM shopping_lists WHERE id=%s AND user_id=%s", (list_id, user["id"])).fetchone()
    if not lst:
        raise HTTPException(404, detail={"code": "not_found", "message": "Lista non trovata"})
    return lst


def touch(conn, list_id):
    conn.execute("UPDATE shopping_lists SET updated_at=now(), status='draft' WHERE id=%s AND status <> 'archived'", (list_id,))


def context(conn, user, lst):
    """Store utilizzabili (nel raggio, non esclusi) e carte fedeltà dell'utente."""
    lat, lon, radius = search_center(conn, user, lst)
    stores = [s for s in nearby_stores(conn, lat, lon, radius, user["id"]) if s["pref"] != -1]
    return stores, user_cards(conn, user["id"]), radius


# ---------------- Liste ----------------
@router.get("/lists")
def lists(user=Depends(current_user), conn=Depends(get_conn)):
    return conn.execute("""
        SELECT l.id, l.name, l.status, l.updated_at, count(i.id) AS item_count,
               count(i.id) FILTER (WHERE i.is_checked) AS checked_count
        FROM shopping_lists l LEFT JOIN shopping_list_items i ON i.list_id = l.id
        WHERE l.user_id=%s AND l.status <> 'archived' GROUP BY l.id ORDER BY l.updated_at DESC""", (user["id"],)).fetchall()


class ListIn(BaseModel):
    name: str = Field(default="Spesa", min_length=1, max_length=60)


@router.post("/lists", status_code=201)
def create_list(body: ListIn, user=Depends(current_user), conn=Depends(get_conn)):
    n = conn.execute("SELECT count(*) AS n FROM shopping_lists WHERE user_id=%s AND status<>'archived'", (user["id"],)).fetchone()["n"]
    if n >= settings.free_max_lists and not is_premium(user):
        raise premium_required("Con il piano Free puoi avere 1 lista attiva")
    lst = conn.execute("INSERT INTO shopping_lists(user_id, name, max_stores) VALUES (%s,%s,%s) RETURNING id, name, status",
                       (user["id"], body.name, 3 if is_premium(user) else 2)).fetchone()
    return lst


@router.get("/lists/{list_id}")
def list_detail(list_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    lst = get_list(conn, list_id, user)
    items = conn.execute(ITEM_SQL, (list_id,)).fetchall()
    best: dict[str, dict] = {}
    if user["home_location"] is not None or lst["search_center"] is not None:
        stores, cards, _ = context(conn, user, lst)
        by_id = {s["id"]: s for s in stores}
        cost, pick = build_cost_matrix(conn, items, list(by_id), cards)
        today = dt.date.today()
        for it in items:
            per = cost[str(it["id"])]
            if per:
                sid = min(per, key=per.get)
                row, packs = pick[str(it["id"])][sid]
                best[str(it["id"])] = {"total": per[sid], "unit_price": round(per[sid] / packs, 2), "packs": packs,
                                       "store_id": sid, "store_name": by_id[sid]["name"], "chain_name": by_id[sid]["chain_name"],
                                       "product_name": row.product_name, "promo": promo_label(row, cards, today),
                                       "confidence": row.confidence, "source": row.source,
                                       "days_old": (dt.datetime.now(dt.timezone.utc) - row.last_observed_at).days}
    out_items = [{
        "id": str(it["id"]), "position": it["position"], "product_id": it["product_id"],
        "generic_product_id": it["generic_product_id"], "label": it["label"], "brand": it["brand"],
        "category": it["category"], "quantity": float(it["quantity"]), "quantity_unit": it["quantity_unit"],
        "brand_lock": it["brand_lock"], "is_checked": it["is_checked"], "can_accept_equivalents": bool(it["product_generic_id"]),
        "best": best.get(str(it["id"])),
    } for it in items]
    session = active_session(conn, user, list_id)
    return {"id": str(lst["id"]), "name": lst["name"], "status": lst["status"], "items": out_items,
            "estimate_total": round(sum(b["total"] for b in best.values()), 2), "active_session": session}


@router.patch("/lists/{list_id}")
def rename_list(list_id: uuid.UUID, body: ListIn, user=Depends(current_user), conn=Depends(get_conn)):
    get_list(conn, list_id, user)
    conn.execute("UPDATE shopping_lists SET name=%s, updated_at=now() WHERE id=%s", (body.name, list_id))
    return {"id": str(list_id), "name": body.name}


@router.delete("/lists/{list_id}", status_code=204)
def delete_list(list_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    get_list(conn, list_id, user)
    conn.execute("UPDATE shopping_lists SET status='archived' WHERE id=%s", (list_id,))
    return Response(status_code=204)


# ---------------- Voci ----------------
class ItemIn(BaseModel):
    product_id: int | None = None
    generic_product_id: int | None = None
    quantity: float = Field(default=1, gt=0, le=99)

    @model_validator(mode="after")
    def exactly_one(self):
        if (self.product_id is None) == (self.generic_product_id is None):
            raise ValueError("Indica product_id oppure generic_product_id")
        return self


@router.post("/lists/{list_id}/items", status_code=201)
def add_item(list_id: uuid.UUID, body: ItemIn, user=Depends(current_user), conn=Depends(get_conn)):
    get_list(conn, list_id, user)
    if body.product_id is not None:
        p = conn.execute("SELECT is_private_label, generic_product_id FROM products WHERE id=%s", (body.product_id,)).fetchone()
        if not p:
            raise HTTPException(404, detail={"code": "not_found", "message": "Prodotto inesistente"})
        if p["is_private_label"]:          # una marca del distributore diventa il generico equivalente
            body = ItemIn(generic_product_id=p["generic_product_id"], quantity=body.quantity)
    elif not conn.execute("SELECT 1 FROM generic_products WHERE id=%s", (body.generic_product_id,)).fetchone():
        raise HTTPException(404, detail={"code": "not_found", "message": "Prodotto inesistente"})
    existing = conn.execute("""SELECT id FROM shopping_list_items WHERE list_id=%s AND
                               product_id IS NOT DISTINCT FROM %s AND generic_product_id IS NOT DISTINCT FROM %s""",
                            (list_id, body.product_id, body.generic_product_id)).fetchone()
    if existing:
        conn.execute("UPDATE shopping_list_items SET quantity=quantity+%s WHERE id=%s", (body.quantity, existing["id"]))
        item_id = existing["id"]
    else:
        pos = conn.execute("SELECT coalesce(max(position),0)+1 AS p FROM shopping_list_items WHERE list_id=%s", (list_id,)).fetchone()["p"]
        item_id = conn.execute("""INSERT INTO shopping_list_items(list_id, position, product_id, generic_product_id, quantity)
                                  VALUES (%s,%s,%s,%s,%s) RETURNING id""",
                               (list_id, pos, body.product_id, body.generic_product_id, body.quantity)).fetchone()["id"]
    touch(conn, list_id)
    return {"id": str(item_id)}


class ItemPatch(BaseModel):
    quantity: float | None = Field(default=None, gt=0, le=99)
    brand_lock: bool | None = None
    is_checked: bool | None = None
    accept_equivalents: bool | None = None


@router.patch("/lists/{list_id}/items/{item_id}")
def patch_item(list_id: uuid.UUID, item_id: uuid.UUID, body: ItemPatch, user=Depends(current_user), conn=Depends(get_conn)):
    get_list(conn, list_id, user)
    it = conn.execute("SELECT * FROM shopping_list_items WHERE id=%s AND list_id=%s", (item_id, list_id)).fetchone()
    if not it:
        raise HTTPException(404, detail={"code": "not_found", "message": "Voce non trovata"})
    if body.quantity is not None:
        conn.execute("UPDATE shopping_list_items SET quantity=%s WHERE id=%s", (body.quantity, item_id))
    if body.brand_lock is not None:
        conn.execute("UPDATE shopping_list_items SET brand_lock=%s WHERE id=%s", (body.brand_lock, item_id))
    if body.is_checked is not None:
        conn.execute("UPDATE shopping_list_items SET is_checked=%s WHERE id=%s", (body.is_checked, item_id))
    if body.accept_equivalents and it["product_id"]:
        g = conn.execute("SELECT generic_product_id FROM products WHERE id=%s", (it["product_id"],)).fetchone()["generic_product_id"]
        if g:
            conn.execute("UPDATE shopping_list_items SET product_id=NULL, generic_product_id=%s WHERE id=%s", (g, item_id))
    if body.is_checked is None or len(body.model_fields_set) > 1:
        touch(conn, list_id)
    return {"id": str(item_id)}


@router.delete("/lists/{list_id}/items/{item_id}", status_code=204)
def delete_item(list_id: uuid.UUID, item_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    get_list(conn, list_id, user)
    conn.execute("DELETE FROM shopping_list_items WHERE id=%s AND list_id=%s", (item_id, list_id))
    touch(conn, list_id)
    return Response(status_code=204)


# ---------------- Ottimizzazione ----------------
def scenario_json(r: ScenarioResult, n_items: int, pick, cost, cards, today) -> dict:
    lines = []
    for iid, sid in r.assignment.items():
        row, packs = pick[iid][sid]
        lines.append({"item_id": iid, "store_id": sid, "product_id": row.product_id, "product_name": row.product_name,
                      "packs": packs, "cost": cost[iid][sid], "promo": promo_label(row, cards, today),
                      "confidence": row.confidence})
    return {"stores": r.order or r.stores, "total": r.total, "reference": r.reference, "saving_abs": r.saving_abs,
            "saving_pct": r.saving_pct, "covered": n_items - len(r.missing), "item_count": n_items,
            "missing": r.missing, "route_m": round(r.route_km * 1000), "penalty": r.penalty,
            "gain_vs_single": r.gain_vs_single, "worth_it": r.worth_it, "lines": lines}


@router.post("/lists/{list_id}/optimize")
def optimize_list(list_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    lst = get_list(conn, list_id, user)
    items = conn.execute(ITEM_SQL, (list_id,)).fetchall()
    if not items:
        raise HTTPException(409, detail={"code": "empty_list", "message": "La lista è vuota"})
    stores, cards, radius = context(conn, user, lst)
    if not stores:
        raise HTTPException(409, detail={"code": "no_stores", "message": "Nessun supermercato nel raggio scelto"})
    premium = is_premium(user)
    today = dt.date.today()
    cost, pick = build_cost_matrix(conn, items, [s["id"] for s in stores], cards, today)
    refs = [StoreRef(s["id"], s["lat"], s["lon"], s["dist_m"]) for s in stores]
    cfg = OptimizerConfig(max_stores=3 if premium else 2)
    ids = [str(i["id"]) for i in items]
    a, alts, b, ref, tried = optimize(refs, ids, cost, cfg)
    n = len(ids)
    sa = scenario_json(a, n, pick, cost, cards, today)
    sb = scenario_json(b, n, pick, cost, cards, today) if b else None
    reference_total = round(sum(ref.get(i, 0) for i in ids), 2)
    run_id = conn.execute("""INSERT INTO optimization_runs(list_id, user_id, scenario_single, scenario_multi, reference_total)
                             VALUES (%s,%s,%s,%s,%s) RETURNING id""",
                          (list_id, user["id"], Jsonb(sa), Jsonb(sb) if sb else None, reference_total)).fetchone()["id"]
    conn.execute("UPDATE shopping_lists SET status='optimized' WHERE id=%s", (list_id,))
    public_b = sb
    if sb and not premium:                                 # gating Premium lato server
        public_b = {"locked": True, "gain_vs_single": sb["gain_vs_single"], "worth_it": sb["worth_it"],
                    "store_count": len(sb["stores"]), "route_m": sb["route_m"]}
    used = {sid for s in [sa, sb] if s for sid in s["stores"]} | {r.stores[0] for r in alts}
    return {
        "run_id": str(run_id), "item_count": n, "reference_total": reference_total, "radius_m": radius,
        "combos_evaluated": tried, "is_premium": premium,
        "items": [{"id": str(i["id"]), "label": i["label"], "quantity": float(i["quantity"])} for i in items],
        "stores": [{"id": s["id"], "name": s["name"], "chain_name": s["chain_name"], "lat": s["lat"], "lon": s["lon"],
                    "dist_m": round(s["dist_m"]), "click_collect": s["has_click_collect"], "used": s["id"] in used}
                   for s in stores],
        "scenario_a": sa,
        "alternatives": [scenario_json(r, n, pick, cost, cards, today) for r in alts],
        "scenario_b": public_b,
    }


class StartIn(BaseModel):
    scenario: str = Field(pattern="^[AB]$")


def active_session(conn, user, list_id=None):
    sql = """SELECT r.*, l.name AS list_name FROM optimization_runs r JOIN shopping_lists l ON l.id = r.list_id
             WHERE r.user_id=%s AND r.started_at IS NOT NULL AND r.closed_at IS NULL"""
    args: list = [user["id"]]
    if list_id:
        sql += " AND r.list_id=%s"
        args.append(list_id)
    r = conn.execute(sql + " ORDER BY r.started_at DESC LIMIT 1", args).fetchone()
    if not r:
        return None
    scen = r["scenario_multi"] if r["chosen_scenario"] == "B" else r["scenario_single"]
    names = {s["id"]: s for s in conn.execute(
        "SELECT s.id, s.name, c.name AS chain_name FROM stores s JOIN chains c ON c.id=s.chain_id WHERE s.id = ANY(%s)",
        (list(r["chosen_stores"]),))}
    return {"run_id": str(r["id"]), "list_id": str(r["list_id"]), "list_name": r["list_name"], "scenario": r["chosen_scenario"],
            "stores": [{"id": sid, "name": names[sid]["name"], "chain_name": names[sid]["chain_name"]} for sid in r["chosen_stores"]],
            "lines": scen["lines"], "estimated_saving": float(r["estimated_saving"] or 0),
            "started_at": r["started_at"].isoformat()}


@router.post("/runs/{run_id}/start")
def start_run(run_id: uuid.UUID, body: StartIn, user=Depends(current_user), conn=Depends(get_conn)):
    r = conn.execute("SELECT * FROM optimization_runs WHERE id=%s AND user_id=%s", (run_id, user["id"])).fetchone()
    if not r:
        raise HTTPException(404, detail={"code": "not_found", "message": "Confronto non trovato"})
    if body.scenario == "B":
        if not is_premium(user):
            raise premium_required("Lo scenario multi-negozio è disponibile con Premium")
        if not r["scenario_multi"]:
            raise HTTPException(409, detail={"code": "no_scenario_b", "message": "Nessuno scenario multi-negozio"})
    scen = r["scenario_multi"] if body.scenario == "B" else r["scenario_single"]
    conn.execute("UPDATE optimization_runs SET closed_at=now() WHERE user_id=%s AND started_at IS NOT NULL AND closed_at IS NULL",
                 (user["id"],))
    conn.execute("UPDATE shopping_list_items SET is_checked=FALSE WHERE list_id=%s", (r["list_id"],))
    conn.execute("""UPDATE optimization_runs SET chosen_scenario=%s, chosen_stores=%s, estimated_saving=%s, started_at=now()
                    WHERE id=%s""", (body.scenario, scen["stores"], max(0, scen["saving_abs"]), run_id))
    return active_session(conn, user)


@router.post("/runs/{run_id}/cancel")
def cancel_run(run_id: uuid.UUID, user=Depends(current_user), conn=Depends(get_conn)):
    conn.execute("UPDATE optimization_runs SET closed_at=now() WHERE id=%s AND user_id=%s AND closed_at IS NULL",
                 (run_id, user["id"]))
    return {"ok": True}


@router.get("/sessions/active")
def get_active(user=Depends(current_user), conn=Depends(get_conn)):
    return active_session(conn, user)
