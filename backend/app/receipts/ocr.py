"""Provider OCR.

- google_vision: Google Cloud Vision DOCUMENT_TEXT_DETECTION via REST (serve GOOGLE_VISION_API_KEY).
- demo: non legge l'immagine; genera il testo di uno scontrino realistico dai prezzi nel DB
  (gli articoli della spesa in corso in quel negozio, oppure 6 articoli a caso). Il testo poi
  passa dal VERO parser e dal VERO matching, quindi la pipeline è esercitata per intero.
"""
from __future__ import annotations

import base64
import datetime as dt

import httpx

from ..config import settings
from ..seed import hash01, receipt_alias


class OcrError(Exception):
    pass


def google_vision_text(image: bytes) -> str:
    if not settings.google_vision_api_key:
        raise OcrError("GOOGLE_VISION_API_KEY non configurata")
    body = {"requests": [{"image": {"content": base64.b64encode(image).decode()},
                          "features": [{"type": "DOCUMENT_TEXT_DETECTION"}],
                          "imageContext": {"languageHints": ["it"]}}]}
    r = httpx.post("https://vision.googleapis.com/v1/images:annotate",
                   params={"key": settings.google_vision_api_key}, json=body, timeout=30)
    r.raise_for_status()
    resp = r.json()["responses"][0]
    if "error" in resp:
        raise OcrError(resp["error"].get("message", "Errore Vision"))
    return resp.get("fullTextAnnotation", {}).get("text", "")


def demo_receipt_text(conn, store_id: int, run: dict | None, seed: str) -> str:
    store = conn.execute("""SELECT s.name, s.address, c.name AS chain, c.id AS chain_id FROM stores s
                            JOIN chains c ON c.id = s.chain_id WHERE s.id=%s""", (store_id,)).fetchone()
    picks: list[tuple[int, int]] = []                     # (product_id, confezioni)
    if run:
        scen = (run["scenario_multi"] if run["chosen_scenario"] == "B" else run["scenario_single"]) or {}
        for line in scen.get("lines", []):
            if line["store_id"] == store_id:
                picks.append((line["product_id"], line["packs"]))
    if not picks:
        rows = conn.execute("""SELECT product_id FROM store_prices WHERE store_id=%s ORDER BY md5(product_id::text || %s) LIMIT 6""",
                            (store_id, seed)).fetchall()
        picks = [(r["product_id"], 1) for r in rows]
    out = [store["chain"].upper(), store["address"].upper(), "P.IVA 0" + str(10000000000 + store_id)[1:],
           "DOCUMENTO COMMERCIALE", "DESCRIZIONE                 PREZZO"]
    total = 0.0
    for n, (pid, packs) in enumerate(picks):
        p = conn.execute("""SELECT p.name, sp.price_regular, sp.price_promo, sp.promo_condition
                            FROM products p JOIN store_prices sp ON sp.product_id=p.id AND sp.store_id=%s
                            WHERE p.id=%s""", (store_id, pid)).fetchone()
        if not p:
            continue
        alias = receipt_alias(p["name"])
        if n == 1:                                   # una riga "sporca" che richiede conferma dell'utente
            alias = "".join(ch for ch in alias if ch not in "AEIOU")[:14]
        unit = float(p["price_regular"])
        if packs > 1:
            out.append(f"{packs} X {unit:.2f}".replace(".", ","))
        line_total = round(unit * packs, 2)
        out.append(f"{alias:<26}{line_total:>8.2f}".replace(".", ","))
        total += line_total
        if p["price_promo"] is not None and p["promo_condition"] == "flyer":
            disc = round((unit - float(p["price_promo"])) * packs, 2)
            out.append(f"{'SCONTO VOLANTINO':<26}{-disc:>8.2f}".replace(".", ","))
            total -= disc
    out += [f"{'TOTALE COMPLESSIVO':<26}{total:>8.2f}".replace(".", ","),
            f"{'PAGAMENTO ELETTRONICO':<26}{total:>8.2f}".replace(".", ","),
            dt.datetime.now().strftime("%d-%m-%Y %H:%M")]
    return "\n".join(out)


def extract_text(conn, image: bytes, store_id: int, run: dict | None, seed: str) -> str:
    if settings.ocr_provider == "google_vision":
        return google_vision_text(image)
    return demo_receipt_text(conn, store_id, run, seed)


__all__ = ["extract_text", "OcrError", "hash01"]
