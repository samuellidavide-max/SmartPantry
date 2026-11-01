"""Dal database alla matrice dei costi cost[voce][store] per un utente."""
from __future__ import annotations

import datetime as dt
import math
from dataclasses import dataclass

from .config import settings


@dataclass
class PriceRow:
    store_id: int
    product_id: int
    product_name: str
    is_private_label: bool
    net_qty: float
    net_unit: str
    regular: float
    promo: float | None
    cond: str
    promo_from: dt.date | None
    promo_to: dt.date | None
    promo_details: dict | None
    chain_id: int
    source: str
    confidence: float
    last_observed_at: dt.datetime


def nearby_stores(conn, lat: float, lon: float, radius_m: int, user_id=None):
    sql = """
        SELECT s.id, s.name, s.address, s.city, s.cap, s.chain_id, c.name AS chain_name, c.slug AS chain_slug,
               c.loyalty_card_name, c.is_discount, s.has_click_collect,
               ST_Y(s.location::geometry) AS lat, ST_X(s.location::geometry) AS lon,
               ST_Distance(s.location, ST_MakePoint(%(lon)s, %(lat)s)::geography) AS dist_m,
               coalesce(p.pref, 0) AS pref
        FROM stores s JOIN chains c ON c.id = s.chain_id
        LEFT JOIN user_store_prefs p ON p.store_id = s.id AND p.user_id = %(uid)s
        WHERE s.is_active AND ST_DWithin(s.location, ST_MakePoint(%(lon)s, %(lat)s)::geography, %(r)s)
        ORDER BY s.location <-> ST_MakePoint(%(lon)s, %(lat)s)::geography
    """
    return conn.execute(sql, {"lat": lat, "lon": lon, "r": radius_m, "uid": user_id}).fetchall()


def user_cards(conn, user_id) -> set[int]:
    return {r["chain_id"] for r in conn.execute("SELECT chain_id FROM user_loyalty_cards WHERE user_id=%s", (user_id,))}


def unit_price(row: PriceRow, cards: set[int], today: dt.date) -> float:
    """Prezzo di 1 confezione per questo utente oggi (promo semplici incluse)."""
    if row.promo is not None and row.cond not in ("multi_buy",) and row.promo_to and \
            (row.promo_from or today) <= today <= row.promo_to and \
            (row.cond != "loyalty_card" or row.chain_id in cards):
        return row.promo
    return row.regular


def promo_active(row: PriceRow, cards: set[int], today: dt.date) -> bool:
    if row.cond == "none" or not row.promo_to or not ((row.promo_from or today) <= today <= row.promo_to):
        return False
    return row.cond != "loyalty_card" or row.chain_id in cards


def packs_needed(item: dict, row: PriceRow) -> int:
    q, unit = float(item["quantity"]), item["quantity_unit"]
    if unit == "pz" or unit != row.net_unit:
        return max(1, math.ceil(q))            # quantità espressa in confezioni
    return max(1, math.ceil(q / float(row.net_qty)))


def line_cost(row: PriceRow, packs: int, cards: set[int], today: dt.date) -> float:
    if row.cond == "multi_buy" and promo_active(row, cards, today):
        d = row.promo_details or {"buy": 3, "pay": 2}
        free = (packs // d["buy"]) * (d["buy"] - d["pay"])
        return row.regular * (packs - free)
    return unit_price(row, cards, today) * packs


def candidates_for_items(conn, items: list[dict]) -> dict[str, list[int]]:
    out: dict[str, list[int]] = {}
    generic_ids = [i["generic_product_id"] for i in items if i["generic_product_id"]]
    by_generic: dict[int, list[dict]] = {}
    if generic_ids:
        for r in conn.execute("SELECT id, generic_product_id, is_private_label FROM products WHERE generic_product_id = ANY(%s)",
                              (generic_ids,)):
            by_generic.setdefault(r["generic_product_id"], []).append(r)
    for it in items:
        if it["product_id"]:
            out[str(it["id"])] = [it["product_id"]]
        else:
            out[str(it["id"])] = [p["id"] for p in by_generic.get(it["generic_product_id"], [])
                                  if not (it["brand_lock"] and p["is_private_label"])]
    return out


def load_prices(conn, store_ids: list[int], product_ids: list[int]) -> dict[tuple[int, int], PriceRow]:
    if not store_ids or not product_ids:
        return {}
    rows = conn.execute("""
        SELECT sp.*, p.name AS product_name, p.is_private_label, p.net_qty, p.net_unit, s.chain_id
        FROM store_prices sp JOIN products p ON p.id = sp.product_id JOIN stores s ON s.id = sp.store_id
        WHERE sp.store_id = ANY(%s) AND sp.product_id = ANY(%s)
          AND sp.last_observed_at > now() - make_interval(days => %s)
    """, (store_ids, product_ids, settings.price_max_age_days)).fetchall()
    return {(r["store_id"], r["product_id"]): PriceRow(
        r["store_id"], r["product_id"], r["product_name"], r["is_private_label"], float(r["net_qty"]), r["net_unit"],
        float(r["price_regular"]), float(r["price_promo"]) if r["price_promo"] is not None else None,
        r["promo_condition"], r["promo_valid_from"], r["promo_valid_to"], r["promo_details"], r["chain_id"],
        r["primary_source"], float(r["confidence"]), r["last_observed_at"]) for r in rows}


def build_cost_matrix(conn, items: list[dict], store_ids: list[int], cards: set[int], today: dt.date | None = None):
    """cost[item_id][store_id] = costo minimo; pick[item_id][store_id] = (PriceRow, confezioni)."""
    today = today or dt.date.today()
    cands = candidates_for_items(conn, items)
    prices = load_prices(conn, store_ids, sorted({p for ps in cands.values() for p in ps}))
    cost: dict[str, dict[int, float]] = {}
    pick: dict[str, dict[int, tuple[PriceRow, int]]] = {}
    for it in items:
        iid = str(it["id"])
        cost[iid], pick[iid] = {}, {}
        for sid in store_ids:
            best = None
            for pid in cands[iid]:
                row = prices.get((sid, pid))
                if not row:
                    continue
                packs = packs_needed(it, row)
                c = line_cost(row, packs, cards, today)
                if best is None or c < best[0] - 1e-9:
                    best = (c, row, packs)
            if best:
                cost[iid][sid] = round(best[0], 2)
                pick[iid][sid] = (best[1], best[2])
    return cost, pick


def promo_label(row: PriceRow, cards: set[int], today: dt.date) -> dict | None:
    if row.cond == "none" or not row.promo_to or not ((row.promo_from or today) <= today <= row.promo_to):
        return None
    return {"condition": row.cond, "valid_to": row.promo_to.isoformat(),
            "applies": row.cond != "loyalty_card" or row.chain_id in cards,
            "details": row.promo_details}
