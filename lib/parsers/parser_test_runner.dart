import '../db/database_helper.dart';
import 'parser_registry.dart';
import '../merchants/merchant_resolver.dart';
import '../validation/transaction_validator.dart';

class ParserTestRunner {
  final ParserRegistry registry = ParserRegistry();
  final TransactionValidator validator = TransactionValidator();

  /// Runs all raw SMS messages through the parser registry and validation.
  /// Does not write anything to the database.
  Future<ParserTestResult> run() async {
    final rawMessages = await DatabaseHelper().getAllRawSms();

    final matched = <String>[];
    final unmatched = <String>[];
    final invalid = <String>[];
    final needsReview = <String>[];

    for (final sms in rawMessages) {
      final result = registry.parse(
        rawSmsId: sms.id ?? -1,
        sender: sms.sender,
        body: sms.body,
      );

      if (result == null) {
        unmatched.add('[${sms.sender}] ${sms.body}');
        continue;
      }

      final validation = validator.validate(result);

      if (validation.status == ValidationStatus.invalid) {
        invalid.add(
          '[${result.bank}] Rs.${result.amount} — '
          '${result.rawMerchant} '
          '(${validation.reasons.join(', ')})',
        );
        continue;
      }

      if (validation.status == ValidationStatus.needsReview) {
        needsReview.add(
          '[${result.bank}] Rs.${result.amount} — '
          '${result.rawMerchant} '
          '(${validation.reasons.join(', ')})',
        );
      }

      matched.add(
        '[${result.bank}] ${result.type.toUpperCase()} '
        'Rs.${result.amount} — ${result.rawMerchant} '
        '(${result.transactionDate?.toIso8601String().split("T").first ?? "no date"})',
      );
    }

    return ParserTestResult(
      total: rawMessages.length,
      matched: matched,
      unmatched: unmatched,
      invalid: invalid,
      needsReview: needsReview,
    );
  }

  /// Parses, validates and persists transactions.
  ///
  /// Invalid transactions are not stored.
  /// Transactions requiring review are currently stored, but counted
  /// separately so we can handle them properly in a later iteration.
  Future<PersistResult> runAndPersist() async {
    final rawMessages = await DatabaseHelper().getAllRawSms();

    int inserted = 0;
    int duplicates = 0;
    int invalid = 0;
    int needsReview = 0;

    for (final sms in rawMessages) {
      final result = registry.parse(
        rawSmsId: sms.id ?? -1,
        sender: sms.sender,
        body: sms.body,
      );

      if (result == null) {
        continue;
      }

      final validation = validator.validate(result);

      // Do not persist structurally invalid transactions.
      if (validation.status == ValidationStatus.invalid) {
        invalid++;
        continue;
      }

      // Keep track of transactions that have low parser confidence.
      if (validation.status == ValidationStatus.needsReview) {
        needsReview++;
      }

      final success =
          await DatabaseHelper().insertParsedTransaction(result);

      if (success) {
        inserted++;
      } else {
        duplicates++;
      }
    }

    return PersistResult(
      inserted: inserted,
      duplicates: duplicates,
      invalid: invalid,
      needsReview: needsReview,
    );
  }

  /// Resolves merchants for existing parsed transactions that do not
  /// already have a merchant_id.
  Future<int> resolveMerchantsForExisting() async {
    final database = await DatabaseHelper().database;
    final resolver = MerchantResolver();

    final rows = await database.query(
      'parsed_transactions',
      where: 'merchant_id IS NULL',
    );

    int resolved = 0;

    for (final row in rows) {
      final merchantId = await resolver.resolve(
        row['raw_merchant'] as String,
        transactionType: row['type'] as String,
      );

      await database.update(
        'parsed_transactions',
        {'merchant_id': merchantId},
        where: 'id = ?',
        whereArgs: [row['id']],
      );

      resolved++;
    }

    return resolved;
  }
}

/// Result returned by the parser test operation.
class ParserTestResult {
  final int total;
  final List<String> matched;
  final List<String> unmatched;
  final List<String> invalid;
  final List<String> needsReview;

  const ParserTestResult({
    required this.total,
    required this.matched,
    required this.unmatched,
    this.invalid = const [],
    this.needsReview = const [],
  });
}

/// Result returned when parsed transactions are persisted.
class PersistResult {
  final int inserted;
  final int duplicates;
  final int invalid;
  final int needsReview;

  const PersistResult({
    required this.inserted,
    required this.duplicates,
    required this.invalid,
    required this.needsReview,
  });
}