from app.optimizer import OptimizerConfig, StoreRef, optimize
from app.receipts.parser import parse_receipt_text

# Stesso esempio del documento tecnico (zona Porta Venezia, 4 store, 10 voci)
STORES = [StoreRef(1, 45.4726, 9.2066, 335), StoreRef(2, 45.4790, 9.2010, 503),
          StoreRef(3, 45.4800, 9.2100, 600), StoreRef(4, 45.4480, 9.1960, 3000)]
COST = {
    "latte": {1: 1.45, 2: 1.09, 3: 1.39, 4: 1.35}, "pasta": {1: 1.29, 3: 1.19, 4: 1.25},
    "olio": {1: 7.49, 2: 6.99, 3: 8.90, 4: 8.49}, "detersivo": {1: 1.99, 2: 0.99, 3: 1.79, 4: 1.89},
    "caffe": {1: 4.29, 2: 3.49, 3: 3.99, 4: 4.10}, "pomodori": {1: 0.99, 2: 0.79, 3: 1.09, 4: 0.95},
    "biscotti": {1: 2.19, 2: 1.49, 3: 1.99, 4: 2.05}, "acqua": {1: 1.89, 2: 1.59, 3: 1.79, 4: 1.99},
    "uova": {1: 2.49, 2: 1.99, 3: 2.59, 4: 2.39}, "carta": {1: 3.99, 2: 2.99, 3: 2.49, 4: 3.49},
}


def test_example_from_spec():
    a, alts, b, ref, tried = optimize(STORES, list(COST), COST, OptimizerConfig(max_stores=3))
    assert a.stores == [3] and a.total == 27.21 and not a.missing          # Carrefour, 10/10
    assert sorted(b.stores) == [2, 3] and b.total == 22.10                  # Eurospin + Carrefour
    assert b.gain_vs_single == 5.11 and b.worth_it
    assert 700 <= b.route_km * 1000 <= 720
    assert b.order[0] == 2                                                   # Eurospin è il più vicino all'utente
    assert all(4 not in r.stores for r in [b])                              # Coop fuori cluster


def test_single_store_preferred_when_gain_small():
    cost = {"x": {1: 1.00, 2: 0.95}, "y": {1: 2.00, 2: 1.98}}
    a, _, b, *_ = optimize(STORES[:2], ["x", "y"], cost, OptimizerConfig(max_stores=2))
    assert b is None or not b.worth_it


def test_coverage_beats_price():
    cost = {"x": {1: 5.0, 2: 1.0}, "y": {1: 5.0}}
    a, *_ = optimize(STORES[:2], ["x", "y"], cost)
    assert a.stores == [1] and not a.missing


def test_parser_quantities_discounts_total():
    text = """ESSELUNGA
VIALE PIAVE 38
P.IVA 01234567890
DOCUMENTO COMMERCIALE
LATTE GRANA PARZ. SCREM 1 L    1,59
2 X 1,49
PASTA DE CECCO SPAGH 500 G     2,98
SCONTO FIDATY                 -0,50
PELATI CIRIO 400 G x3          3,27
SUBTOTALE                      7,34
TOTALE COMPLESSIVO             7,34
PAGAMENTO ELETTRONICO          7,34"""
    r = parse_receipt_text(text)
    assert r.vat_number == "01234567890"
    assert [l.qty for l in r.lines] == [1, 2, 3]
    assert r.lines[1].discount == 0.5 and r.lines[1].unit_price == 1.49
    assert r.total_printed == 7.34 and r.total_parsed == 7.34
