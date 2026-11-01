import 'package:flutter_test/flutter_test.dart';
import 'package:smartpantry/core/format.dart';
import 'package:smartpantry/data/models.dart';

void main() {
  test('formato euro italiano', () {
    expect(eur(22.1), '22,10 €');
    expect(eur(1234.5), '1.234,50 €');
    expect(eur(-3.8), '−3,80 €');
  });

  test('distanze', () {
    expect(km(710), '710 m');
    expect(km(4900), '4,9 km');
  });

  test('scenario B bloccato (utente Free) si legge senza errori', () {
    final s = Scenario.fromJson({'locked': true, 'gain_vs_single': 3.8, 'worth_it': true, 'store_count': 2, 'route_m': 830});
    expect(s.locked, isTrue);
    expect(s.storeCount, 2);
    expect(s.lines, isEmpty);
  });
}
