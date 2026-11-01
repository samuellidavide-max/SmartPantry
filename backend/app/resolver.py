"""Price resolver: dal ledger price_observations al prezzo corrente in store_prices.

Regole (vedi documento tecnico, sezione 4):
  1. Outlier: mediana e MAD delle osservazioni a 30 giorni della coppia (store, prodotto);
     outlier se |p - mediana| > 3 * 1,4826 * MAD  E  > 20% della mediana (servono >= 4 osservazioni).
  2. Una osservazione da scontrino conta solo se confermata da >= 2 utenti distinti (entro ±5%, 14 gg)
     oppure se l'utente ha trust_score >= 0,8.
  3. Per ogni sorgente si prende l'osservazione valida più recente; vince il punteggio più alto:
       score = confidenza_sorgente * exp(-giorni/14) * (1 + 0,1 * min(conferme, 5))
"""
from __future__ import annotations

import datetime as dt
import math
from statistics import median

SOURCE_CONF = {"online": 0.9, "flyer": 0.7, "receipt": 0.5}


def _paid(o: dict) -> float:
    return float(o["price_promo"] if o["price_promo"] is not None else o["price_regular"])


def flag_outliers(conn, store_id: int, product_id: int) -> list[int]:
    obs = conn.execute("""SELECT id, price_regular, price_promo FROM price_observations
                          WHERE store_id=%s AND product_id=%s AND observed_at > now() - interval '30 days'""",
                       (store_id, product_id)).fetchall()
    if len(obs) < 4:
        return []
    prices = [_paid(o) for o in obs]
    med = median(prices)
    mad = median(abs(p - med) for p in prices)
    flagged = [o["id"] for o, p in zip(obs, prices)
               if abs(p - med) > 3 * 1.4826 * mad and abs(p - med) > 0.2 * med]
    if flagged:
        conn.execute("UPDATE price_observations SET is_outlier = TRUE WHERE id = ANY(%s)", (flagged,))
    return flagged


def resolve_pair(conn, store_id: int, product_id: int, now: dt.datetime | None = None) -> dict | None:
    now = now or dt.datetime.now(dt.timezone.utc)
    flag_outliers(conn, store_id, product_id)
    obs = conn.execute("""SELECT o.*, u.trust_score FROM price_observations o LEFT JOIN users u ON u.id = o.reported_by
                          WHERE o.store_id=%s AND o.product_id=%s AND NOT o.is_outlier
                            AND o.observed_at > now() - interval '60 days'
                          ORDER BY o.observed_at DESC""", (store_id, product_id)).fetchall()
    if not obs:
        return None
    best, best_score = None, -1.0
    for source in ("online", "flyer", "receipt"):
        cand = [o for o in obs if o["source"] == source]
        if not cand:
            continue
        latest = cand[0]
        confirmations = 1
        if source == "receipt":
            p = _paid(latest)
            recent = [o for o in cand if (now - o["observed_at"]).days <= 14 and abs(_paid(o) - p) <= 0.05 * p]
            confirmations = len({o["reported_by"] for o in recent if o["reported_by"]}) or 1
            trusted = (latest["trust_score"] or 0) >= 0.8
            if confirmations < 2 and not trusted and latest["source_ref"] != "seed":
                continue
        days = max(0.0, (now - latest["observed_at"]).total_seconds() / 86400)
        base = SOURCE_CONF[source]
        if source == "receipt":                       # 0,5 -> 0,95 con il consenso di più utenti
            base = min(0.95, base + 0.15 * (confirmations - 1))
        score = base * math.exp(-days / 14) * (1 + 0.1 * min(confirmations, 5))
        if score > best_score:
            best, best_score = (latest, confirmations), score
    if not best:
        return None
    o, confirmations = best
    current = conn.execute("SELECT * FROM store_prices WHERE store_id=%s AND product_id=%s", (store_id, product_id)).fetchone()
    today = now.date()
    paid = _paid(o)
    if o["source"] == "receipt" and current and current["price_promo"] is not None and current["promo_valid_to"] \
            and current["promo_valid_to"] >= today and abs(float(current["price_promo"]) - paid) < 0.02:
        regular, promo, cond = float(current["price_regular"]), float(current["price_promo"]), current["promo_condition"]
        vfrom, vto, details = current["promo_valid_from"], current["promo_valid_to"], current["promo_details"]
    elif o["source"] == "receipt":
        regular, promo, cond, vfrom, vto, details = paid, None, "none", None, None, None
    else:
        regular = float(o["price_regular"] if o["price_regular"] is not None else paid)
        promo = float(o["price_promo"]) if o["price_promo"] is not None else None
        cond, vfrom, vto, details = o["promo_condition"], o["valid_from"], o["valid_to"], o["promo_details"]
        if promo is not None and (promo > regular or vto is None):
            promo = None
        if promo is None and cond != "multi_buy":
            cond, vfrom, vto, details = "none", None, None, None
    prod = conn.execute("SELECT net_qty, net_unit FROM products WHERE id=%s", (product_id,)).fetchone()
    per = float(prod["net_qty"]) / (1000 if prod["net_unit"] in ("g", "ml") else 1)
    n30 = conn.execute("""SELECT count(*) AS n FROM price_observations WHERE store_id=%s AND product_id=%s
                          AND observed_at > now() - interval '30 days' AND NOT is_outlier""",
                       (store_id, product_id)).fetchone()["n"]
    from psycopg.types.json import Jsonb
    conn.execute("""INSERT INTO store_prices(store_id, product_id, price_regular, price_promo, promo_condition, promo_valid_from,
                       promo_valid_to, promo_details, unit_price_regular, primary_source, confidence, observations_30d,
                       last_observed_at, updated_at)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, now())
                    ON CONFLICT (store_id, product_id) DO UPDATE SET
                       price_regular=EXCLUDED.price_regular, price_promo=EXCLUDED.price_promo,
                       promo_condition=EXCLUDED.promo_condition, promo_valid_from=EXCLUDED.promo_valid_from,
                       promo_valid_to=EXCLUDED.promo_valid_to, promo_details=EXCLUDED.promo_details,
                       unit_price_regular=EXCLUDED.unit_price_regular, primary_source=EXCLUDED.primary_source,
                       confidence=EXCLUDED.confidence, observations_30d=EXCLUDED.observations_30d,
                       last_observed_at=EXCLUDED.last_observed_at, updated_at=now()""",
                 (store_id, product_id, regular, promo, cond, vfrom, vto, Jsonb(details) if details else None,
                  round(regular / per, 4), o["source"], round(min(0.99, best_score), 3), n30, o["observed_at"]))
    return {"store_id": store_id, "product_id": product_id, "price": paid, "source": o["source"],
            "confirmations": confirmations}
