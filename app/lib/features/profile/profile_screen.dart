import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'premium_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final _cap = TextEditingController(text: ref.read(meProvider).home?.cap ?? '');
  late final _server = TextEditingController(text: ref.read(repositoryProvider).api.baseUrl);
  bool busy = false;

  @override
  void dispose() {
    _cap.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() f, {String? ok}) async {
    setState(() => busy = true);
    try {
      await f();
      ref.invalidate(storesProvider);
      ref.invalidate(promosProvider);
      if (mounted && ok != null) toast(context, ok);
    } catch (e) {
      if (mounted) {
        if (e is GeoException) {
          toast(context, e.message);
        } else {
          showApiError(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setZone(Future<GeoPoint> Function() getter) => _do(() async {
        final p = await getter();
        final cap = RegExp(r'^\d{5}$').hasMatch(_cap.text) ? _cap.text : null;
        final m = await ref.read(repositoryProvider).updateMe(lat: p.lat, lon: p.lon, cap: cap);
        ref.read(sessionProvider.notifier).setMe(m);
      }, ok: 'Zona aggiornata');

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final chains = ref.watch(chainsProvider);
    final stores = ref.watch(storesProvider);
    final repo = ref.read(repositoryProvider);
    final notifier = ref.read(sessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Profilo')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Piano ${me.isPremium ? 'Premium' : 'Free'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                    me.plan == 'premium'
                        ? 'Attivato in modalità demo'
                        : me.premiumUntil != null && me.isPremium
                            ? 'Premium fino al ${shortDate(me.premiumUntil!)}'
                            : '1 lista · scenario A · raggio 5 km',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
                ]),
              ),
              if (me.plan == 'premium' && me.devMode)
                TextButton(
                  onPressed: () => _do(() async => notifier.setMe(await repo.premiumDemo(false))),
                  child: const Text('Torna a Free'),
                )
              else if (!me.isPremium)
                FilledButton.tonal(
                  // il tema dà ai FilledButton minimumSize Size.fromHeight (larghezza infinita): in una Row va limitata
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: () => showPremiumSheet(context),
                  child: const Text('Premium'),
                ),
            ]),
            const SizedBox(height: 12),
            Text('Crediti ${me.credits}/${me.creditsForPremiumWeek} · serie ${me.streakWeeks} settimane',
                style: TextStyle(color: context.muted, fontSize: 13)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                  value: (me.credits / me.creditsForPremiumWeek).clamp(0, 1).toDouble(), minHeight: 8),
            ),
          ]),
        ),
        const SectionTitle('Zona e raggio'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => _setZone(currentPosition),
              icon: const Icon(Icons.my_location),
              label: const Text('Usa la mia posizione'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cap,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'CAP', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: busy || !RegExp(r'^\d{5}$').hasMatch(_cap.text) ? null : () => _setZone(() => geocodeCap(_cap.text)),
                icon: const Icon(Icons.check),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final r in [2000, 5000, 10000])
                ChoiceChip(
                  label: Text('${r ~/ 1000} km${r > me.maxRadiusM ? ' · Premium' : ''}'),
                  selected: me.searchRadiusM == r,
                  onSelected: busy
                      ? null
                      : (_) {
                          if (r > me.maxRadiusM) {
                            showPremiumSheet(context, reason: 'Il raggio di 10 km è incluso in Premium');
                            return;
                          }
                          _do(() async => notifier.setMe(await repo.updateMe(radiusM: r)));
                        },
                ),
            ]),
          ]),
        ),
        const SectionTitle('Carte fedeltà'),
        chains.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(chainsProvider)),
          data: (list) => Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in list.where((c) => c.loyaltyCardName != null))
              FilterChip(
                label: Text(c.loyaltyCardName!),
                selected: me.loyaltyChainIds.contains(c.id),
                onSelected: busy
                    ? null
                    : (v) {
                        final ids = {...me.loyaltyChainIds};
                        v ? ids.add(c.id) : ids.remove(c.id);
                        _do(() async => notifier.setMe(await repo.updateMe(loyaltyChainIds: ids.toList())));
                      },
              ),
          ]),
        ),
        const SectionTitle('Negozi in zona'),
        Text('Disattiva quelli dove non vuoi andare.', style: TextStyle(color: context.muted, fontSize: 13)),
        const SizedBox(height: 6),
        stores.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(storesProvider)),
          data: (list) => AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (list.isEmpty)
                const ListTile(title: Text('Nessun negozio nel raggio')),
              for (final s in list)
                SwitchListTile(
                  title: Text(s.name),
                  subtitle: Text('${km(s.distM)}${s.clickCollect ? ' · Click & Collect' : ''}'),
                  value: s.pref != -1,
                  onChanged: busy ? null : (v) => _do(() => repo.setStorePref(s.id, v ? 0 : -1)),
                ),
            ]),
          ),
        ),
        const SectionTitle('Server'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _server,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Indirizzo del backend'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => notifier.changeServer(_server.text),
              child: const Text('Salva e ricollegati'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.colors.error),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Ricominciare da zero?'),
                content: const Text('Crei un nuovo utente: liste, crediti e storico di questo dispositivo non saranno più visibili.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Ricomincia'),
                  ),
                ],
              ),
            );
            if (ok == true) await notifier.reset();
          },
          child: const Text('Ricomincia da zero (nuovo utente)'),
        ),
      ]),
    );
  }
}
