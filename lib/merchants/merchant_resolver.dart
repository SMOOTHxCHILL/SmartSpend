import 'package:string_similarity/string_similarity.dart';
import '../db/database_helper.dart';
import '../ml/ml_categorizer.dart';
import 'mcc_lookup.dart';

class MerchantResolver {
  final DatabaseHelper db = DatabaseHelper();

  /// Cleans up raw merchant text before matching:
  /// strips trailing store codes, extra spaces, common noise tokens.
  String _normalize(String raw) {
    var s = raw.toUpperCase().trim();
    s = s.replaceAll(RegExp(r'[\*]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Resolves a raw merchant string to a merchant_id.
  /// - Exact alias match -> return existing merchant.
  /// - Fuzzy match above threshold -> link as new alias to existing merchant.
  /// - No match -> create a new merchant. Category is resolved in order:
  ///     1. MCC seed lookup (keyword match, high confidence)
  ///     2. On-device ML categorizer fallback (learned from your corrections)
  ///     3. 'Other' (debit) / 'Transfer' (credit) as last resort
  ///
  /// Whichever path assigns the category, category_source stays 'default' --
  /// only a manual correction through the UI ever sets 'user_corrected'.
  /// This keeps ML-guessed and MCC-guessed categories fully overridable and
  /// keeps them out of future training data until a human confirms them.
  Future<int> resolve(
    String rawMerchantText, {
    required String transactionType,
    double? amount,
    DateTime? transactionDate,
  }) async {
    final normalized = _normalize(rawMerchantText);
    final database = await db.database;

    // 1. Exact alias match
    final exactRows = await database.query(
      'merchant_aliases',
      where: 'alias_text = ?',
      whereArgs: [normalized],
    );
    if (exactRows.isNotEmpty) {
      return exactRows.first['merchant_id'] as int;
    }

    // 2. Fuzzy match against existing aliases
    final allAliases = await database.query('merchant_aliases');
    double bestScore = 0.0;
    int? bestMerchantId;

    for (final row in allAliases) {
      final alias = row['alias_text'] as String;
      final score = StringSimilarity.compareTwoStrings(normalized, alias);
      if (score > bestScore) {
        bestScore = score;
        bestMerchantId = row['merchant_id'] as int;
      }
    }

    const threshold = 0.7; // tuned starting point; adjust based on real results
    if (bestScore >= threshold && bestMerchantId != null) {
      // Link this new variant as an alias to the existing merchant
      await database.insert('merchant_aliases', {
        'merchant_id': bestMerchantId,
        'alias_text': normalized,
      });
      return bestMerchantId;
    }

    // 3. No match found — create a new merchant entity.
    String? mcc;
    String defaultCategory;

    if (transactionType != 'debit') {
      // Credits / transfers stay 'Transfer' regardless of MCC/ML guesses --
      // neither applies to person-to-person transfer detection.
      defaultCategory = 'Transfer';
    } else {
      final mccMatch = MccLookup.lookup(normalized);

      if (mccMatch != null) {
        mcc = mccMatch.mcc;
        defaultCategory = mccMatch.category;
      } else {
        // MCC lookup missed -- try the on-device ML fallback before
        // giving up to 'Other'. Requires amount + transactionDate; if
        // either is missing (or the model isn't loaded), falls through.
        String? mlGuess;
        if (amount != null && transactionDate != null) {
          mlGuess = await MlCategorizer().predict(
            merchantName: normalized,
            amount: amount,
            transactionDate: transactionDate,
            isDebit: true,
          );
        }
        defaultCategory = mlGuess ?? 'Other';
      }
    }

    final newMerchantId = await database.insert('merchants', {
      'canonical_name': normalized,
      'category': defaultCategory,
      'category_source': 'default',
      'mcc': mcc,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await database.insert('merchant_aliases', {
      'merchant_id': newMerchantId,
      'alias_text': normalized,
    });
    return newMerchantId;
  }

  /// One-time backfill for merchants created before the MCC seed table
  /// existed (or before their keyword was added to it). Only touches
  /// merchants still at category_source = 'default' — anything the user
  /// has already corrected is left alone. MCC-only (doesn't invoke the ML
  /// model, since this runs in a tight loop over potentially many merchants
  /// and ONNX inference per-row would be needlessly slow for a backfill --
  /// the ML fallback is for new merchants going forward, via resolve()).
  Future<int> backfillMccForExisting() async {
    final database = await db.database;

    final rows = await database.query(
      'merchants',
      where: "mcc IS NULL AND category_source = 'default'",
    );

    int updated = 0;

    for (final row in rows) {
      final canonicalName = row['canonical_name'] as String;
      final match = MccLookup.lookup(canonicalName);

      if (match == null) continue;

      await database.update(
        'merchants',
        {
          'mcc': match.mcc,
          'category': match.category,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: "id = ? AND category_source = 'default'",
        whereArgs: [row['id']],
      );

      updated++;
    }

    return updated;
  }
}
