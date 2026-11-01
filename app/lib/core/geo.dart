import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

class GeoPoint {
  GeoPoint(this.lat, this.lon, [this.label]);
  final double lat, lon;
  final String? label;
}

class GeoException implements Exception {
  GeoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Posizione GPS del telefono (chiede il permesso se serve).
Future<GeoPoint> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw GeoException('La localizzazione è disattivata: attivala o inserisci il CAP');
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw GeoException('Permesso posizione negato: inserisci il CAP');
  }
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
  );
  return GeoPoint(p.latitude, p.longitude, 'La mia posizione');
}

/// CAP italiano -> coordinate tramite Nominatim (OpenStreetMap).
/// Va bene per sviluppo e test; in produzione meglio un geocoder a pagamento o una tabella CAP nel backend.
Future<GeoPoint> geocodeCap(String cap) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    headers: {'User-Agent': 'SmartPantry/0.1 (app di sviluppo)'},
  ));
  try {
    final r = await dio.get('https://nominatim.openstreetmap.org/search',
        queryParameters: {'postalcode': cap, 'country': 'it', 'format': 'json', 'limit': 1});
    final list = r.data as List;
    if (list.isEmpty) throw GeoException('CAP $cap non trovato');
    final m = list.first as Map;
    return GeoPoint(double.parse('${m['lat']}'), double.parse('${m['lon']}'), 'CAP $cap');
  } on DioException {
    throw GeoException('Non riesco a cercare il CAP: controlla la connessione');
  }
}
