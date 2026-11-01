"""Parsing del testo OCR di uno scontrino italiano in righe prodotto.

Gestisce i casi più comuni:
  LATTE PS GRANAR 1L            1,29      -> riga prodotto
  2 X 1,29                                 -> quantità per la riga successiva (stile Esselunga)
  PELATI CIRIO 400 G  x3        2,97      -> quantità in coda
  SCONTO FIDATY                -0,50      -> sconto agganciato alla riga precedente
  TOTALE COMPLESSIVO           17,88      -> totale stampato
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

PRICE_AT_END = re.compile(r"^(?P<desc>.+?)\s+(?P<price>-?\d{1,4}[.,]\d{2})\s*(?:[A-Z]{1,2}|\*)?\s*$")
QTY_LINE = re.compile(r"^\s*(?P<q>\d+(?:[.,]\d+)?)\s*[Xx×]\s*(?P<unit>\d{1,4}[.,]\d{2})\s*$")
QTY_SUFFIX = re.compile(r"\s+[Xx×](?P<q>\d{1,2})$")
SKIP = re.compile(r"\b(SUBTOTALE|CONTANTE|CONTANTI|RESTO|PAGAMENTO|BANCOMAT|CARTA DI CREDITO|ELETTRONICO|"
                  r"DI CUI IVA|IVA|NUMERO PEZZI|PEZZI|RT |DOCUMENTO COMMERCIALE|SCONTRINO)\b")
TOTAL = re.compile(r"\bTOTALE\b")
DISCOUNT = re.compile(r"\b(SCONTO|SC\.|PROMO|RIDUZIONE|BUONO)\b")
VAT = re.compile(r"P\.?\s?IVA\s*:?\s*(\d{11})")


def to_float(s: str) -> float:
    return float(s.replace(".", "").replace(",", ".")) if s.count(",") == 1 else float(s)


@dataclass
class ParsedLine:
    line_no: int
    raw_text: str
    qty: float
    unit_price: float
    line_total: float
    discount: float = 0.0


@dataclass
class ParsedReceipt:
    lines: list[ParsedLine] = field(default_factory=list)
    total_printed: float | None = None
    vat_number: str | None = None

    @property
    def total_parsed(self) -> float:
        return round(sum(l.line_total - l.discount for l in self.lines), 2)


def parse_receipt_text(text: str) -> ParsedReceipt:
    out = ParsedReceipt()
    pending_qty: tuple[float, float] | None = None
    for raw in text.splitlines():
        line = re.sub(r"\s+", " ", raw.strip().upper())
        if not line:
            continue
        if (m := VAT.search(line)) and not out.vat_number:
            out.vat_number = m.group(1)
            continue
        if m := QTY_LINE.match(line):
            pending_qty = (to_float(m.group("q")), to_float(m.group("unit")))
            continue
        m = PRICE_AT_END.match(line)
        if not m:
            continue
        desc, price = m.group("desc").strip(), to_float(m.group("price"))
        if TOTAL.search(desc) and not re.search(r"\bSUBTOTALE\b", desc):
            out.total_printed = price
            continue
        if SKIP.search(desc + " "):
            continue
        if DISCOUNT.search(desc) or price < 0:
            if out.lines:
                out.lines[-1].discount = round(out.lines[-1].discount + abs(price), 2)
            continue
        qty = 1.0
        if mq := QTY_SUFFIX.search(desc):
            qty = float(mq.group("q"))
            desc = desc[: mq.start()].strip()
        if pending_qty:
            qty = pending_qty[0]
            pending_qty = None
        out.lines.append(ParsedLine(len(out.lines) + 1, desc, qty, round(price / qty, 2), price))
    return out
