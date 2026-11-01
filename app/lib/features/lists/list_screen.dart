import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class ListScreen extends ConsumerStatefulWidget {
  const ListScreen({super.key, required this.listId});
  final String listId;

  @override
  ConsumerState<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends ConsumerState<ListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  SearchResult? _results;
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _searching = true);
      try {
        final r = await ref.read(repositoryProvider).search(q.trim());
        if (mounted && _search.text.trim() == q.trim()) setState(() => _results = r);
      } catch (e) {
        if (mounted) showApiError(context, e);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(listDetailProvider(widget.listId));
      ref.invalidate(listsProvider);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _add({int? productId, int? genericId}) async {
    _search.clear();
    setState(() => _results = null);
    FocusScope.of(context).unfocus();
    await _run(() => ref.read(repositoryProvider).addItem(widget.listId, productId: productId, genericId: genericId));
  }

  Future<void> _rename(String current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome della lista'),
        content: TextField(controller: c, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _run(() => ref.read(repositoryProvider).renameList(widget.listId, name));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(listDetailProvider(widget.listId));
    return Scaffold(
      appBar: AppBar(
        title: detail.maybeWhen(
          data: (d) => GestureDetector(onTap: () => _rename(d.name), child: Text(d.name)),
          orElse: () => const Text('Lista'),
        ),
        actions: [
          detail.maybeWhen(
            data: (d) => IconButton(onPressed: () => _rename(d.name), icon: const Icon(Icons.edit_outlined), tooltip: 'Rinomina'),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(listDetailProvider(widget.listId))),
        data: (d) => Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(listDetailProvider(widget.listId)),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                if (d.activeSession != null) _sessionBanner(d.activeSession!) else _searchBox(),
                const SizedBox(height: 8),
                if (d.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text('La lista è vuota.\nCerca un prodotto qui sopra o aggiungilo dalle promo in Home.',
                        textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                  ),
                ..._grouped(d),
              ]),
            ),
          ),
          if (d.activeSession == null && d.items.isNotEmpty) _footer(d),
        ]),
      ),
    );
  }

  Widget _searchBox() {
    final r = _results;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _search,
        onChanged: _onQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Aggiungi: latte, De Cecco, olio…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : (_search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _results = null);
                      })),
        ),
      ),
      if (r != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (r.generics.isEmpty && r.products.isEmpty)
                const ListTile(title: Text('Nessun prodotto trovato')),
              for (final g in r.generics)
                ListTile(
                  dense: true,
                  leading: const Tag('Generico'),
                  title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('qualsiasi marca'),
                  onTap: () => _add(genericId: g.id),
                ),
              for (final p in r.products)
                ListTile(
                  dense: true,
                  leading: const Tag('Marca'),
                  title: Text(p.name),
                  onTap: () => _add(productId: p.id),
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _sessionBanner(ShoppingSession s) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Spesa in corso', style: TextStyle(fontWeight: FontWeight.w700, color: context.saving)),
        Text(
            s.scenario == 'B'
                ? '${s.stores.length} negozi. Spunta i prodotti mentre li prendi.'
                : 'Un solo negozio: ${s.stores.first.name}.',
            style: TextStyle(color: context.muted)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => context.go('/scan'),
              child: const Text('Fine spesa: scansiona'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _run(() async {
              await ref.read(repositoryProvider).cancelRun(s.runId);
              ref.invalidate(activeSessionProvider);
            }),
            child: const Text('Annulla'),
          ),
        ]),
      ]),
    );
  }

  List<Widget> _grouped(ListDetail d) {
    final out = <Widget>[];
    final s = d.activeSession;
    if (s != null) {
      final storeOf = {for (final l in s.lines) l.itemId: l};
      for (var i = 0; i < s.stores.length; i++) {
        final st = s.stores[i];
        final items = d.items.where((it) => storeOf[it.id]?.storeId == st.id).toList();
        out.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Row(children: [
            NumberBadge(i + 1),
            const SizedBox(width: 10),
            Expanded(child: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
        ));
        out.addAll(items.map((it) => _itemRow(d, it, line: storeOf[it.id])));
      }
      final rest = d.items.where((it) => !storeOf.containsKey(it.id)).toList();
      if (rest.isNotEmpty) {
        out.add(_catHeader('Non trovati nei negozi scelti'));
        out.addAll(rest.map((it) => _itemRow(d, it)));
      }
      return out;
    }
    final cats = <String, List<ListItem>>{};
    for (final it in d.items) {
      cats.putIfAbsent(it.category, () => []).add(it);
    }
    for (final e in cats.entries) {
      out.add(_catHeader(e.key));
      out.addAll(e.value.map((it) => _itemRow(d, it)));
    }
    return out;
  }

  Widget _catHeader(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6, left: 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: .8, fontWeight: FontWeight.w700, color: context.muted)),
      );

  Widget _itemRow(ListDetail d, ListItem it, {ScenarioLine? line}) {
    final b = it.best;
    final price = line?.cost ?? b?.total;
    final where = line == null ? b?.chainName : null;
    final promo = promoTag(context, line?.promo ?? b?.promo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        onTap: () => _openItem(d, it),
        child: Row(children: [
          Checkbox(
            value: it.isChecked,
            onChanged: (v) => _run(() => ref.read(repositoryProvider).updateItem(widget.listId, it.id, checked: v)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: it.isChecked ? TextDecoration.lineThrough : null,
                    color: it.isChecked ? context.muted : null,
                  )),
              const SizedBox(height: 3),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Tag('×${qty(it.quantity)}', color: context.colors.onSurface),
                Text(it.isGeneric ? (it.brandLock ? 'solo marche note' : 'qualsiasi marca') : 'marca',
                    style: TextStyle(fontSize: 12.5, color: context.muted)),
                if (promo != null) promo,
                if (b != null && b.confidence < 0.5) Tag('stimato', color: Brand.warn, dashed: true),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(price == null ? '—' : '${line == null ? 'da ' : ''}${eur(price)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (where != null) Text(where, style: TextStyle(fontSize: 11.5, color: context.muted)),
            if (price == null) Text('non trovato', style: TextStyle(fontSize: 11.5, color: context.muted)),
          ]),
        ]),
      ),
    );
  }

  Widget _footer(ListDetail d) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('${d.items.length} voci', style: TextStyle(color: context.muted)),
          const Spacer(),
          if (d.estimateTotal > 0) Text('stima da ${eur(d.estimateTotal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => context.go('/lists/${widget.listId}/compare'),
          child: const Text('Confronta prezzi'),
        ),
      ]),
    );
  }

  Future<void> _openItem(ListDetail d, ListItem it) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(listId: widget.listId, item: it, onChanged: () {
        ref.invalidate(listDetailProvider(widget.listId));
        ref.invalidate(listsProvider);
      }),
    );
  }
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.listId, required this.item, required this.onChanged});
  final String listId;
  final ListItem item;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  late double quantity = widget.item.quantity;
  late bool brandLock = widget.item.brandLock;

  Future<void> _do(Future<void> Function() f, {bool close = false}) async {
    try {
      await f();
      widget.onChanged();
      if (mounted && close) Navigator.pop(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item, b = it.best;
    final repo = ref.read(repositoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(it.label, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Quantità (confezioni)', style: TextStyle(color: context.muted))),
          IconButton.filledTonal(
            onPressed: quantity <= 1
                ? null
                : () {
                    setState(() => quantity -= 1);
                    _do(() => repo.updateItem(widget.listId, it.id, quantity: quantity));
                  },
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 44, child: Text(qty(quantity), textAlign: TextAlign.center, style: context.text.titleLarge)),
          IconButton.filledTonal(
            onPressed: quantity >= 99
                ? null
                : () {
                    setState(() => quantity += 1);
                    _do(() => repo.updateItem(widget.listId, it.id, quantity: quantity));
                  },
            icon: const Icon(Icons.add),
          ),
        ]),
        const SizedBox(height: 8),
        if (it.isGeneric)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo marche note'),
            subtitle: const Text('Esclude le marche del supermercato'),
            value: brandLock,
            onChanged: (v) {
              setState(() => brandLock = v);
              _do(() => repo.updateItem(widget.listId, it.id, brandLock: v));
            },
          )
        else if (it.canAcceptEquivalents)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Accetta prodotti equivalenti'),
            subtitle: const Text('Confronta anche le altre marche dello stesso prodotto'),
            trailing: const Icon(Icons.swap_horiz),
            onTap: () => _do(() => repo.updateItem(widget.listId, it.id, acceptEquivalents: true), close: true),
          ),
        if (b != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Miglior prezzo noto: ${eur(b.unitPrice)} a confezione da ${b.storeName}\n'
              '${b.productName} · fonte: ${_source(b.source)}, ${b.daysOld == 0 ? 'oggi' : '${b.daysOld} gg fa'}',
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: context.colors.error),
          onPressed: () => _do(() => repo.deleteItem(widget.listId, it.id), close: true),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Rimuovi dalla lista'),
        ),
      ]),
    );
  }

  String _source(String s) => switch (s) { 'online' => 'spesa online', 'flyer' => 'volantino', _ => 'scontrini' };
}
