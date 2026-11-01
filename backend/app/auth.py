"""Autenticazione MVP: utente anonimo legato al dispositivo, token JWT HS256.
In produzione si aggiunge login (Apple/Google/email) collegando l'utente anonimo."""
from __future__ import annotations

import datetime as dt
import uuid

import jwt
from fastapi import Depends, Header, HTTPException

from .config import settings
from .db import get_conn


def issue_token(user_id: str) -> str:
    now = dt.datetime.now(dt.timezone.utc)
    payload = {"sub": str(user_id), "iat": now, "exp": now + dt.timedelta(days=180)}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def current_user(authorization: str | None = Header(default=None), conn=Depends(get_conn)) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, detail={"code": "unauthorized", "message": "Token mancante"})
    try:
        payload = jwt.decode(authorization.split(" ", 1)[1], settings.jwt_secret, algorithms=["HS256"])
        user_id = uuid.UUID(payload["sub"])
    except Exception:
        raise HTTPException(401, detail={"code": "unauthorized", "message": "Token non valido"})
    user = conn.execute("SELECT * FROM users WHERE id = %s", (user_id,)).fetchone()
    if not user:
        raise HTTPException(401, detail={"code": "unauthorized", "message": "Utente inesistente"})
    return user


def is_premium(user: dict) -> bool:
    if user["plan"] == "premium":
        return True
    until = user.get("premium_until")
    return bool(until and until > dt.datetime.now(dt.timezone.utc))


def max_radius(user: dict) -> int:
    return settings.premium_max_radius_m if is_premium(user) else settings.free_max_radius_m


def premium_required(message: str):
    return HTTPException(403, detail={"code": "premium_required", "message": message})
