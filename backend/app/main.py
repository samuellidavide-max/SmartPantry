"""SmartPantry API - avvio: uvicorn app.main:app --host 0.0.0.0 --port 8000"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .db import close_pool, init_pool, run_migrations
from .routers import catalog, lists, me, receipts


@asynccontextmanager
async def lifespan(_app: FastAPI):
    run_migrations()
    init_pool()
    yield
    close_pool()


app = FastAPI(title="SmartPantry API", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.exception_handler(RequestValidationError)
async def validation_handler(_req: Request, exc: RequestValidationError):
    first = exc.errors()[0] if exc.errors() else {}
    msg = first.get("msg", "Dati non validi").replace("Value error, ", "")
    return JSONResponse(status_code=422, content={"detail": {"code": "invalid", "message": msg, "field": ".".join(str(x) for x in first.get("loc", []))}})


@app.get("/health")
def health():
    return {"status": "ok"}


for r in (me.router, catalog.router, lists.router, receipts.router):
    app.include_router(r)
