"""Ottimizzazione spesa: Scenario A (singolo store) vs Scenario B (2-3 store vicini).

Modulo puro (nessun accesso al DB): riceve la matrice dei costi già calcolata da pricing.py.
Fissato un insieme di store, l'assegnazione ottima è "ogni voce allo store più economico",
quindi basta enumerare le combinazioni di k<=3 store tra i migliori candidati.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from itertools import combinations, permutations
from statistics import mean


@dataclass(frozen=True)
class StoreRef:
    id: int
    lat: float
    lon: float
    dist_m: float = 0.0        # distanza dal centro di ricerca


@dataclass
class OptimizerConfig:
    max_stores: int = 2
    max_cluster_km: float = 1.5
    stop_penalty_eur: float = 1.50
    km_penalty_eur: float = 0.40
    min_gain_eur: float = 1.00
    min_items_per_store: int = 1
    top_candidates: int = 15


@dataclass
class ScenarioResult:
    stores: list[int]
    assignment: dict[str, int]
    missing: list[str]
    total: float
    reference: float
    route_km: float = 0.0
    penalty: float = 0.0
    order: list[int] = field(default_factory=list)
    gain_vs_single: float | None = None
    worth_it: bool = True

    @property
    def saving_abs(self) -> float:
        return round(self.reference - self.total, 2)

    @property
    def saving_pct(self) -> float:
        return round(100 * self.saving_abs / self.reference, 1) if self.reference else 0.0


def haversine_km(a: StoreRef, b: StoreRef) -> float:
    p1, p2 = math.radians(a.lat), math.radians(b.lat)
    dp, dl = p2 - p1, math.radians(b.lon - a.lon)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(h))


def route_km(stores: list[StoreRef]) -> float:
    if len(stores) < 2:
        return 0.0
    return min(sum(haversine_km(p[i], p[i + 1]) for i in range(len(p) - 1)) for p in permutations(stores))


def visit_order(stores: list[StoreRef]) -> list[int]:
    """Ordine di visita più corto partendo dal punto dell'utente."""
    best = min(permutations(stores),
               key=lambda p: p[0].dist_m / 1000 + sum(haversine_km(p[i], p[i + 1]) for i in range(len(p) - 1)))
    return [s.id for s in best]


def reference_prices(cost: dict[str, dict[int, float]]) -> dict[str, float]:
    return {i: mean(per.values()) for i, per in cost.items() if per}


def evaluate(combo, items, cost, ref) -> ScenarioResult:
    assignment, missing, total = {}, [], 0.0
    for i in items:
        offers = [(cost[i][s.id], s.id) for s in combo if s.id in cost.get(i, {})]
        if offers:
            price, sid = min(offers)
            assignment[i] = sid
            total += price
        else:
            missing.append(i)
    reference = sum(ref[i] for i in assignment)
    return ScenarioResult([s.id for s in combo], assignment, missing, round(total, 2), round(reference, 2))


def optimize(stores: list[StoreRef], items: list[str], cost: dict[str, dict[int, float]],
             cfg: OptimizerConfig | None = None):
    """Ritorna (scenario_a, alternative_a[<=3], scenario_b | None, ref_prices, combos_valutate)."""
    cfg = cfg or OptimizerConfig()
    ref = reference_prices(cost)
    singles = sorted((evaluate((s,), items, cost, ref) for s in stores),
                     key=lambda r: (len(r.missing), r.total))
    if not singles:
        return None, [], None, ref, 0
    a = singles[0]
    a.order = a.stores[:]
    by_id = {s.id: s for s in stores}
    pool = [by_id[r.stores[0]] for r in singles[: cfg.top_candidates]]

    best, best_score, tried = None, math.inf, 0
    for k in range(2, max(2, cfg.max_stores) + 1):
        if k > cfg.max_stores:
            break
        for combo in combinations(pool, k):
            if any(haversine_km(x, y) > cfg.max_cluster_km for x, y in combinations(combo, 2)):
                continue
            tried += 1
            r = evaluate(combo, items, cost, ref)
            per = {s: 0 for s in r.stores}
            for sid in r.assignment.values():
                per[sid] += 1
            if min(per.values()) < cfg.min_items_per_store:
                continue
            r.route_km = round(route_km(list(combo)), 3)
            r.penalty = round((k - 1) * cfg.stop_penalty_eur + r.route_km * cfg.km_penalty_eur, 2)
            score = len(r.missing) * 1e6 + r.total + r.penalty
            if score < best_score:
                best, best_score = r, score
    if best is not None:
        best.order = visit_order([by_id[s] for s in best.stores])
        best.gain_vs_single = round(a.total - best.total, 2)
        best.worth_it = len(best.missing) < len(a.missing) or (best.gain_vs_single - best.penalty >= cfg.min_gain_eur)
    return a, singles[:3], best, ref, tried
