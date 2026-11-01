import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/store_map.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int step = 0;
  final _cap = TextEditingController();
  GeoPoint? point;
  int radius = 5000;
  List<Store>? stores;
  bool busy = false;
  String? geoError;
  final Set<int> cards = {};

  @override
  void dispose() {
    _cap.dispose();
    super.dispose();
  }

  Future<void> _setPoint(Future<GeoPoint> Function() getter) async {
    setState(() {
      busy = true;
      geoError = null;
    });
    try {
      final p = await getter();
      final repo = ref.read(repositoryProvider);
      await repo.updateMe(lat: p.lat, lon: p.lon, cap: RegExp(r'^\d{5}$').hasMatch(_cap.text) ? _cap.text : null);
      point = p;
      await _loadStores();
    } on GeoException catch (e) {
      geoError = e.message;
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadStores() async {
    final p = point;
    if (p == null) return;
    final s = await ref.read(repositoryProvider).nearbyStores(lat: p.lat, lon: p.lon, radiusM: radius);
    if (mounted) setState(() => stores = s);
  }

  Future<void> _seedDemo() async {
    final p = point;
    if (p == null) return;
    setState(() => busy = true);
    try {
      final n = await ref.read(repositoryProvider).seedDemoStores(p.lat, p.lon);
      await _loadStores();
      if (mounted) toast(context, 'Creati $n negozi demo attorno a te');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).updateMe(radiusM: radius, loyaltyChainIds: cards.toList());
      await ref.read(sessionProvider.notifier).completeOnboarding();
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == step ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == step ? context.colors.primary : context.colors.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            Expanded(child: [_welcome, _zone, _cards][step](context, me)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : _next(),
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(['Inizia', 'Continua', 'Fatto, vai alla Home'][step]),
            ),
          ]),
        ),
      ),
    );
  }

  VoidCallback? _next() {
    switch (step) {
      case 0:
        return () => setState(() => step = 1);
      case 1:
        return point == null ? null : () => setState(() => step = 2);
      default:
        return _finish;
    }
  }

  Widget _welcome(BuildContext context, Me me) {
    Widget bullet(String n, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
                radius: 18,
                backgroundColor: context.colors.primaryContainer,
                child: Text(n, style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.onPrimaryContainer))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(body, style: TextStyle(color: context.muted, fontSize: 13.5)),
              ]),
            ),
          ]),
        );
    return ListView(children: [
      Text('Stessa spesa,', style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
      Text('meno euro.',
          style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: context.saving)),
      const SizedBox(height: 12),
      Text('SmartPantry confronta i prezzi dei supermercati vicini a te e ti dice dove conviene comprare ogni prodotto.',
          style: TextStyle(color: context.muted, fontSize: 15)),
      const SizedBox(height: 24),
      bullet('1', 'Scrivi la lista', 'Prodotti generici ("olio EVO") o di una marca precisa.'),
      bullet('2', 'Confronta due strategie', 'Tutto in un solo negozio, oppure diviso fra 2–3 negozi vicini.'),
      bullet('3', 'Scansiona lo scontrino', 'Aggiorni i prezzi per tutti e guadagni giorni Premium.'),
    ]);
  }

  Widget _zone(BuildContext context, Me me) {
    final p = point;
    return ListView(children: [
      Text('Dove fai la spesa?', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: busy ? null : () => _setPoint(currentPosition),
        icon: const Icon(Icons.my_location),
        label: const Text('Usa la mia posizione'),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _cap,
            keyboardType: TextInputType.number,
            maxLength: 5,
            decoration: const InputDecoration(labelText: 'Oppure scrivi il CAP', counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: busy
              ? null
              : () {
                  if (!RegExp(r'^\d{5}$').hasMatch(_cap.text)) {
                    setState(() => geoError = 'Il CAP ha 5 cifre');
                    return;
                  }
                  _setPoint(() => geocodeCap(_cap.text));
                },
          icon: const Icon(Icons.search),
        ),
      ]),
      if (geoError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(geoError!, style: TextStyle(color: context.colors.error)),
        ),
      const SizedBox(height: 16),
      Text('Raggio di ricerca', style: TextStyle(color: context.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final r in [2000, 5000, 10000])
          ChoiceChip(
            label: Text('${r ~/ 1000} km${r > me.maxRadiusM ? ' · Premium' : ''}'),
            selected: radius == r,
            onSelected: r > me.maxRadiusM
                ? null
                : (_) async {
                    setState(() => radius = r);
                    try {
                      await _loadStores();
                    } catch (e) {
                      if (mounted) showApiError(context, e);
                    }
                  },
          ),
      ]),
      const SizedBox(height: 12),
      if (p != null) ...[
        StoreMap(center: LatLng(p.lat, p.lon), stores: stores ?? const [], radiusM: radius),
        const SizedBox(height: 8),
        if (stores != null && stores!.isNotEmpty)
          Text('${stores!.length} supermercati in zona · ${stores!.map((s) => s.chainName).toSet().length} catene',
              style: TextStyle(color: context.muted)),
        if (stores != null && stores!.isEmpty) ...[
          Text('Non ci sono ancora supermercati con prezzi in questa zona.', style: TextStyle(color: context.muted)),
          if (me.devMode)
            TextButton.icon(
              onPressed: busy ? null : _seedDemo,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Crea negozi demo qui (modalità sviluppo)'),
            ),
        ],
      ],
    ]);
  }

  Widget _cards(BuildContext context, Me me) {
    final chains = ref.watch(chainsProvider);
    return ListView(children: [
      Text('Quali carte fedeltà hai?', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Alcune offerte valgono solo con la carta della catena. Le conteggiamo solo se ce l\'hai.',
          style: TextStyle(color: context.muted)),
      const SizedBox(height: 16),
      chains.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(chainsProvider)),
        data: (list) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in list.where((c) => c.loyaltyCardName != null))
            FilterChip(
              label: Text('${c.loyaltyCardName} · ${c.name}'),
              selected: cards.contains(c.id),
              onSelected: (v) => setState(() => v ? cards.add(c.id) : cards.remove(c.id)),
            ),
        ]),
      ),
    ]);
  }
}
