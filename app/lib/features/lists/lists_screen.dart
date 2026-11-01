import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class ListsScreen extends ConsumerStatefulWidget {
  const ListsScreen({super.key});

  @override
  ConsumerState<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends ConsumerState<ListsScreen> {
  /// Liste appena eliminate con lo swipe: vanno tolte subito dall'albero, altrimenti
  /// il Dismissible già chiuso verrebbe ricostruito con i dati vecchi (errore di Flutter).
  final Set<String> _removed = {};

  Future<void> _delete(String id) async {
    setState(() => _removed.add(id));
    try {
      await ref.read(repositoryProvider).deleteList(id);
    } catch (e) {
      if (mounted) {
        setState(() => _removed.remove(id));
        showApiError(context, e);
      }
    }
    if (mounted) ref.invalidate(listsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(listsProvider);
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Le tue liste')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            final id = await ref.read(repositoryProvider).createList('Nuova lista');
            ref.invalidate(listsProvider);
            if (context.mounted) context.go('/lists/$id');
          } catch (e) {
            if (context.mounted) showApiError(context, e);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuova lista'),
      ),
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(listsProvider)),
        data: (all) {
          final l = all.where((x) => !_removed.contains(x.id)).toList();
          return RefreshIndicator(
          onRefresh: () async => ref.invalidate(listsProvider),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
            if (l.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Nessuna lista. Creane una per iniziare.',
                    textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
              ),
            for (final x in l)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Dismissible(
                  key: ValueKey(x.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: context.colors.errorContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.delete_outline, color: context.colors.onErrorContainer),
                  ),
                  onDismissed: (_) => _delete(x.id),
                  child: AppCard(
                    onTap: () => context.go('/lists/${x.id}'),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text('${x.itemCount} voci · ${x.checkedCount} spuntate',
                              style: TextStyle(color: context.muted, fontSize: 13)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
                ),
              ),
            if (!me.isPremium)
              Text('Con il piano Free puoi avere 1 lista attiva. Premium: liste illimitate.',
                  style: TextStyle(color: context.muted, fontSize: 13)),
          ]),
          );
        },
      ),
    );
  }
}
