// Modelli dati: specchio delle risposte JSON del backend FastAPI.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    v == null ? <T>[] : (v as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();

class HomeLocation {
  HomeLocation(this.lat, this.lon, this.cap);
  final double lat, lon;
  final String? cap;
}

class Me {
  Me.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        plan = j['plan'] as String,
        isPremium = j['is_premium'] as bool,
        premiumUntil = j['premium_until'] as String?,
        credits = j['credits'] as int,
        creditsForPremiumWeek = j['credits_for_premium_week'] as int,
        home = j['home'] == null
            ? null
            : HomeLocation(_d(j['home']['lat']), _d(j['home']['lon']), j['home']['cap'] as String?),
        searchRadiusM = j['search_radius_m'] as int,
        maxRadiusM = j['max_radius_m'] as int,
        loyaltyChainIds = (j['loyalty_chain_ids'] as List).cast<int>(),
        streakWeeks = j['streak_weeks'] as int,
        devMode = j['dev_mode'] as bool? ?? false;

  final String id, plan;
  final bool isPremium, devMode;
  final String? premiumUntil;
  final int credits, creditsForPremiumWeek, searchRadiusM, maxRadiusM, streakWeeks;
  final HomeLocation? home;
  final List<int> loyaltyChainIds;
}

class Chain {
  Chain.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        slug = j['slug'] as String,
        loyaltyCardName = j['loyalty_card_name'] as String?,
        isDiscount = j['is_discount'] as bool;
  final int id;
  final String name, slug;
  final String? loyaltyCardName;
  final bool isDiscount;
}

class Store {
  Store.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        address = j['address'] as String? ?? '',
        chainId = j['chain_id'] as int? ?? 0,
        chainName = j['chain_name'] as String,
        lat = _d(j['lat']),
        lon = _d(j['lon']),
        distM = _d(j['dist_m']),
        clickCollect = j['click_collect'] as bool? ?? false,
        pref = j['pref'] as int? ?? 0,
        used = j['used'] as bool? ?? false;
  final int id, chainId, pref;
  final String name, address, chainName;
  final double lat, lon, distM;
  final bool clickCollect, used;
}

class GenericHit {
  GenericHit.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        category = j['category'] as String;
  final int id;
  final String name, category;
}

class ProductHit {
  ProductHit.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        brand = j['brand'] as String?,
        category = j['category'] as String? ?? '';
  final int id;
  final String name, category;
  final String? brand;
}

class SearchResult {
  SearchResult.fromJson(Map<String, dynamic> j)
      : generics = _list(j['generics'], GenericHit.fromJson),
        products = _list(j['products'], ProductHit.fromJson);
  final List<GenericHit> generics;
  final List<ProductHit> products;
}

class Promo {
  Promo.fromJson(Map<String, dynamic> j)
      : storeId = j['store_id'] as int,
        productId = j['product_id'] as int,
        productName = j['product_name'] as String,
        genericProductId = j['generic_product_id'] as int?,
        isPrivateLabel = j['is_private_label'] as bool,
        priceRegular = _d(j['price_regular']),
        pricePromo = _dn(j['price_promo']),
        condition = j['promo_condition'] as String,
        pct = j['pct'] as int,
        validTo = j['valid_to'] as String,
        storeName = j['store_name'] as String,
        chainName = j['chain_name'] as String,
        loyaltyCardName = j['loyalty_card_name'] as String?;
  final int storeId, productId, pct;
  final int? genericProductId;
  final bool isPrivateLabel;
  final double priceRegular;
  final double? pricePromo;
  final String productName, condition, validTo, storeName, chainName;
  final String? loyaltyCardName;
}

class PromoInfo {
  PromoInfo.fromJson(Map<String, dynamic> j)
      : condition = j['condition'] as String,
        validTo = j['valid_to'] as String,
        applies = j['applies'] as bool? ?? true;
  final String condition, validTo;
  final bool applies;
}

class BestPrice {
  BestPrice.fromJson(Map<String, dynamic> j)
      : total = _d(j['total']),
        unitPrice = _d(j['unit_price']),
        packs = j['packs'] as int,
        storeId = j['store_id'] as int,
        storeName = j['store_name'] as String,
        chainName = j['chain_name'] as String,
        productName = j['product_name'] as String,
        promo = j['promo'] == null ? null : PromoInfo.fromJson(Map<String, dynamic>.from(j['promo'] as Map)),
        confidence = _d(j['confidence']),
        source = j['source'] as String,
        daysOld = j['days_old'] as int? ?? 0;
  final double total, unitPrice, confidence;
  final int packs, storeId, daysOld;
  final String storeName, chainName, productName, source;
  final PromoInfo? promo;
}

class ListSummary {
  ListSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        status = j['status'] as String,
        itemCount = j['item_count'] as int,
        checkedCount = j['checked_count'] as int;
  final String id, name, status;
  final int itemCount, checkedCount;
}

class ListItem {
  ListItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        productId = j['product_id'] as int?,
        genericProductId = j['generic_product_id'] as int?,
        label = j['label'] as String,
        brand = j['brand'] as String?,
        category = j['category'] as String? ?? 'Altro',
        quantity = _d(j['quantity']),
        brandLock = j['brand_lock'] as bool,
        isChecked = j['is_checked'] as bool,
        canAcceptEquivalents = j['can_accept_equivalents'] as bool? ?? false,
        best = j['best'] == null ? null : BestPrice.fromJson(Map<String, dynamic>.from(j['best'] as Map));
  final String id, label, category;
  final int? productId, genericProductId;
  final String? brand;
  final double quantity;
  final bool brandLock, isChecked, canAcceptEquivalents;
  final BestPrice? best;
  bool get isGeneric => genericProductId != null;
}

class ScenarioLine {
  ScenarioLine.fromJson(Map<String, dynamic> j)
      : itemId = j['item_id'] as String,
        storeId = j['store_id'] as int,
        productId = j['product_id'] as int,
        productName = j['product_name'] as String,
        packs = j['packs'] as int,
        cost = _d(j['cost']),
        promo = j['promo'] == null ? null : PromoInfo.fromJson(Map<String, dynamic>.from(j['promo'] as Map));
  final String itemId, productName;
  final int storeId, productId, packs;
  final double cost;
  final PromoInfo? promo;
}

class SessionStore {
  SessionStore.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = j['name'] as String,
        chainName = j['chain_name'] as String;
  final int id;
  final String name, chainName;
}

class ShoppingSession {
  ShoppingSession.fromJson(Map<String, dynamic> j)
      : runId = j['run_id'] as String,
        listId = j['list_id'] as String,
        listName = j['list_name'] as String,
        scenario = j['scenario'] as String,
        stores = _list(j['stores'], SessionStore.fromJson),
        lines = _list(j['lines'], ScenarioLine.fromJson),
        estimatedSaving = _d(j['estimated_saving']);
  final String runId, listId, listName, scenario;
  final List<SessionStore> stores;
  final List<ScenarioLine> lines;
  final double estimatedSaving;
}

class ListDetail {
  ListDetail.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        status = j['status'] as String,
        items = _list(j['items'], ListItem.fromJson),
        estimateTotal = _d(j['estimate_total']),
        activeSession = j['active_session'] == null
            ? null
            : ShoppingSession.fromJson(Map<String, dynamic>.from(j['active_session'] as Map));
  final String id, name, status;
  final List<ListItem> items;
  final double estimateTotal;
  final ShoppingSession? activeSession;
}

class Scenario {
  Scenario.fromJson(Map<String, dynamic> j)
      : locked = j['locked'] as bool? ?? false,
        stores = j['stores'] == null ? <int>[] : (j['stores'] as List).cast<int>(),
        storeCount = j['store_count'] as int? ?? (j['stores'] as List?)?.length ?? 0,
        total = _d(j['total']),
        reference = _d(j['reference']),
        savingAbs = _d(j['saving_abs']),
        savingPct = _d(j['saving_pct']),
        covered = j['covered'] as int? ?? 0,
        itemCount = j['item_count'] as int? ?? 0,
        missing = j['missing'] == null ? <String>[] : (j['missing'] as List).cast<String>(),
        routeM = _d(j['route_m']),
        penalty = _d(j['penalty']),
        gainVsSingle = _dn(j['gain_vs_single']),
        worthIt = j['worth_it'] as bool? ?? true,
        lines = _list(j['lines'], ScenarioLine.fromJson);
  final bool locked, worthIt;
  final List<int> stores;
  final int storeCount, covered, itemCount;
  final double total, reference, savingAbs, savingPct, routeM, penalty;
  final double? gainVsSingle;
  final List<String> missing;
  final List<ScenarioLine> lines;
}

class OptItem {
  OptItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        label = j['label'] as String,
        quantity = _d(j['quantity']);
  final String id, label;
  final double quantity;
}

class OptimizeResult {
  OptimizeResult.fromJson(Map<String, dynamic> j)
      : runId = j['run_id'] as String,
        itemCount = j['item_count'] as int,
        referenceTotal = _d(j['reference_total']),
        radiusM = j['radius_m'] as int,
        combosEvaluated = j['combos_evaluated'] as int,
        isPremium = j['is_premium'] as bool,
        items = _list(j['items'], OptItem.fromJson),
        stores = _list(j['stores'], Store.fromJson),
        scenarioA = Scenario.fromJson(Map<String, dynamic>.from(j['scenario_a'] as Map)),
        alternatives = _list(j['alternatives'], Scenario.fromJson),
        scenarioB = j['scenario_b'] == null ? null : Scenario.fromJson(Map<String, dynamic>.from(j['scenario_b'] as Map));
  final String runId;
  final int itemCount, radiusM, combosEvaluated;
  final double referenceTotal;
  final bool isPremium;
  final List<OptItem> items;
  final List<Store> stores;
  final Scenario scenarioA;
  final List<Scenario> alternatives;
  final Scenario? scenarioB;

  Store store(int id) => stores.firstWhere((s) => s.id == id);
  String itemLabel(String id) => items.firstWhere((i) => i.id == id, orElse: () => OptItem.fromJson({'id': id, 'label': '?', 'quantity': 1})).label;
}

class Candidate {
  Candidate.fromJson(Map<String, dynamic> j)
      : productId = j['product_id'] as int,
        name = j['name'] as String,
        score = _d(j['score']);
  final int productId;
  final String name;
  final double score;
}

class ReceiptLine {
  ReceiptLine.fromJson(Map<String, dynamic> j)
      : lineNo = j['line_no'] as int,
        rawText = j['raw_text'] as String,
        qty = _d(j['qty']),
        lineTotal = _d(j['line_total']),
        discount = _d(j['discount']),
        productId = j['product_id'] as int?,
        productName = j['product_name'] as String?,
        needsReview = j['needs_review'] as bool,
        candidates = _list(j['candidates'], Candidate.fromJson);
  final int lineNo;
  final String rawText;
  final double qty, lineTotal, discount;
  final int? productId;
  final String? productName;
  final bool needsReview;
  final List<Candidate> candidates;
}

class Receipt {
  Receipt.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        status = j['status'] as String,
        storeName = j['store_name'] as String? ?? '',
        totalPrinted = _dn(j['total_printed']),
        totalParsed = _dn(j['total_parsed']),
        totalsMatch = j['totals_match'] as bool? ?? false,
        purchasedAt = j['purchased_at'] as String?,
        lines = _list(j['lines'], ReceiptLine.fromJson);
  final String id, status, storeName;
  final double? totalPrinted, totalParsed;
  final bool totalsMatch;
  final String? purchasedAt;
  final List<ReceiptLine> lines;
}

class ConfirmResult {
  ConfirmResult.fromJson(Map<String, dynamic> j)
      : creditsAwarded = j['credits_awarded'] as int,
        streakBonus = j['streak_bonus'] as int,
        streakWeeks = j['streak_weeks'] as int,
        creditsTotal = j['credits_total'] as int,
        pricesSubmitted = j['prices_submitted'] as int,
        savingConfirmed = _dn(j['saving_confirmed']);
  final int creditsAwarded, streakBonus, streakWeeks, creditsTotal, pricesSubmitted;
  final double? savingConfirmed;
}

class MonthSaving {
  MonthSaving.fromJson(Map<String, dynamic> j)
      : year = j['year'] as int,
        month = j['month'] as int,
        saving = _d(j['saving']);
  final int year, month;
  final double saving;
}

class Savings {
  Savings.fromJson(Map<String, dynamic> j)
      : monthSaving = _d(j['month_saving']),
        yearSaving = _d(j['year_saving']),
        yearCount = j['year_count'] as int,
        months = _list(j['months'], MonthSaving.fromJson);
  final double monthSaving, yearSaving;
  final int yearCount;
  final List<MonthSaving> months;
}
