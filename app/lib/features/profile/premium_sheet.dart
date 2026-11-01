import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';

Future<void> showPremiumSheet(BuildContext context, {String? reason}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _PremiumSheet(reason: reason),
  );
}

class _PremiumSheet extends ConsumerWidget {
  const _PremiumSheet({this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    Widget perk(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [Icon(Icons.check, color: context.saving, size: 20), const SizedBox(width: 8), Expanded(child: Text(t))]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('SmartPantry Premium', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (reason != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(reason!, style: TextStyle(color: context.muted))),
        const SizedBox(height: 14),
        perk('Scenario multi-negozio completo, fino a 3 negozi'),
        perk('Liste illimitate'),
        perk('Raggio di ricerca fino a 10 km'),
        const SizedBox(height: 10),
        Text('Oppure: ${me.creditsForPremiumWeek} crediti da scontrini = 7 giorni gratis (hai ${me.credits} crediti).',
            style: TextStyle(color: context.muted, fontSize: 13)),
        const SizedBox(height: 16),
        if (me.devMode)
          FilledButton(
            onPressed: () async {
              final repo = ref.read(repositoryProvider);
              final notifier = ref.read(sessionProvider.notifier);
              try {
                final m = await repo.premiumDemo(true);
                notifier.setMe(m);
                if (context.mounted) Navigator.pop(context);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Attiva Premium (demo, gratis)'),
          )
        else
          // In produzione: acquisto in-app (es. RevenueCat / in_app_purchase) che notifica il backend.
          const FilledButton(onPressed: null, child: Text('Abbonamento in arrivo')),
      ]),
    );
  }
}
