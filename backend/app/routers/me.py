from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..auth import current_user, is_premium, issue_token
from ..config import settings
from ..db import get_conn
from ..users import user_out

router = APIRouter(prefix="/v1", tags=["utente"])


class AnonymousIn(BaseModel):
    device_id: str = Field(min_length=8, max_length=128)


@router.post("/auth/anonymous")
def auth_anonymous(body: AnonymousIn, conn=Depends(get_conn)):
    user = conn.execute("SELECT * FROM users WHERE device_id=%s", (body.device_id,)).fetchone()
    if not user:
        user = conn.execute("INSERT INTO users(device_id, credits) VALUES (%s, 0) RETURNING *", (body.device_id,)).fetchone()
    return {"token": issue_token(user["id"]), "user": user_out(conn, user)}


@router.get("/me")
def get_me(user=Depends(current_user), conn=Depends(get_conn)):
    return user_out(conn, user)


class MeIn(BaseModel):
    home_lat: float | None = Field(default=None, ge=-90, le=90)
    home_lon: float | None = Field(default=None, ge=-180, le=180)
    home_cap: str | None = Field(default=None, pattern=r"^\d{5}$")
    search_radius_m: int | None = Field(default=None, ge=500, le=20000)
    loyalty_chain_ids: list[int] | None = None


@router.patch("/me")
def patch_me(body: MeIn, user=Depends(current_user), conn=Depends(get_conn)):
    if (body.home_lat is None) != (body.home_lon is None):
        raise HTTPException(422, detail={"code": "invalid", "message": "Servono sia latitudine che longitudine"})
    if body.home_lat is not None:
        conn.execute("UPDATE users SET home_location = ST_MakePoint(%s,%s)::geography WHERE id=%s",
                     (body.home_lon, body.home_lat, user["id"]))
    if body.home_cap is not None:
        conn.execute("UPDATE users SET home_cap=%s WHERE id=%s", (body.home_cap, user["id"]))
    if body.search_radius_m is not None:
        limit = settings.premium_max_radius_m if is_premium(user) else settings.free_max_radius_m
        if body.search_radius_m > limit:
            raise HTTPException(403, detail={"code": "premium_required", "message": "Raggio oltre 5 km disponibile con Premium"})
        conn.execute("UPDATE users SET search_radius_m=%s WHERE id=%s", (body.search_radius_m, user["id"]))
    if body.loyalty_chain_ids is not None:
        conn.execute("DELETE FROM user_loyalty_cards WHERE user_id=%s", (user["id"],))
        for cid in set(body.loyalty_chain_ids):
            conn.execute("INSERT INTO user_loyalty_cards(user_id, chain_id) SELECT %s, id FROM chains WHERE id=%s",
                         (user["id"], cid))
    fresh = conn.execute("SELECT * FROM users WHERE id=%s", (user["id"],)).fetchone()
    return user_out(conn, fresh)


class PrefIn(BaseModel):
    pref: int = Field(ge=-1, le=1)          # -1 escluso, 0 neutro, 1 preferito


@router.put("/me/store-prefs/{store_id}")
def set_store_pref(store_id: int, body: PrefIn, user=Depends(current_user), conn=Depends(get_conn)):
    if body.pref == 0:
        conn.execute("DELETE FROM user_store_prefs WHERE user_id=%s AND store_id=%s", (user["id"], store_id))
    else:
        conn.execute("""INSERT INTO user_store_prefs(user_id, store_id, pref) VALUES (%s,%s,%s)
                        ON CONFLICT (user_id, store_id) DO UPDATE SET pref=EXCLUDED.pref""", (user["id"], store_id, body.pref))
    return {"store_id": store_id, "pref": body.pref}


@router.get("/me/savings")
def savings(user=Depends(current_user), conn=Depends(get_conn)):
    rows = conn.execute("""SELECT date_trunc('month', closed_at) AS m, sum(realized_saving) AS s, count(*) AS n
                           FROM optimization_runs WHERE user_id=%s AND realized_saving IS NOT NULL
                             AND closed_at > date_trunc('month', now()) - interval '11 months'
                           GROUP BY 1""", (user["id"],)).fetchall()
    by_month = {(r["m"].year, r["m"].month): (float(r["s"]), r["n"]) for r in rows}
    today = dt.date.today()
    months = []
    for k in range(5, -1, -1):
        y, m = today.year, today.month - k
        while m <= 0:
            y, m = y - 1, m + 12
        s, _ = by_month.get((y, m), (0.0, 0))
        months.append({"year": y, "month": m, "saving": round(s, 2)})
    year = [v for (y, _m), v in by_month.items() if y == today.year]
    return {"month_saving": months[-1]["saving"], "year_saving": round(sum(v[0] for v in year), 2),
            "year_count": sum(v[1] for v in year), "months": months}


@router.post("/me/premium/redeem")
def redeem(user=Depends(current_user), conn=Depends(get_conn)):
    need = settings.credits_for_premium_week
    if user["credits"] < need:
        raise HTTPException(409, detail={"code": "not_enough_credits", "message": f"Servono {need} crediti"})
    base = max(user["premium_until"] or dt.datetime.now(dt.timezone.utc), dt.datetime.now(dt.timezone.utc))
    conn.execute("UPDATE users SET credits=credits-%s, premium_until=%s WHERE id=%s",
                 (need, base + dt.timedelta(days=7), user["id"]))
    conn.execute("INSERT INTO credit_ledger(user_id, delta, reason) VALUES (%s,%s,'redeem_premium')", (user["id"], -need))
    return user_out(conn, conn.execute("SELECT * FROM users WHERE id=%s", (user["id"],)).fetchone())


@router.post("/me/premium/demo")
def premium_demo(on: bool = True, user=Depends(current_user), conn=Depends(get_conn)):
    """Solo DEV_MODE: attiva/disattiva Premium senza pagamento (in produzione: RevenueCat / store billing)."""
    if not settings.dev_mode:
        raise HTTPException(404)
    conn.execute("UPDATE users SET plan=%s WHERE id=%s", ("premium" if on else "free", user["id"]))
    if not on:
        conn.execute("UPDATE users SET search_radius_m=LEAST(search_radius_m, %s) WHERE id=%s",
                     (settings.free_max_radius_m, user["id"]))
    return user_out(conn, conn.execute("SELECT * FROM users WHERE id=%s", (user["id"],)).fetchone())
