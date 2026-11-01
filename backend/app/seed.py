"""Dati DEMO: catene, catalogo, negozi attorno a un punto, prezzi deterministici.

Uso CLI:  python -m app.seed --lat 45.4773 --lon 9.2050
Lo stesso codice è usato da POST /v1/dev/seed-near per creare negozi demo vicino all'utente.
I prezzi sono inventati (ma stabili): servono a provare l'app finché gli scraper non sono attivi.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import re
import unicodedata

from psycopg.types.json import Jsonb

CHAINS = [
    # slug, nome, carta, fattore prezzo, discount, portale online
    ("esselunga", "Esselunga", "Fidaty", 1.04, False, "https://www.esselungaacasa.it"),
    ("coop", "Coop", "Carta Socio Coop", 1.02, False, "https://www.coopshop.it"),
    ("conad", "Conad", "Carta Insieme", 1.00, False, "https://spesaonline.conad.it"),
    ("carrefour", "Carrefour", "Carta Carrefour", 1.01, False, "https://www.carrefour.it/spesa-online"),
    ("eurospin", "Eurospin", None, 0.79, True, None),
    ("lidl", "Lidl", "Lidl Plus", 0.81, True, None),
]
CATEGORIES = ["Latticini e uova", "Dispensa", "Colazione", "Bevande", "Frutta e verdura", "Casa e igiene"]
# id, nome, formato, categoria, prezzo base, net_qty, unità
GENERICS = [
    ("latte", "Latte parzialmente scremato", "1 L", 0, 1.35, 1000, "ml"),
    ("yogurt", "Yogurt bianco", "2×125 g", 0, 1.10, 250, "g"),
    ("mozzarella", "Mozzarella", "125 g", 0, 1.05, 125, "g"),
    ("parmigiano", "Parmigiano Reggiano", "200 g", 0, 4.20, 200, "g"),
    ("uova", "Uova fresche", "6 pz", 0, 2.20, 6, "pz"),
    ("burro", "Burro", "250 g", 0, 2.60, 250, "g"),
    ("pasta", "Pasta corta di semola", "500 g", 1, 0.95, 500, "g"),
    ("spaghetti", "Spaghetti", "500 g", 1, 0.95, 500, "g"),
    ("riso", "Riso Carnaroli", "1 kg", 1, 2.60, 1000, "g"),
    ("olio", "Olio extravergine d'oliva", "1 L", 1, 8.20, 1000, "ml"),
    ("pelati", "Pomodori pelati", "400 g", 1, 0.85, 400, "g"),
    ("passata", "Passata di pomodoro", "700 g", 1, 1.10, 700, "g"),
    ("tonno", "Tonno all'olio d'oliva", "3×80 g", 1, 3.40, 240, "g"),
    ("farina", "Farina 00", "1 kg", 1, 0.85, 1000, "g"),
    ("zucchero", "Zucchero", "1 kg", 1, 1.15, 1000, "g"),
    ("caffe", "Caffè macinato", "250 g", 2, 3.80, 250, "g"),
    ("biscotti", "Biscotti frollini", "350 g", 2, 1.90, 350, "g"),
    ("fette", "Fette biscottate", "315 g", 2, 1.60, 315, "g"),
    ("acqua", "Acqua naturale", "6×1,5 L", 3, 1.75, 9000, "ml"),
    ("birra", "Birra lager", "3×33 cl", 3, 2.70, 990, "ml"),
    ("banane", "Banane", "1 kg", 4, 1.79, 1000, "g"),
    ("mele", "Mele Golden", "1,5 kg", 4, 2.40, 1500, "g"),
    ("piatti", "Detersivo piatti", "1 L", 5, 1.60, 1000, "ml"),
    ("lavatrice", "Detersivo lavatrice", "25 lavaggi", 5, 6.50, 25, "pz"),
    ("carta", "Carta igienica", "8 rotoli", 5, 3.20, 8, "pz"),
    ("cucina", "Carta da cucina", "2 rotoli", 5, 1.90, 2, "pz"),
]
BRANDED = [
    ("8000000000011", "Latte Granarolo parz. scremato 1 L", "Granarolo", "latte", 1.59),
    ("8000000000028", "Latte Zymil parz. scremato 1 L", "Parmalat", "latte", 1.89),
    ("8000000000035", "Yogurt Müller bianco 2×125 g", "Müller", "yogurt", 1.39),
    ("8000000000042", "Mozzarella Santa Lucia 125 g", "Galbani", "mozzarella", 1.29),
    ("8000000000059", "Parmigiano Reggiano Parmareggio 200 g", "Parmareggio", "parmigiano", 4.99),
    ("8000000000066", "Uova Aia 6 pz", "Aia", "uova", 2.59),
    ("8000000000073", "Pasta Barilla Penne Rigate n.73 500 g", "Barilla", "pasta", 1.29),
    ("8000000000080", "Pasta De Cecco Penne Rigate n.41 500 g", "De Cecco", "pasta", 1.49),
    ("8000000000097", "Pasta De Cecco Spaghetti n.12 500 g", "De Cecco", "spaghetti", 1.49),
    ("8000000000103", "Pasta Barilla Spaghetti n.5 500 g", "Barilla", "spaghetti", 1.29),
    ("8000000000110", "Riso Scotti Carnaroli 1 kg", "Scotti", "riso", 3.19),
    ("8000000000127", "Olio Monini Classico EVO 1 L", "Monini", "olio", 9.90),
    ("8000000000134", "Olio Carapelli Il Frantolio EVO 1 L", "Carapelli", "olio", 9.49),
    ("8000000000141", "Pelati Cirio 400 g", "Cirio", "pelati", 1.09),
    ("8000000000158", "Passata Mutti 700 g", "Mutti", "passata", 1.49),
    ("8000000000165", "Tonno Rio Mare 3×80 g", "Rio Mare", "tonno", 4.29),
    ("8000000000172", "Farina 00 Barilla 1 kg", "Barilla", "farina", 1.19),
    ("8000000000189", "Zucchero Eridania 1 kg", "Eridania", "zucchero", 1.49),
    ("8000000000196", "Caffè Lavazza Qualità Rossa 250 g", "Lavazza", "caffe", 4.29),
    ("8000000000202", "Caffè Kimbo Aroma Gold 250 g", "Kimbo", "caffe", 4.49),
    ("8000000000219", "Biscotti Mulino Bianco Macine 350 g", "Mulino Bianco", "biscotti", 2.29),
    ("8000000000226", "Fette biscottate Mulino Bianco 315 g", "Mulino Bianco", "fette", 2.09),
    ("8000000000233", "Acqua Sant'Anna 6×1,5 L", "Sant'Anna", "acqua", 2.19),
    ("8000000000240", "Acqua Levissima 6×1,5 L", "Levissima", "acqua", 2.49),
    ("8000000000257", "Birra Peroni 3×33 cl", "Peroni", "birra", 3.19),
    ("8000000000264", "Banane Chiquita 1 kg", "Chiquita", "banane", 2.29),
    ("8000000000271", "Svelto piatti limone 1 L", "Svelto", "piatti", 2.19),
    ("8000000000288", "Dash detersivo lavatrice 25 lavaggi", "Dash", "lavatrice", 8.99),
    ("8000000000295", "Carta igienica Scottex 8 rotoli", "Scottex", "carta", 4.29),
    ("8000000000301", "Carta cucina Scottex 2 rotoli", "Scottex", "cucina", 2.39),
]
# (chain slug, scostamento est km, nord km, click&collect)
STORE_LAYOUT = [
    ("esselunga", 0.35, -0.20, True), ("eurospin", -0.25, 0.40, False), ("carrefour", 0.50, 0.45, True),
    ("conad", -0.60, -0.35, True), ("lidl", 1.90, 1.30, False), ("coop", 2.20, -2.60, True),
    ("eurospin", 3.30, 2.50, False), ("esselunga", 4.80, 1.00, True), ("coop", 6.80, -4.50, True),
]
STREETS = ["Viale Piave", "Via Lazzaretto", "Corso Buenos Aires", "Via Spallanzani", "Viale Monza",
           "Viale Umbria", "Via Padova", "Via Rubattino", "Viale Forlanini"]


def hash01(s: str) -> float:
    h = 2166136261
    for ch in s:
        h ^= ord(ch)
        h = (h * 16777619) & 0xFFFFFFFF
    return (h % 100000) / 100000


def round_price(x: float) -> float:
    return max(0.29, round(round(x * 10) / 10 - 0.01, 2))


def normalize_alias(text: str) -> str:
    t = unicodedata.normalize("NFD", text).encode("ascii", "ignore").decode().upper()
    t = re.sub(r"[^A-Z0-9,. ]", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def receipt_alias(name: str) -> str:
    """Abbreviazione stile scontrino: 'Latte Granarolo parz. scremato 1 L' -> 'LATTE GRANA PARZ. SCREM 1 L'."""
    words = [w for w in normalize_alias(name).split() if w not in {"DI", "DA", "AL", "ALL", "D", "E"}]
    return " ".join(w[:5] if len(w) > 6 else w for w in words)[:24].strip()


def ensure_catalog(conn) -> None:
    if conn.execute("SELECT 1 FROM chains LIMIT 1").fetchone():
        return
    for slug, name, card, _f, disc, url in CHAINS:
        conn.execute("INSERT INTO chains(name, slug, loyalty_card_name, online_portal_url, is_discount) VALUES (%s,%s,%s,%s,%s)",
                     (name, slug, card, url, disc))
    cat_ids = [conn.execute("INSERT INTO categories(name) VALUES (%s) RETURNING id", (c,)).fetchone()["id"] for c in CATEGORIES]
    gen_ids = {}
    for gid, name, size, cat, _base, qty, unit in GENERICS:
        gen_ids[gid] = conn.execute(
            "INSERT INTO generic_products(name, category_id, base_unit, default_qty) VALUES (%s,%s,%s,%s) RETURNING id",
            (f"{name} {size}", cat_ids[cat], unit, qty)).fetchone()["id"]
    gmap = {g[0]: g for g in GENERICS}
    for ean, name, brand, gid, _base in BRANDED:
        g = gmap[gid]
        conn.execute("""INSERT INTO products(ean, name, brand, category_id, generic_product_id, net_qty, net_unit, attributes)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                     (ean, name, brand, cat_ids[g[3]], gen_ids[gid], g[5], g[6], Jsonb({"seed_key": gid})))
    chains = {r["slug"]: r["id"] for r in conn.execute("SELECT id, slug FROM chains")}
    for slug, cname, *_ in CHAINS:          # marche del distributore
        for gid, gname, size, cat, _b, qty, unit in GENERICS:
            conn.execute("""INSERT INTO products(name, brand, is_private_label, private_label_chain, category_id,
                            generic_product_id, net_qty, net_unit, attributes) VALUES (%s,%s,TRUE,%s,%s,%s,%s,%s,%s)""",
                         (f"{gname} {size} {cname}", cname, chains[slug], cat_ids[cat], gen_ids[gid], qty, unit,
                          Jsonb({"seed_key": gid})))
    # alias scontrino per catena
    for p in conn.execute("SELECT id, name, private_label_chain FROM products").fetchall():
        targets = [p["private_label_chain"]] if p["private_label_chain"] else list(chains.values())
        for cid in targets:
            conn.execute("""INSERT INTO product_aliases(product_id, chain_id, source, alias_text, confidence)
                            VALUES (%s,%s,'receipt',%s,0.9) ON CONFLICT DO NOTHING""",
                         (p["id"], cid, receipt_alias(p["name"])))


def seed_stores_near(conn, lat: float, lon: float, label: str | None = None) -> int:
    """Crea i 9 negozi demo attorno a (lat, lon) e i relativi prezzi. Ritorna il numero di negozi creati."""
    ensure_catalog(conn)
    chains = {r["slug"]: r for r in conn.execute("SELECT id, slug, name, loyalty_card_name FROM chains")}
    factors = {c[0]: (c[3], c[4], c[5] is not None) for c in CHAINS}
    products = conn.execute("""SELECT p.id, p.name, p.is_private_label, p.private_label_chain, p.net_qty, p.net_unit,
                                      p.attributes->>'seed_key' AS gkey FROM products p""").fetchall()
    base_by_name = {b[1]: b[4] for b in BRANDED}
    gbase = {g[0]: g[4] for g in GENERICS}
    today = dt.date.today()
    tag = label or f"{lat:.3f},{lon:.3f}"
    created = 0
    for idx, ((slug, dx, dy, cc), street) in enumerate(zip(STORE_LAYOUT, STREETS)):
        ch = chains[slug]
        slat = lat + dy / 110.574
        slon = lon + dx / (111.320 * math.cos(math.radians(lat)))
        name = f"{ch['name']} {street}"
        ext = f"demo-{tag}-{idx}"
        row = conn.execute("""INSERT INTO stores(chain_id, external_store_id, name, address, cap, city, location,
                                has_click_collect, has_online_prices, price_zone)
                              VALUES (%s,%s,%s,%s,'00000','Demo', ST_MakePoint(%s,%s)::geography, %s, %s, %s)
                              ON CONFLICT (chain_id, external_store_id) DO NOTHING RETURNING id""",
                           (ch["id"], ext, name, f"{street} {10 + idx}", slon, slat, cc, factors[slug][2], f"demo-{slug}")).fetchone()
        if not row:
            continue
        created += 1
        sid = row["id"]
        f, discount, portal = factors[slug]
        for p in products:
            if p["is_private_label"]:
                if p["private_label_chain"] != ch["id"]:
                    continue
                base = gbase[p["gkey"]] * 0.84
            else:
                if hash01(f"av{slug}{p['id']}") >= (0.22 if discount else 0.9):
                    continue
                base = base_by_name[p["name"]]
            key = f"{idx}{slug}{p['id']}"
            regular = round_price(base * f * (1 + (hash01("pr" + key) - 0.5) * 0.12))
            promo, cond, vfrom, vto, details = None, "none", None, None, None
            if hash01("promo" + key) < 0.15:
                h3 = hash01("cond" + key)
                vfrom, vto = today - dt.timedelta(days=2), today + dt.timedelta(days=2 + int(hash01("vt" + key) * 10))
                if h3 > 0.88:
                    cond, details = "multi_buy", {"buy": 3, "pay": 2}
                else:
                    cond = "loyalty_card" if (ch["loyalty_card_name"] and h3 < 0.42) else "flyer"
                    promo = min(round(regular - 0.1, 2), round_price(regular * (1 - (0.15 + 0.22 * hash01("pct" + key)))))
                    promo = max(0.19, promo)
            hs = hash01("src" + key)
            source = "online" if portal and hs < 0.75 else ("flyer" if hs < 0.88 else "receipt")
            conf = {"online": 0.9, "flyer": 0.7}.get(source, 0.8 if hash01("cf" + key) >= 0.5 else 0.45)
            age = int(hash01("age" + key) * (2 if source == "online" else 12))
            observed = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=age)
            per = float(p["net_qty"]) / (1000 if p["net_unit"] in ("g", "ml") else 1)
            conn.execute("""INSERT INTO store_prices(store_id, product_id, price_regular, price_promo, promo_condition,
                              promo_valid_from, promo_valid_to, promo_details, unit_price_regular, primary_source,
                              confidence, observations_30d, last_observed_at)
                            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,1,%s)""",
                         (sid, p["id"], regular, promo, cond, vfrom, vto, Jsonb(details) if details else None,
                          round(regular / per, 4), source, conf, observed))
            conn.execute("""INSERT INTO price_observations(store_id, product_id, source, source_ref, price_regular,
                              price_promo, promo_condition, promo_details, valid_from, valid_to, observed_at)
                            VALUES (%s,%s,%s,'seed',%s,%s,%s,%s,%s,%s,%s)""",
                         (sid, p["id"], source, regular, promo, cond, Jsonb(details) if details else None, vfrom, vto, observed))
    return created


def main():
    import psycopg
    from psycopg.rows import dict_row
    from .config import settings
    from .db import run_migrations
    ap = argparse.ArgumentParser(description="Crea dati demo attorno a un punto")
    ap.add_argument("--lat", type=float, default=45.4773)
    ap.add_argument("--lon", type=float, default=9.2050)
    a = ap.parse_args()
    run_migrations()
    with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
        n = seed_stores_near(conn, a.lat, a.lon)
        conn.commit()
    print(json.dumps({"stores_created": n, "lat": a.lat, "lon": a.lon}))


if __name__ == "__main__":
    main()
