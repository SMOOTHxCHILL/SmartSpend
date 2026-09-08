import '../models/parsed_transaction.dart';

abstract class ParserInterface {
  /// A short name identifying the bank this parser handles.
  String get bankName;

  /// Quick check: does this SMS look like it's from this bank at all?
  bool matchesSender(String sender);

  /// Attempt to parse the SMS body.
  ///
  /// [receivedAt] is the timestamp of the SMS itself. It is especially
  /// important when the bank SMS contains an ambiguous two-digit year.
  ParsedTransaction? tryParse({
    required int rawSmsId,
    required String sender,
    required String body,
    required DateTime receivedAt,
  });
}