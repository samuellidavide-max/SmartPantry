"""Serializzazione utente e helper condivisi tra i router."""
from __future__ import annotations

from fastapi import HTTPException

from .auth import is_premium, max_radius
from .config import settings


def user_out(conn, user: dict) -> dict:
    home = None
    if user["home_location"] is not None:
        r = conn.execute("SELECT ST_Y(%s::geometry) AS lat, ST_X(%s::geometry) AS lon",
                         (user["home_location"], user["home_location"])).fetchone()
        home = {"lat": r["lat"], "lon": r["lon"], "cap": user["home_cap"]}
    cards = [r["chain_id"] for r in conn.execute("SELECT chain_id FROM user_loyalty_cards WHERE user_id=%s ORDER BY chain_id",
                                                 (user["id"],))]
    return {
        "id": str(user["id"]), "plan": user["plan"], "is_premium": is_premium(user),
        "premium_until": user["premium_until"].isoformat() if user["premium_until"] else None,
        "credits": user["credits"], "credits_for_premium_week": settings.credits_for_premium_week,
        "home": home, "search_radius_m": min(user["search_radius_m"], max_radius(user)),
        "max_radius_m": max_radius(user), "loyalty_chain_ids": cards,
        "streak_weeks": user["streak_weeks"], "trust_score": user["trust_score"], "dev_mode": settings.dev_mode,
    }


def search_center(conn, user: dict, lst: dict | None = None) -> tuple[float, float, int]:
    """(lat, lon, raggio_m) per la ricerca: centro della lista o casa dell'utente."""
    loc = (lst or {}).get("search_center") or user["home_location"]
    if loc is None:
        raise HTTPException(409, detail={"code": "location_required",
                                         "message": "Imposta prima la tua zona (posizione o CAP)"})
    r = conn.execute("SELECT ST_Y(%s::geometry) AS lat, ST_X(%s::geometry) AS lon", (loc, loc)).fetchone()
    radius = (lst or {}).get("radius_m") or user["search_radius_m"]
    return r["lat"], r["lon"], min(radius, max_radius(user))
