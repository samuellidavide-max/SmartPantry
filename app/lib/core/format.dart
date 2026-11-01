/// Formattazione italiana senza dipendenze esterne.
String eur(num value) {
  final neg = value < 0;
  final cents = (value.abs() * 100).round();
  final intPart = (cents ~/ 100).toString();
  final dec = (cents % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}$buf,$dec €';
}

String km(num meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

const monthsShort = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
const monthsLong = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
];

/// "2026-11-12" -> "12/11"
String shortDate(String iso) {
  final p = iso.split('T').first.split('-');
  if (p.length < 3) return iso;
  return '${p[2]}/${p[1]}';
}

String qty(num q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString().replaceAll('.', ',');
