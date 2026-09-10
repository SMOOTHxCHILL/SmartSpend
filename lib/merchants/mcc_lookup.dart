/// A small curated seed of MCC (Merchant Category Code) mappings for common
/// Indian merchants, keyed by a keyword found in the normalized merchant
/// name. This is intentionally not the full ISO 18245 standard — just
/// enough real-world coverage to bootstrap category guesses for new
/// merchants and backfill existing ones. Expand this list as you notice
/// merchants that should be mapping but aren't.
class MccMatch {
  final String mcc;
  final String category;

  const MccMatch(this.mcc, this.category);
}

class _MccRule {
  final String keyword;
  final String mcc;
  final String category;

  const _MccRule(this.keyword, this.mcc, this.category);
}

class MccLookup {
  static const List<_MccRule> _rules = [
    // Food & Dining (5812 — Eating Places, Restaurants)
    _MccRule('SWIGGY', '5812', 'Food & Dining'),
    _MccRule('ZOMATO', '5812', 'Food & Dining'),
    _MccRule('DOMINO', '5812', 'Food & Dining'),
    _MccRule('MCDONALD', '5812', 'Food & Dining'),
    _MccRule('STARBUCKS', '5812', 'Food & Dining'),
    _MccRule('KFC', '5812', 'Food & Dining'),

    // Groceries (5411 — Grocery Stores, Supermarkets)
    _MccRule('BIGBASKET', '5411', 'Groceries'),
    _MccRule('BLINKIT', '5411', 'Groceries'),
    _MccRule('ZEPTO', '5411', 'Groceries'),
    _MccRule('DMART', '5411', 'Groceries'),
    _MccRule('GROFERS', '5411', 'Groceries'),

    // Shopping (5399/5311 — Department & Variety Stores)
    _MccRule('AMAZON', '5311', 'Shopping'),
    _MccRule('FLIPKART', '5311', 'Shopping'),
    _MccRule('MYNTRA', '5651', 'Shopping'),
    _MccRule('AJIO', '5651', 'Shopping'),
    _MccRule('NYKAA', '5977', 'Shopping'),

    // Transport (4121 — Taxicabs, Limousines)
    _MccRule('UBER', '4121', 'Transport'),
    _MccRule('OLACABS', '4121', 'Transport'),
    _MccRule('RAPIDO', '4121', 'Transport'),

    // Bills & Utilities (4900/4899 — Utilities)
    _MccRule('AIRTEL', '4899', 'Bills & Utilities'),
    _MccRule('JIO', '4899', 'Bills & Utilities'),
    _MccRule('VODAFONE', '4899', 'Bills & Utilities'),
    _MccRule('BESCOM', '4900', 'Bills & Utilities'),
    _MccRule('TATAPOWER', '4900', 'Bills & Utilities'),

    // Entertainment (5815/7832 — Digital Goods, Motion Picture)
    _MccRule('NETFLIX', '5815', 'Entertainment'),
    _MccRule('HOTSTAR', '5815', 'Entertainment'),
    _MccRule('SPOTIFY', '5815', 'Entertainment'),
    _MccRule('BOOKMYSHOW', '7832', 'Entertainment'),

    // Health (8011/8062/5912 — Medical, Pharmacy)
    _MccRule('APOLLO', '8062', 'Health'),
    _MccRule('PHARMEASY', '5912', 'Health'),
    _MccRule('PRACTO', '8011', 'Health'),
    _MccRule('1MG', '5912', 'Health'),

    // Investment (6211 — Securities Brokers/Dealers)
    _MccRule('ZERODHA', '6211', 'Investment'),
    _MccRule('GROWW', '6211', 'Investment'),
    _MccRule('UPSTOX', '6211', 'Investment'),
  ];

  /// Looks up an MCC/category guess from a normalized (uppercase) merchant
  /// name using substring matching against the keyword list.
  static MccMatch? lookup(String normalizedMerchantName) {
    for (final rule in _rules) {
      if (normalizedMerchantName.contains(rule.keyword)) {
        return MccMatch(rule.mcc, rule.category);
      }
    }
    return null;
  }
}