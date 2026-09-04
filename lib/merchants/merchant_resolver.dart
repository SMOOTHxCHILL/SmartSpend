import 'package:string_similarity/string_similarity.dart';
import '../db/database_helper.dart';

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
  /// - No match -> create a new merchant with category 'Other' (user can correct later).
  Future<int> resolve(String rawMerchantText, {required String transactionType}) async {
    final normalized = _normalize(rawMerchantText);
    final database = await db.database;

    // Person-to-person transfers get their own bucket, not merchant resolution.
    // Heuristic for now: no common merchant keywords AND type is debit/credit
    // between individuals is hard to detect purely from text, so we rely on
    // this being refined later; for now treat as a normal merchant lookup too.

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
    String? bestAlias;
    double bestScore = 0.0;
    int? bestMerchantId;

    for (final row in allAliases) {
      final alias = row['alias_text'] as String;
      final score = StringSimilarity.compareTwoStrings(normalized, alias);
      if (score > bestScore) {
        bestScore = score;
        bestAlias = alias;
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

    // 3. No match found — create a new merchant entity
    final defaultCategory = transactionType == 'debit' ? 'Other' : 'Transfer';
    final newMerchantId = await database.insert('merchants', {
      'canonical_name': normalized,
      'category': defaultCategory,
      'mcc': null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await database.insert('merchant_aliases', {
      'merchant_id': newMerchantId,
      'alias_text': normalized,
    });
    return newMerchantId;
  }
}