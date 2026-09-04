import '../db/database_helper.dart';
import 'parser_registry.dart';
import '../merchants/merchant_resolver.dart';

class ParserTestRunner {
  final ParserRegistry registry = ParserRegistry();

  /// Runs all raw SMS through the parser registry and returns a summary.
  /// Doesn't write anything to the database — this is read-only, for eyeballing results.
  Future<ParserTestResult> run() async {
    final rawMessages = await DatabaseHelper().getAllRawSms();

    final matched = <String>[];
    final unmatched = <String>[];

    for (final sms in rawMessages) {
      final result = registry.parse(
        rawSmsId: sms.id ?? -1,
        sender: sms.sender,
        body: sms.body,
      );

      if (result != null) {
        matched.add(
          '[${result.bank}] ${result.type.toUpperCase()} '
          'Rs.${result.amount} — ${result.rawMerchant} '
          '(${result.transactionDate?.toIso8601String().split("T").first ?? "no date"})',
        );
      } else {
        // Only flag as "unmatched" if it looks like it's even from a bank sender.
        // Random SMS from friends/OTPs/promos are expected to not match — that's fine, not a bug.
        unmatched.add('[${sms.sender}] ${sms.body}');
      }
    }

    return ParserTestResult(
      total: rawMessages.length,
      matched: matched,
      unmatched: unmatched,
    );
  }

  /// Runs the parser and WRITES matched results to parsed_transactions.
  /// Returns counts of inserted vs skipped (duplicate) records.
  Future<(int inserted, int duplicates)> runAndPersist() async {
    final rawMessages = await DatabaseHelper().getAllRawSms();
    int inserted = 0;
    int duplicates = 0;

    for (final sms in rawMessages) {
      final result = registry.parse(
        rawSmsId: sms.id ?? -1,
        sender: sms.sender,
        body: sms.body,
      );
      if (result != null) {
        final success = await DatabaseHelper().insertParsedTransaction(result);
        if (success) {
          inserted++;
        } else {
          duplicates++;
        }
      }
    }

    return (inserted, duplicates);
  }

  /// Runs merchant resolution over all parsed_transactions that don't yet
  /// have a merchant_id, and updates them in place.
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

class ParserTestResult {
  final int total;
  final List<String> matched;
  final List<String> unmatched;

  ParserTestResult({
    required this.total,
    required this.matched,
    required this.unmatched,
  });
}