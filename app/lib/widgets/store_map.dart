import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../data/models.dart';

/// Mappa OpenStreetMap: posizione utente, cerchio del raggio, negozi e percorso numerato.
class StoreMap extends StatelessWidget {
  const StoreMap({
    super.key,
    required this.center,
    required this.stores,
    this.route = const [],
    this.radiusM,
    this.height = 220,
  });

  final LatLng center;
  final List<Store> stores;
  final List<int> route;          // id negozi nell'ordine di visita
  final int? radiusM;
  final double height;

  double _zoomFor(int? radius) {
    final r = radius ?? 3000;
    if (r <= 1000) return 15;
    if (r <= 2000) return 14;
    if (r <= 5000) return 12.6;
    return 11.6;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in stores) s.id: s};
    final routeStores = route.where(byId.containsKey).map((id) => byId[id]!).toList();
    final accent = context.colors.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: routeStores.isEmpty ? center : routeStores.first.point,
            initialZoom: routeStores.isEmpty ? _zoomFor(radiusM) : 14.5,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'it.smartpantry.smartpantry',
            ),
            if (radiusM != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: center,
                  radius: radiusM!.toDouble(),
                  useRadiusInMeter: true,
                  color: accent.withAlpha(18),
                  borderColor: accent.withAlpha(120),
                  borderStrokeWidth: 1.5,
                ),
              ]),
            if (routeStores.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(points: [center, ...routeStores.map((s) => s.point)], strokeWidth: 3, color: accent),
              ]),
            MarkerLayer(markers: [
              for (final s in stores.where((s) => !route.contains(s.id)))
                Marker(
                  point: s.point,
                  width: 90,
                  height: 34,
                  child: _Pin(label: s.chainName, color: Colors.white, textColor: Colors.black87),
                ),
              for (var i = 0; i < routeStores.length; i++)
                Marker(
                  point: routeStores[i].point,
                  width: 110,
                  height: 34,
                  child: _Pin(label: '${i + 1} · ${routeStores[i].chainName}', color: accent, textColor: Colors.white),
                ),
              Marker(
                point: center,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F6FED),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.label, required this.color, required this.textColor});
  final String label;
  final Color color, textColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
      ),
    );
  }
}

extension StorePoint on Store {
  LatLng get point => LatLng(lat, lon);
}
