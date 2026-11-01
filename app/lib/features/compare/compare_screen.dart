import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/store_map.dart';
import '../profile/premium_sheet.dart';

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key, required this.listId});
  final String listId;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  String? scenario;               // 'A' | 'B' (default: B se conviene)
  bool starting = false;

  Future<void> _start(OptimizeResult r, String sc) async {
    setState(() => starting = true);
    try {
      await ref.read(repositoryProvider).startRun(r.runId, sc);
      ref.invalidate(activeSessionProvider);
      ref.invalidate(listDetailProvider(widget.listId));
      if (mounted) context.go('/lists/${widget.listId}');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(optimizeProvider(widget.listId));
    final me = ref.watch(meProvider);
    ref.listen(meProvider.select((m) => m.isPremium), (_, __) => ref.invalidate(optimizeProvider(widget.listId)));
    return Scaffold(
      appBar: AppBar(title: const Text('Confronto')),
      body: res.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(optimizeProvider(widget.listId))),
        data: (r) {
          final b = r.scenarioB;
          final bGood = b != null && b.worthIt;
          final sc = scenario ?? (bGood ? 'B' : 'A');
          final center = me.home == null ? r.stores.first.point : LatLng(me.home!.lat, me.home!.lon);
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                _headline(r),
                const SizedBox(height: 14),
                _bars(r),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'A', label: Text('A · Un negozio')),
                    ButtonSegment(value: 'B', label: Text('B · Risparmio max')),
                  ],
                  selected: {sc},
                  onSelectionChanged: (s) => setState(() => scenario = s.first),
                ),
                const SizedBox(height: 14),
                if (sc == 'A') ..._panelA(r, center) else ..._panelB(r, center),
                const SizedBox(height: 8),
                Text('Le promo con carta fedeltà valgono solo per le carte indicate nel Profilo.',
                    style: TextStyle(fontSize: 12, color: context.muted)),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: starting || (sc == 'B' && (b == null || b.locked)) ? null : () => _start(r, sc),
                      child: const Text('Avvia spesa'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _clickCollect(r, sc),
                      child: const Text('Click & Collect'),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _headline(OptimizeResult r) {
    final a = r.scenarioA, b = r.scenarioB;
    final good = (b != null && b.worthIt && (b.gainVsSingle ?? 0) > 0) ? b : null;
    final best = (good != null && !good.locked) ? good : a;
    final style = context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(
        good != null
            ? TextSpan(children: [
                const TextSpan(text: 'Risparmi fino a '),
                TextSpan(text: eur(good.gainVsSingle!), style: TextStyle(color: context.saving)),
                const TextSpan(text: ' oggi'),
              ])
            : TextSpan(children: [
                const TextSpan(text: 'Conviene un solo negozio: '),
                TextSpan(text: r.store(a.stores.first).chainName, style: TextStyle(color: context.saving)),
              ]),
        style: style,
      ),
      const SizedBox(height: 4),
      Text(
        'Rispetto al miglior negozio singolo. Rispetto alla media della zona risparmi '
        '${eur(best.savingAbs)} (${best.savingPct.toStringAsFixed(1).replaceAll('.', ',')}%).',
        style: TextStyle(color: context.muted),
      ),
    ]);
  }

  Widget _bars(OptimizeResult r) {
    final a = r.scenarioA, b = r.scenarioB;
    final values = [r.referenceTotal, a.total, if (b != null && !b.locked) b.total];
    final mx = values.reduce((x, y) => x > y ? x : y);
    Widget bar(String label, double v, Color c, {String? text, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 86, child: Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : null))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: LinearProgressIndicator(
                  value: mx == 0 ? 0 : v / mx,
                  minHeight: 14,
                  color: c,
                  backgroundColor: context.colors.surfaceContainerHighest,
                ),
              ),
            ),
            SizedBox(
              width: 78,
              child: Text(text ?? eur(v),
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : null)),
            ),
          ]),
        );
    return Column(children: [
      bar('Media zona', r.referenceTotal, context.colors.outlineVariant),
      bar('A · 1 negozio', a.total, context.muted),
      if (b != null)
        bar('B · ${b.storeCount} negozi', b.locked ? mx * 0.85 : b.total, context.saving,
            text: b.locked ? '•••' : null, bold: true),
    ]);
  }

  List<Widget> _panelA(OptimizeResult r, LatLng center) {
    return [
      StoreMap(center: center, stores: r.stores, route: [r.scenarioA.stores.first], radiusM: r.radiusM),
      const SizedBox(height: 12),
      for (var i = 0; i < r.alternatives.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _StoreCard(
            index: i + 1,
            muted: i > 0,
            store: r.store(r.alternatives[i].stores.first),
            scenario: r.alternatives[i],
            result: r,
            initiallyOpen: i == 0,
            showVsMedia: true,
          ),
        ),
    ];
  }

  List<Widget> _panelB(OptimizeResult r, LatLng center) {
    final b = r.scenarioB;
    if (b == null) {
      return [
        AppCard(
          child: Text('Nessuna combinazione di negozi abbastanza vicini tra loro (max 1,5 km). '
              'Lo scenario A resta la scelta migliore.'),
        ),
      ];
    }
    if (b.locked) {
      return [
        AppCard(
          child: Column(children: [
            Icon(Icons.lock_outline, color: context.saving, size: 32),
            const SizedBox(height: 8),
            Text('Con Premium vedi dove comprare ogni prodotto',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              (b.gainVsSingle ?? 0) > 0
                  ? 'Dividendo la spesa fra ${b.storeCount} negozi risparmi ${eur(b.gainVsSingle!)} su questa lista.'
                  : 'Scopri se conviene dividere la spesa fra più negozi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => showPremiumSheet(context), child: const Text('Prova Premium')),
          ]),
        ),
      ];
    }
    return [
      if (!b.worthIt)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: Text(
              'Non conviene dividere la spesa: il risparmio (${eur(b.gainVsSingle ?? 0)}) non copre il costo '
              'di una fermata in più (${eur(b.penalty)}).',
            ),
          ),
        ),
      StoreMap(center: center, stores: r.stores, route: b.stores, radiusM: r.radiusM),
      const SizedBox(height: 8),
      Text('Distanza tra i negozi: ${km(b.routeM)} · copertura ${b.covered}/${b.itemCount} · '
          '${r.combosEvaluated} combinazioni valutate',
          style: TextStyle(color: context.muted, fontSize: 13)),
      const SizedBox(height: 10),
      for (var i = 0; i < b.stores.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _StoreCard(
            index: i + 1,
            store: r.store(b.stores[i]),
            scenario: b,
            result: r,
            onlyStore: b.stores[i],
            initiallyOpen: true,
          ),
        ),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'Totale ${eur(b.total)} · ', style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(
          text: '−${eur(b.savingAbs)} (${b.savingPct.toStringAsFixed(1).replaceAll('.', ',')}%) rispetto alla media della zona',
          style: TextStyle(color: context.saving),
        ),
      ])),
    ];
  }

  void _clickCollect(OptimizeResult r, String sc) {
    final ids = sc == 'B' && r.scenarioB != null && !r.scenarioB!.locked ? r.scenarioB!.stores : [r.scenarioA.stores.first];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Click & Collect', style: ctx.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Nella versione con le catene collegate, qui si apre il portale della catena con il carrello già pronto.'),
          const SizedBox(height: 8),
          for (final id in ids)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.store(id).name),
              trailing: Tag(r.store(id).clickCollect ? 'Disponibile' : 'Non disponibile',
                  color: r.store(id).clickCollect ? ctx.saving : ctx.muted),
            ),
        ]),
      ),
    );
  }
}

class _StoreCard extends StatefulWidget {
  const _StoreCard({
    required this.index,
    required this.store,
    required this.scenario,
    required this.result,
    this.onlyStore,
    this.muted = false,
    this.initiallyOpen = false,
    this.showVsMedia = false,
  });
  final int index;
  final Store store;
  final Scenario scenario;
  final OptimizeResult result;
  final int? onlyStore;
  final bool muted, initiallyOpen, showVsMedia;

  @override
  State<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<_StoreCard> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final s = widget.scenario, r = widget.result;
    final lines = s.lines.where((l) => widget.onlyStore == null || l.storeId == widget.onlyStore).toList();
    final sub = lines.fold<double>(0, (a, l) => a + l.cost);
    final diff = s.reference - s.total;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          NumberBadge(widget.index, muted: widget.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.store.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                widget.onlyStore == null
                    ? '${s.covered}/${s.itemCount} prodotti trovati · ${km(widget.store.distM)}'
                    : '${lines.length} ${lines.length == 1 ? 'prodotto' : 'prodotti'}'
                        '${widget.store.clickCollect ? ' · Click & Collect' : ''}',
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(eur(widget.onlyStore == null ? s.total : sub), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (widget.showVsMedia)
              Text(diff >= 0 ? '−${eur(diff)} vs media' : '+${eur(-diff)} vs media',
                  style: TextStyle(fontSize: 11.5, color: diff >= 0 ? context.saving : context.muted)),
          ]),
        ]),
        TextButton(
          onPressed: () => setState(() => open = !open),
          child: Text(open ? 'Nascondi prodotti' : 'Mostra prodotti'),
        ),
        if (open) ...[
          const Divider(height: 1),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.itemLabel(l.itemId)}  ×${l.packs}', style: const TextStyle(fontSize: 13.5)),
                    Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(l.productName, style: TextStyle(fontSize: 12, color: context.muted)),
                      if (promoTag(context, l.promo) != null) promoTag(context, l.promo)!,
                    ]),
                  ]),
                ),
                Text(eur(l.cost), style: const TextStyle(fontSize: 13.5)),
              ]),
            ),
          if (widget.onlyStore == null)
            for (final m in s.missing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(r.itemLabel(m), style: TextStyle(color: context.muted))),
                  Text('non trovato', style: TextStyle(color: context.muted, fontSize: 12)),
                ]),
              ),
        ],
      ]),
    );
  }
}
