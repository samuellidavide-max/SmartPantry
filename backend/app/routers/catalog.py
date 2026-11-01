from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ..auth import current_user
from ..config import settings
from ..db import get_conn
from ..pricing import nearby_stores
from ..seed import seed_stores_near
from ..users import search_center

router = APIRouter(prefix="/v1", tags=["catalogo"])


def store_out(s: dict) -> dict:
    return {"id": s["id"], "name": s["name"], "address": s["address"], "chain_id": s["chain_id"],
            "chain_name": s["chain_name"], "chain_slug": s["chain_slug"], "is_discount": s["is_discount"],
            "lat": s["lat"], "lon": s["lon"], "dist_m": round(s["dist_m"]), "click_collect": s["has_click_collect"],
            "pref": s["pref"], "loyalty_card_name": s["loyalty_card_name"]}


@router.get("/chains")
def chains(conn=Depends(get_conn)):
    return conn.execute("SELECT id, name, slug, loyalty_card_name, is_discount, online_portal_url FROM chains ORDER BY name").fetchall()


@router.get("/stores/nearby")
def stores_nearby(lat: float | None = None, lon: float | None = None, radius_m: int | None = None,
                  user=Depends(current_user), conn=Depends(get_conn)):
    if lat is None or lon is None:
        lat, lon, r = search_center(conn, user)
        radius_m = radius_m or r
    radius_m = min(radius_m or user["search_radius_m"], 20000)
    return [store_out(s) for s in nearby_stores(conn, lat, lon, radius_m, user["id"])]


@router.get("/products/search")
def search(q: str = Query(min_length=2, max_length=60), conn=Depends(get_conn), user=Depends(current_user)):
    words = [w for w in q.lower().split() if w][:5]
    def cond(expr: str) -> str:
        return " AND ".join([f"lower(unaccent({expr})) LIKE '%%' || lower(unaccent(%s)) || '%%'"] * len(words))
    generics = conn.execute(f"""
        SELECT g.id, g.name, c.name AS category FROM generic_products g JOIN categories c ON c.id = g.category_id
        WHERE {cond("g.name")}
        ORDER BY (lower(unaccent(g.name)) LIKE lower(unaccent(%s)) || '%%') DESC, similarity(g.name, %s) DESC LIMIT 5""",
        (*words, words[0], q)).fetchall()
    products = conn.execute(f"""
        SELECT p.id, p.name, p.brand, p.ean, p.generic_product_id, c.name AS category
        FROM products p JOIN categories c ON c.id = p.category_id
        WHERE NOT p.is_private_label AND {cond("p.name || ' ' || coalesce(p.brand, '')")}
        ORDER BY (lower(unaccent(p.name)) LIKE '%%' || lower(unaccent(%s)) || '%%') DESC, similarity(p.name, %s) DESC LIMIT 8""",
        (*words, q, q)).fetchall()
    return {"generics": generics, "products": products}


@router.get("/products/by-ean/{ean}")
def by_ean(ean: str, conn=Depends(get_conn), user=Depends(current_user)):
    p = conn.execute("SELECT id, name, brand, ean, generic_product_id FROM products WHERE ean=%s", (ean,)).fetchone()
    if not p:
        raise HTTPException(404, detail={"code": "not_found", "message": "Codice a barre non in catalogo"})
    return p


@router.get("/promos/top")
def top_promos(limit: int = Query(default=10, le=30), user=Depends(current_user), conn=Depends(get_conn)):
    lat, lon, radius = search_center(conn, user)
    stores = {s["id"]: s for s in nearby_stores(conn, lat, lon, radius, user["id"]) if s["pref"] != -1}
    if not stores:
        return []
    rows = conn.execute("""
        SELECT sp.store_id, sp.product_id, p.name AS product_name, p.generic_product_id, p.is_private_label,
               sp.price_regular, sp.price_promo, sp.promo_condition, sp.promo_valid_to, sp.promo_details,
               CASE WHEN sp.promo_condition = 'multi_buy' THEN 33
                    ELSE round(100 * (1 - sp.price_promo / sp.price_regular)) END AS pct
        FROM store_prices sp JOIN products p ON p.id = sp.product_id
        WHERE sp.store_id = ANY(%s) AND sp.promo_condition <> 'none'
          AND current_date BETWEEN coalesce(sp.promo_valid_from, current_date) AND sp.promo_valid_to
        ORDER BY pct DESC, sp.product_id""", (list(stores),)).fetchall()
    seen, out = set(), []
    for r in rows:
        if r["generic_product_id"] in seen:
            continue
        seen.add(r["generic_product_id"])
        s = stores[r["store_id"]]
        out.append({**r, "price_regular": float(r["price_regular"]),
                    "price_promo": float(r["price_promo"]) if r["price_promo"] is not None else None,
                    "pct": int(r["pct"]), "valid_to": r["promo_valid_to"].isoformat(),
                    "store_name": s["name"], "chain_name": s["chain_name"], "loyalty_card_name": s["loyalty_card_name"]})
        if len(out) >= limit:
            break
    for o in out:
        o.pop("promo_valid_to", None)
    return out


class SeedIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


@router.post("/dev/seed-near")
def dev_seed(body: SeedIn, user=Depends(current_user), conn=Depends(get_conn)):
    """Solo DEV_MODE: crea negozi e prezzi demo attorno al punto indicato (per provare l'app ovunque)."""
    if not settings.dev_mode:
        raise HTTPException(404)
    near = nearby_stores(conn, body.lat, body.lon, 3000)
    if near:
        return {"stores_created": 0, "message": "Ci sono già negozi in zona"}
    return {"stores_created": seed_stores_near(conn, body.lat, body.lon, label=dt.datetime.now().strftime("%Y%m%d%H%M%S%f"))}
