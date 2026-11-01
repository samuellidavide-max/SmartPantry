import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// Repository inizializzato in main() con l'URL del server salvato.
final repositoryProvider = Provider<Repository>((ref) => throw UnimplementedError('override in main'));

/// Stato di accesso: utente corrente + onboarding completato.
class AppSession {
  AppSession(this.me, this.onboarded);
  final Me me;
  final bool onboarded;
  AppSession copyWith({Me? me, bool? onboarded}) => AppSession(me ?? this.me, onboarded ?? this.onboarded);
}

class SessionNotifier extends AsyncNotifier<AppSession> {
  @override
  Future<AppSession> build() async {
    final repo = ref.read(repositoryProvider);
    final me = await repo.signIn();
    final prefs = await SharedPreferences.getInstance();
    final onboarded = (prefs.getBool('onboarded') ?? false) && me.home != null;
    return AppSession(me, onboarded);
  }

  Repository get _repo => ref.read(repositoryProvider);

  void setMe(Me me) {
    final s = state.valueOrNull;
    if (s != null) state = AsyncData(s.copyWith(me: me));
  }

  Future<void> refreshMe() async => setMe(await _repo.me());

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    final s = state.valueOrNull;
    if (s != null) state = AsyncData(s.copyWith(me: await _repo.me(), onboarded: true));
  }

  Future<void> reset() async {
    await _repo.signOutAndReset();
    state = await AsyncValue.guard(build);
  }

  /// Cambia server (es. IP del computer in rete locale) e rifà l'accesso.
  Future<void> changeServer(String url) async {
    await AppConfig.saveBaseUrl(url);
    _repo.api.baseUrl = await AppConfig.loadBaseUrl();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _repo.api.token = null;
    state = const AsyncLoading<AppSession>();
    state = await AsyncValue.guard(build);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, AppSession>(SessionNotifier.new);

/// Comodità: utente corrente (dopo l'accesso).
final meProvider = Provider<Me>((ref) => ref.watch(sessionProvider).requireValue.me);

final chainsProvider = FutureProvider<List<Chain>>((ref) => ref.read(repositoryProvider).chains());

final savingsProvider = FutureProvider.autoDispose<Savings>((ref) => ref.read(repositoryProvider).savings());

final promosProvider = FutureProvider.autoDispose<List<Promo>>((ref) {
  ref.watch(meProvider.select((m) => '${m.home?.lat},${m.home?.lon},${m.searchRadiusM},${m.loyaltyChainIds}'));
  return ref.read(repositoryProvider).topPromos();
});

final storesProvider = FutureProvider.autoDispose<List<Store>>((ref) {
  ref.watch(meProvider.select((m) => '${m.home?.lat},${m.home?.lon},${m.searchRadiusM}'));
  return ref.read(repositoryProvider).nearbyStores();
});

final listsProvider = FutureProvider.autoDispose<List<ListSummary>>((ref) => ref.read(repositoryProvider).lists());

final listDetailProvider = FutureProvider.autoDispose.family<ListDetail, String>((ref, id) {
  ref.watch(meProvider.select((m) => '${m.searchRadiusM},${m.loyaltyChainIds},${m.isPremium}'));
  return ref.read(repositoryProvider).list(id);
});

final optimizeProvider = FutureProvider.autoDispose.family<OptimizeResult, String>(
    (ref, listId) => ref.read(repositoryProvider).optimize(listId));

final activeSessionProvider =
    FutureProvider.autoDispose<ShoppingSession?>((ref) => ref.read(repositoryProvider).activeSession());

/// Messaggio d'errore leggibile per qualunque eccezione.
String errorText(Object e) => e is ApiException ? e.message : 'Si è verificato un errore imprevisto';
