import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

enum _Step { idle, uploading, review, done }

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  _Step step = _Step.idle;
  Uint8List? photo;
  Receipt? receipt;
  ConfirmResult? result;
  bool busy = false;

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 2000);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _upload(bytes);
  }

  Future<void> _upload(Uint8List bytes) async {
    setState(() {
      photo = bytes;
      step = _Step.uploading;
    });
    try {
      final r = await ref.read(repositoryProvider).uploadReceipt(bytes);
      if (!mounted) return;
      setState(() {
        receipt = r;
        step = _Step.review;
      });
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => step = _Step.idle);
      }
    }
  }

  Future<void> _fix(ReceiptLine l, int? productId) async {
    try {
      final r = await ref.read(repositoryProvider).fixReceiptLine(receipt!.id, l.lineNo, productId);
      if (mounted) setState(() => receipt = r);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _confirm() async {
    setState(() => busy = true);
    try {
      final res = await ref.read(repositoryProvider).confirmReceipt(receipt!.id);
      await ref.read(sessionProvider.notifier).refreshMe();
      ref.invalidate(savingsProvider);
      ref.invalidate(activeSessionProvider);
      ref.invalidate(listsProvider);
      if (!mounted) return;
      setState(() {
        result = res;
        step = _Step.done;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _reset() => setState(() {
        step = _Step.idle;
        photo = null;
        receipt = null;
        result = null;
      });

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (step) {
          _Step.review => 'Verifica scontrino',
          _Step.done => 'Grazie!',
          _ => 'Scansiona scontrino',
        }),
        leading: step == _Step.review ? IconButton(onPressed: _reset, icon: const Icon(Icons.close)) : null,
      ),
      body: switch (step) {
        _Step.idle => _idle(me),
        _Step.uploading => _uploading(),
        _Step.review => _review(),
        _Step.done => _done(me),
      },
    );
  }

  Widget _credits(Me me) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Crediti', style: TextStyle(fontWeight: FontWeight.w700))),
            Text('${me.credits}/${me.creditsForPremiumWeek}'),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(value: (me.credits / me.creditsForPremiumWeek).clamp(0, 1).toDouble(), minHeight: 10),
          ),
          const SizedBox(height: 8),
          Text('+10 crediti per ogni scontrino validato, +5 se mantieni la serie settimanale. '
              '${me.creditsForPremiumWeek} crediti = 7 giorni Premium.',
              style: TextStyle(color: context.muted, fontSize: 13)),
          if (me.credits >= me.creditsForPremiumWeek) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                try {
                  final m = await ref.read(repositoryProvider).redeemPremium();
                  ref.read(sessionProvider.notifier).setMe(m);
                  if (mounted) toast(context, '7 giorni Premium attivati');
                } catch (e) {
                  if (mounted) showApiError(context, e);
                }
              },
              child: const Text('Riscatta 7 giorni Premium'),
            ),
          ],
        ]),
      );

  Widget _idle(Me me) {
    final session = ref.watch(activeSessionProvider);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF0B0F0D), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(20),
            child: const Text(
              'Appoggia lo scontrino su un piano scuro, ben illuminato.\nTieni il telefono parallelo e inquadralo tutto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Fotografa lo scontrino'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
            onPressed: () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Scegli dalla galleria'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      session.maybeWhen(
        data: (s) => s == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                    child: Text('Spesa in corso: lo scontrino verrà collegato a ${s.stores.first.name}.')),
              ),
        orElse: () => const SizedBox.shrink(),
      ),
      _credits(me),
      if (me.devMode)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Modalità sviluppo: il server usa l\'OCR demo, che genera lo scontrino dai prezzi del negozio '
            '(la foto non viene letta). Con OCR_PROVIDER=google_vision legge la foto vera.',
            style: TextStyle(color: context.muted, fontSize: 12),
          ),
        ),
    ]);
  }

  Widget _uploading() => ListView(padding: const EdgeInsets.all(16), children: [
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(photo!, height: 320, fit: BoxFit.cover, color: Colors.black38, colorBlendMode: BlendMode.darken),
          ),
        const SizedBox(height: 20),
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        const Text('Leggo lo scontrino e riconosco i prodotti…', textAlign: TextAlign.center),
      ]);

  Widget _review() {
    final r = receipt!;
    final pending = r.lines.where((l) => l.needsReview).length;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.storeName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${r.lines.length} righe riconosciute', style: TextStyle(color: context.muted)),
            ]),
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(children: [
              for (final l in r.lines) ...[
                _line(l),
                const Divider(height: 14),
              ],
              Row(children: [
                Icon(r.totalsMatch ? Icons.check_circle : Icons.error_outline,
                    size: 18, color: r.totalsMatch ? context.saving : context.colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.totalsMatch ? 'Totale letto = stampato' : 'Il totale non torna: rifai la foto',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(eur(r.totalPrinted ?? r.totalParsed ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace')),
              ]),
            ]),
          ),
          const SizedBox(height: 8),
          Text('I prezzi confermati entrano nel database dopo il controllo anti-anomalie e diventano visibili a tutti.',
              style: TextStyle(color: context.muted, fontSize: 12)),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: pending > 0 || busy || !r.totalsMatch ? null : _confirm,
            child: Text(pending > 0 ? 'Scegli il prodotto per le righe con ?' : 'Conferma e invia · +10 crediti'),
          ),
        ),
      ),
    ]);
  }

  Widget _line(ReceiptLine l) {
    const mono = TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 13);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 2, right: 8),
        child: l.needsReview
            ? Text('?', style: TextStyle(color: Brand.warn, fontWeight: FontWeight.w800))
            : Icon(Icons.check, size: 16, color: context.saving),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${l.rawText}${l.qty > 1 ? ' x${qty(l.qty)}' : ''}', style: mono),
          if (!l.needsReview)
            Text('→ ${l.productName}', style: TextStyle(color: context.muted, fontSize: 12.5))
          else
            DropdownButton<int?>(
              isExpanded: true,
              hint: const Text('Quale prodotto è?'),
              value: null,
              items: [
                for (final c in l.candidates)
                  DropdownMenuItem(value: c.productId, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => _fix(l, v),
            ),
          if (l.discount > 0) Text('sconto −${eur(l.discount)}', style: TextStyle(color: context.promo, fontSize: 12)),
        ]),
      ),
      Text(eur(l.lineTotal), style: mono),
    ]);
  }

  Widget _done(Me me) {
    final r = result!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Scontrino validato', style: TextStyle(color: context.colors.onPrimary.withAlpha(220))),
          Text('+${r.creditsAwarded} crediti',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: context.colors.onPrimary)),
          Text(
            '${r.pricesSubmitted} prezzi inviati per la tua zona'
            '${r.streakBonus > 0 ? ' · bonus serie di ${r.streakWeeks} settimane' : ''}',
            style: TextStyle(color: context.colors.onPrimary.withAlpha(220)),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (r.savingConfirmed != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Risparmio confermato: ', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: eur(r.savingConfirmed!), style: TextStyle(fontWeight: FontWeight.w700, color: context.saving)),
              const TextSpan(text: '\nLo trovi nella Home.'),
            ])),
          ),
        ),
      _credits(me),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: _reset, child: const Text('Scansiona un altro scontrino')),
    ]);
  }
}
