import os

os.environ.setdefault("DATABASE_URL", "postgresql://postgres@localhost:5432/smartpantry_test")
os.environ.setdefault("DEV_MODE", "1")
os.environ.setdefault("OCR_PROVIDER", "demo")

import psycopg  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

MILANO = (45.4773, 9.2050)


@pytest.fixture(scope="session")
def client():
    url = os.environ["DATABASE_URL"]
    with psycopg.connect(url, autocommit=True) as c:          # database pulito ad ogni sessione di test
        c.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    from app.main import app
    with TestClient(app) as tc:
        yield tc


def new_user(client, device="device-test-0001", lat=MILANO[0], lon=MILANO[1]):
    r = client.post("/v1/auth/anonymous", json={"device_id": device})
    assert r.status_code == 200, r.text
    h = {"Authorization": "Bearer " + r.json()["token"]}
    assert client.patch("/v1/me", json={"home_lat": lat, "home_lon": lon, "home_cap": "20129"}, headers=h).status_code == 200
    return h
