import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../features/profile/premium_sheet.dart';

/// Mostra un errore API: se serve Premium apre direttamente il foglio Premium.
void showApiError(BuildContext context, Object e) {
  if (e is ApiException && e.isPremiumRequired) {
    showPremiumSheet(context, reason: e.message);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Errore imprevisto')));
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

/// Riquadro bianco con bordo sottile: il "card" dell'app (indipendente dalla versione di Flutter).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = context.isDark ? const Color(0xFF27322C) : const Color(0xFFD9E1DC);
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: context.muted),
          const SizedBox(height: 12),
          Text(error is ApiException ? (error as ApiException).message : 'Errore imprevisto',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
        ]),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.dashed = false});
  final String label;
  final Color? color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: dashed ? null : c.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: dashed ? Border.all(color: c) : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

/// Etichetta promo di una voce (volantino / carta fedeltà / 3x2).
Widget? promoTag(BuildContext context, PromoInfo? p, {bool compact = true}) {
  if (p == null) return null;
  final until = compact ? '' : ' fino al ${shortDate(p.validTo)}';
  switch (p.condition) {
    case 'multi_buy':
      return Tag('3x2$until', color: context.promo);
    case 'loyalty_card':
      return Tag(p.applies ? 'Con carta$until' : 'Serve la carta', color: context.promo);
    default:
      return Tag('Volantino$until', color: context.promo);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Expanded(child: Text(text, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class NumberBadge extends StatelessWidget {
  const NumberBadge(this.n, {super.key, this.muted = false});
  final int n;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: muted ? context.colors.surfaceContainerHighest : context.colors.primary,
      child: Text('$n',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: muted ? context.colors.onSurface : context.colors.onPrimary)),
    );
  }
}
