"""Flusso completo come lo farebbe l'app: utente, zona, lista, confronto, spesa, scontrino, crediti."""
from conftest import MILANO, new_user


def test_full_flow(client):
    h = new_user(client)
    # zona senza negozi -> seed demo
    assert client.get("/v1/stores/nearby", headers=h).json() == []
    r = client.post("/v1/dev/seed-near", json={"lat": MILANO[0], "lon": MILANO[1]}, headers=h)
    assert r.json()["stores_created"] == 9
    stores = client.get("/v1/stores/nearby", headers=h).json()
    assert len(stores) == 8 and stores[0]["dist_m"] < stores[-1]["dist_m"]      # 5 km Free: 8 su 9
    chains = {c["slug"]: c["id"] for c in client.get("/v1/chains").json()}
    me = client.patch("/v1/me", json={"loyalty_chain_ids": [chains["esselunga"]]}, headers=h).json()
    assert me["loyalty_chain_ids"] == [chains["esselunga"]] and me["max_radius_m"] == 5000

    # raggio oltre 5 km bloccato per Free
    assert client.patch("/v1/me", json={"search_radius_m": 10000}, headers=h).json()["detail"]["code"] == "premium_required"

    # ricerca prodotti
    s = client.get("/v1/products/search", params={"q": "olio"}, headers=h).json()
    assert s["generics"] and any("Monini" in p["name"] for p in s["products"])
    s2 = client.get("/v1/products/search", params={"q": "de cecco spaghetti"}, headers=h).json()
    dececco = s2["products"][0]
    assert "De Cecco Spaghetti" in dececco["name"]
    caffe = client.get("/v1/products/search", params={"q": "caffe"}, headers=h).json()["generics"][0]   # senza accento
    assert caffe["name"].startswith("Caffè")

    # lista
    lst = client.post("/v1/lists", json={"name": "Spesa settimana"}, headers=h).json()
    lid = lst["id"]
    assert client.post("/v1/lists", json={"name": "Seconda"}, headers=h).json()["detail"]["code"] == "premium_required"
    want = ["latte", "olio", "detersivo piatti", "pelati", "biscotti", "acqua", "uova", "tonno", "mozzarella", "passata", "yogurt", "banane"]
    for q in want:
        g = client.get("/v1/products/search", params={"q": q}, headers=h).json()["generics"][0]
        assert client.post(f"/v1/lists/{lid}/items", json={"generic_product_id": g["id"], "quantity": 2 if q in ("latte", "pelati") else 1},
                           headers=h).status_code == 201
    client.post(f"/v1/lists/{lid}/items", json={"product_id": dececco["id"], "quantity": 2}, headers=h)
    client.post(f"/v1/lists/{lid}/items", json={"product_id": dececco["id"]}, headers=h)        # stessa voce: quantità +1
    detail = client.get(f"/v1/lists/{lid}", headers=h).json()
    assert len(detail["items"]) == 13
    dec_item = next(i for i in detail["items"] if i["product_id"] == dececco["id"])
    assert dec_item["quantity"] == 3 and dec_item["best"]["total"] > 0
    assert detail["estimate_total"] > 10

    # promo
    promos = client.get("/v1/promos/top", headers=h).json()
    assert promos and promos[0]["pct"] >= promos[-1]["pct"]

    # ottimizzazione Free: B bloccato lato server
    opt = client.post(f"/v1/lists/{lid}/optimize", headers=h).json()
    a = opt["scenario_a"]
    assert a["covered"] == 13 and a["total"] > 0 and len(opt["alternatives"]) == 3
    assert opt["scenario_b"]["locked"] is True and "lines" not in opt["scenario_b"]
    assert client.post(f"/v1/runs/{opt['run_id']}/start", json={"scenario": "B"}, headers=h).json()["detail"]["code"] == "premium_required"

    # Premium demo -> B completo
    assert client.post("/v1/me/premium/demo", headers=h).json()["is_premium"] is True
    opt = client.post(f"/v1/lists/{lid}/optimize", headers=h).json()
    b = opt["scenario_b"]
    assert b and len(b["stores"]) in (2, 3) and b["total"] <= opt["scenario_a"]["total"]
    assert sum(l["cost"] for l in b["lines"]) == __import__("pytest").approx(b["total"], abs=0.02)
    assert b["route_m"] <= 1500 * 2

    sess = client.post(f"/v1/runs/{opt['run_id']}/start", json={"scenario": "B"}, headers=h).json()
    assert sess["scenario"] == "B" and sess["stores"][0]["id"] == b["stores"][0]
    assert client.get(f"/v1/lists/{lid}", headers=h).json()["active_session"]["run_id"] == opt["run_id"]

    # scontrino (OCR demo) -> revisione riga incerta -> conferma
    rec = client.post("/v1/receipts", files={"image": ("s.jpg", b"\xff\xd8fake-jpeg", "image/jpeg")}, headers=h)
    assert rec.status_code == 201, rec.text
    rec = rec.json()
    assert rec["store_id"] == b["stores"][0] and rec["totals_match"]
    review = [l for l in rec["lines"] if l["needs_review"]]
    assert len(review) == 1 and review[0]["candidates"]
    others = [l for l in rec["lines"] if not l["needs_review"]]
    assert others and all(l["match_confidence"] >= 0.55 for l in others)
    rec = client.patch(f"/v1/receipts/{rec['id']}/lines/{review[0]['line_no']}",
                       json={"product_id": review[0]["candidates"][0]["product_id"]}, headers=h).json()
    assert not any(l["needs_review"] for l in rec["lines"])
    done = client.post(f"/v1/receipts/{rec['id']}/confirm", headers=h).json()
    assert done["credits_awarded"] == 10 and done["prices_submitted"] == len(rec["lines"])
    assert done["saving_confirmed"] is not None
    assert client.post(f"/v1/receipts/{rec['id']}/confirm", headers=h).json()["detail"]["code"] == "already_validated"
    assert client.get("/v1/sessions/active", headers=h).json() is None

    sav = client.get("/v1/me/savings", headers=h).json()
    assert sav["month_saving"] == done["saving_confirmed"] and len(sav["months"]) == 6


def test_receipt_consensus_updates_price(client):
    """Due utenti diversi riportano lo stesso prezzo da scontrino -> il prezzo diventa quello ufficiale."""
    import psycopg
    import os
    h1, h2 = new_user(client, "device-consensus-1"), new_user(client, "device-consensus-2")
    with psycopg.connect(os.environ["DATABASE_URL"]) as c:
        sid, pid, old = c.execute("""SELECT sp.store_id, sp.product_id, sp.price_regular FROM store_prices sp
                                     WHERE sp.primary_source='flyer' AND sp.price_promo IS NULL ORDER BY 1,2 LIMIT 1""").fetchone()
        from app.resolver import resolve_pair
        from psycopg.rows import dict_row
        c.row_factory = dict_row
        users = [r["id"] for r in c.execute("SELECT id FROM users WHERE device_id LIKE 'device-consensus-%'")]
        new_price = round(float(old) + 0.30, 2)
        c.execute("""INSERT INTO price_observations(store_id, product_id, source, price_regular, reported_by)
                     VALUES (%s,%s,'receipt',%s,%s)""", (sid, pid, new_price, users[0]))
        resolve_pair(c, sid, pid)
        assert float(c.execute("SELECT price_regular FROM store_prices WHERE store_id=%s AND product_id=%s", (sid, pid)).fetchone()["price_regular"]) == float(old)
        c.execute("""INSERT INTO price_observations(store_id, product_id, source, price_regular, reported_by)
                     VALUES (%s,%s,'receipt',%s,%s)""", (sid, pid, new_price, users[1]))
        res = resolve_pair(c, sid, pid)
        assert res["source"] == "receipt" and res["confirmations"] == 2
        row = c.execute("SELECT price_regular, primary_source FROM store_prices WHERE store_id=%s AND product_id=%s", (sid, pid)).fetchone()
        assert float(row["price_regular"]) == new_price and row["primary_source"] == "receipt"
        c.rollback()


def test_outlier_detection(client):
    import os
    import psycopg
    from psycopg.rows import dict_row
    from app.resolver import flag_outliers
    with psycopg.connect(os.environ["DATABASE_URL"], row_factory=dict_row) as c:
        sid, pid, base = c.execute("SELECT store_id, product_id, price_regular FROM store_prices WHERE price_promo IS NULL ORDER BY 1,2 OFFSET 5 LIMIT 1").fetchone().values()
        base = float(base)
        for p in (base, base + 0.02, base - 0.02, base + 0.01, 9.99):
            c.execute("INSERT INTO price_observations(store_id, product_id, source, price_regular) VALUES (%s,%s,'receipt',%s)", (sid, pid, p))
        flagged = flag_outliers(c, sid, pid)
        prices = [float(r["price_regular"]) for r in c.execute("SELECT price_regular FROM price_observations WHERE id = ANY(%s)", (flagged,))]
        assert prices == [9.99]
        c.rollback()


def test_errors_are_readable(client):
    h = new_user(client, "device-errors-0001")
    r = client.post("/v1/lists/00000000-0000-0000-0000-000000000000/items", json={}, headers=h)
    assert r.status_code in (404, 422) and "message" in r.json()["detail"]
    assert client.get("/v1/me").status_code == 401
