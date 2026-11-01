import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import 'models.dart';

/// Tutte le chiamate al backend in un unico punto.
class Repository {
  Repository(this.api);
  final ApiClient api;

  static const _tokenKey = 'auth_token';
  static const _deviceKey = 'device_id';

  // ---------- Autenticazione anonima ----------
  Future<Me> signIn() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved != null) {
      api.token = saved;
      try {
        return await me();
      } on ApiException catch (e) {
        if (e.status != 401) rethrow;      // token scaduto o DB azzerato: nuovo accesso
      }
    }
    var device = prefs.getString(_deviceKey);
    if (device == null) {
      final r = Random.secure();
      device = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_deviceKey, device);
    }
    final res = await api.post('/v1/auth/anonymous', body: {'device_id': device}) as Map;
    api.token = res['token'] as String;
    await prefs.setString(_tokenKey, res['token'] as String);
    return Me.fromJson(Map<String, dynamic>.from(res['user'] as Map));
  }

  Future<void> signOutAndReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_deviceKey);
    await prefs.remove('onboarded');
    api.token = null;
  }

  // ---------- Utente ----------
  Future<Me> me() async => Me.fromJson(Map<String, dynamic>.from(await api.get('/v1/me') as Map));

  Future<Me> updateMe({double? lat, double? lon, String? cap, int? radiusM, List<int>? loyaltyChainIds}) async {
    final body = <String, dynamic>{
      if (lat != null) 'home_lat': lat,
      if (lon != null) 'home_lon': lon,
      if (cap != null) 'home_cap': cap,
      if (radiusM != null) 'search_radius_m': radiusM,
      if (loyaltyChainIds != null) 'loyalty_chain_ids': loyaltyChainIds,
    };
    return Me.fromJson(Map<String, dynamic>.from(await api.patch('/v1/me', body: body) as Map));
  }

  Future<Savings> savings() async => Savings.fromJson(Map<String, dynamic>.from(await api.get('/v1/me/savings') as Map));

  Future<Me> premiumDemo(bool on) async =>
      Me.fromJson(Map<String, dynamic>.from(await api.post('/v1/me/premium/demo', query: {'on': on}) as Map));

  Future<Me> redeemPremium() async =>
      Me.fromJson(Map<String, dynamic>.from(await api.post('/v1/me/premium/redeem') as Map));

  Future<void> setStorePref(int storeId, int pref) => api.put('/v1/me/store-prefs/$storeId', body: {'pref': pref});

  // ---------- Catalogo ----------
  Future<List<Chain>> chains() async =>
      (await api.get('/v1/chains') as List).map((e) => Chain.fromJson(Map<String, dynamic>.from(e as Map))).toList();

  Future<List<Store>> nearbyStores({double? lat, double? lon, int? radiusM}) async {
    final res = await api.get('/v1/stores/nearby', query: {
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (radiusM != null) 'radius_m': radiusM,
    }) as List;
    return res.map((e) => Store.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<int> seedDemoStores(double lat, double lon) async {
    final res = await api.post('/v1/dev/seed-near', body: {'lat': lat, 'lon': lon}) as Map;
    return res['stores_created'] as int;
  }

  Future<SearchResult> search(String q) async =>
      SearchResult.fromJson(Map<String, dynamic>.from(await api.get('/v1/products/search', query: {'q': q}) as Map));

  Future<List<Promo>> topPromos() async => (await api.get('/v1/promos/top', query: {'limit': 10}) as List)
      .map((e) => Promo.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  // ---------- Liste ----------
  Future<List<ListSummary>> lists() async => (await api.get('/v1/lists') as List)
      .map((e) => ListSummary.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  Future<String> createList(String name) async => (await api.post('/v1/lists', body: {'name': name}) as Map)['id'] as String;

  Future<ListDetail> list(String id) async =>
      ListDetail.fromJson(Map<String, dynamic>.from(await api.get('/v1/lists/$id') as Map));

  Future<void> renameList(String id, String name) => api.patch('/v1/lists/$id', body: {'name': name});

  Future<void> deleteList(String id) => api.delete('/v1/lists/$id');

  Future<void> addItem(String listId, {int? productId, int? genericId, double quantity = 1}) => api.post(
        '/v1/lists/$listId/items',
        body: {
          if (productId != null) 'product_id': productId,
          if (genericId != null) 'generic_product_id': genericId,
          'quantity': quantity,
        },
      );

  Future<void> updateItem(String listId, String itemId,
          {double? quantity, bool? brandLock, bool? checked, bool? acceptEquivalents}) =>
      api.patch('/v1/lists/$listId/items/$itemId', body: {
        if (quantity != null) 'quantity': quantity,
        if (brandLock != null) 'brand_lock': brandLock,
        if (checked != null) 'is_checked': checked,
        if (acceptEquivalents != null) 'accept_equivalents': acceptEquivalents,
      });

  Future<void> deleteItem(String listId, String itemId) => api.delete('/v1/lists/$listId/items/$itemId');

  Future<OptimizeResult> optimize(String listId) async =>
      OptimizeResult.fromJson(Map<String, dynamic>.from(await api.post('/v1/lists/$listId/optimize') as Map));

  Future<ShoppingSession> startRun(String runId, String scenario) async => ShoppingSession.fromJson(
      Map<String, dynamic>.from(await api.post('/v1/runs/$runId/start', body: {'scenario': scenario}) as Map));

  Future<void> cancelRun(String runId) => api.post('/v1/runs/$runId/cancel');

  Future<ShoppingSession?> activeSession() async {
    final r = await api.get('/v1/sessions/active');
    return r == null ? null : ShoppingSession.fromJson(Map<String, dynamic>.from(r as Map));
  }

  // ---------- Scontrini ----------
  Future<Receipt> uploadReceipt(List<int> bytes, {int? storeId}) async => Receipt.fromJson(Map<String, dynamic>.from(
      await api.upload('/v1/receipts', bytes, 'scontrino.jpg', fields: {if (storeId != null) 'store_id': storeId})
          as Map));

  Future<Receipt> fixReceiptLine(String receiptId, int lineNo, int? productId) async => Receipt.fromJson(
      Map<String, dynamic>.from(
          await api.patch('/v1/receipts/$receiptId/lines/$lineNo', body: {'product_id': productId}) as Map));

  Future<ConfirmResult> confirmReceipt(String receiptId) async =>
      ConfirmResult.fromJson(Map<String, dynamic>.from(await api.post('/v1/receipts/$receiptId/confirm') as Map));
}
