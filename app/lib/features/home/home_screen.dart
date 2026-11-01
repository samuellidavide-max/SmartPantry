import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _newList(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref.read(repositoryProvider).createList('Nuova lista');
      ref.invalidate(listsProvider);
      if (context.mounted) context.go('/lists/$id');
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _addPromo(BuildContext context, WidgetRef ref, Promo p) async {
    final repo = ref.read(repositoryProvider);
    try {
      var lists = await repo.lists();
      final listId = lists.isEmpty ? await repo.createList('Spesa') : lists.first.id;
      if (p.isPrivateLabel && p.genericProductId != null) {
        await repo.addItem(listId, genericId: p.genericProductId);
      } else {
        await repo.addItem(listId, productId: p.productId);
      }
      ref.invalidate(listsProvider);
      ref.invalidate(listDetailProvider(listId));
      lists = await repo.lists();
      if (context.mounted) toast(context, 'Aggiunto a "${lists.firstWhere((l) => l.id == listId).name}"');
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final savings = ref.watch(savingsProvider);
    final lists = ref.watch(listsProvider);
    final promos = ref.watch(promosProvider);
    final session = ref.watch(activeSessionProvider);
    final now = DateTime.now();
    final toPremium = (me.creditsForPremiumWeek - me.credits).clamp(0, 1000);

    return Scaffold(
      appBar: AppBar(
        title: const Text('La tua spesa'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: const Icon(Icons.place_outlined, size: 18),
              label: Text('${me.home?.cap ?? 'Zona'} · ${me.searchRadiusM ~/ 1000} km'),
              onPressed: () => context.go('/profile'),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(savingsProvider);
          ref.invalidate(listsProvider);
          ref.invalidate(promosProvider);
          ref.invalidate(activeSessionProvider);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          // Risparmio
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(18)),
            child: DefaultTextStyle(
              style: TextStyle(color: context.colors.onPrimary),
              child: savings.when(
                loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text(errorText(e)),
                data: (s) => _SavingsCard(s: s, monthName: monthsLong[now.month - 1], year: now.year),
              ),
            ),
          ),
          const SizedBox(height: 14),
          session.maybeWhen(
            data: (s) => s == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      onTap: () => context.go('/lists/${s.listId}'),
                      child: Row(children: [
                        Icon(Icons.shopping_cart_outlined, color: context.saving),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Spesa in corso: ${s.listName} · ${s.stores.length} '
                              '${s.stores.length == 1 ? 'negozio' : 'negozi'}'),
                        ),
                        const Icon(Icons.chevron_right),
                      ]),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          FilledButton.icon(
            onPressed: () => _newList(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Nuova lista'),
          ),
          const SizedBox(height: 10),
          lists.maybeWhen(
            data: (l) => l.isEmpty
                ? const SizedBox.shrink()
                : AppCard(
                    onTap: () => context.go('/lists/${l.first.id}'),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Continua: ${l.first.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${l.first.itemCount} voci', style: TextStyle(color: context.muted, fontSize: 13)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          SectionTitle('Top promo in zona',
              trailing: promos.maybeWhen(
                  data: (p) => Text('${p.length} offerte', style: TextStyle(color: context.muted, fontSize: 12)),
                  orElse: () => null)),
          SizedBox(
            height: 212,
            child: promos.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(promosProvider)),
              data: (list) => list.isEmpty
                  ? Center(child: Text('Nessuna offerta attiva in zona', style: TextStyle(color: context.muted)))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _PromoCard(p: list[i], onAdd: () => _addPromo(context, ref, list[i])),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: context.promo.withAlpha(28),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.go('/scan'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.receipt_long, color: context.promo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        toPremium == 0
                            ? 'Hai ${me.credits} crediti: riscatta 7 giorni Premium'
                            : 'Ancora ${(toPremium / 10).ceil()} scontrini per 7 giorni Premium',
                        style: TextStyle(fontWeight: FontWeight.w700, color: context.promo),
                      ),
                      Text('Serie attiva: ${me.streakWeeks} settimane', style: TextStyle(color: context.muted, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.s, required this.monthName, required this.year});
  final Savings s;
  final String monthName;
  final int year;

  @override
  Widget build(BuildContext context) {
    final on = context.colors.onPrimary;
    final mx = s.months.fold<double>(1, (a, m) => m.saving > a ? m.saving : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Risparmiato a $monthName', style: TextStyle(color: on.withAlpha(220))),
      Text(eur(s.monthSaving), style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: on, height: 1.1)),
      Text('Nel $year: ${eur(s.yearSaving)} · ${s.yearCount} spese', style: TextStyle(color: on.withAlpha(220))),
      const SizedBox(height: 10),
      SizedBox(
        height: 50,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < s.months.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 3 + 30 * s.months[i].saving / mx,
                    decoration: BoxDecoration(
                      color: on.withAlpha(i == s.months.length - 1 ? 255 : 90),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(monthsShort[s.months[i].month - 1], style: TextStyle(fontSize: 10.5, color: on.withAlpha(200))),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.p, required this.onAdd});
  final Promo p;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final multi = p.condition == 'multi_buy';
    return SizedBox(
      width: 160,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Tag(multi ? '3x2' : '−${p.pct}%${p.condition == 'loyalty_card' ? ' · carta' : ''}', color: context.promo),
          const SizedBox(height: 6),
          Text(p.productName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(eur(multi ? p.priceRegular : (p.pricePromo ?? p.priceRegular)), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            if (!multi)
              Text(eur(p.priceRegular),
                  style: TextStyle(fontSize: 12, color: context.muted, decoration: TextDecoration.lineThrough)),
          ]),
          Text('${p.storeName} · fino al ${shortDate(p.validTo)}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.muted)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(34)),
              onPressed: onAdd,
              child: const Text('+ lista'),
            ),
          ),
        ]),
      ),
    );
  }
}
