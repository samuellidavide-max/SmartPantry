"""Pool di connessioni PostgreSQL e runner delle migrazioni SQL."""
from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import settings

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"
_pool: ConnectionPool | None = None


def init_pool(url: str | None = None) -> ConnectionPool:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(url or settings.database_url, min_size=1, max_size=10,
                               kwargs={"row_factory": dict_row}, open=True)
    return _pool


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


@contextmanager
def connection():
    pool = init_pool()
    with pool.connection() as conn:
        yield conn


def get_conn():
    """Dipendenza FastAPI: una connessione per richiesta, commit automatico a fine richiesta."""
    with connection() as conn:
        yield conn


def run_migrations(url: str | None = None) -> list[str]:
    applied = []
    with psycopg.connect(url or settings.database_url, autocommit=False) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ DEFAULT now())")
        done = {r[0] for r in conn.execute("SELECT name FROM schema_migrations").fetchall()}
        for f in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if f.name in done:
                continue
            conn.execute(f.read_text(encoding="utf-8"))
            conn.execute("INSERT INTO schema_migrations(name) VALUES (%s)", (f.name,))
            applied.append(f.name)
        conn.commit()
    return applied
