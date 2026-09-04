import '../models/parsed_transaction.dart';

abstract class ParserInterface {
  /// A short name identifying the bank this parser handles
  String get bankName;

  /// Quick check: does this SMS look like it's from this bank at all?
  /// (usually based on sender ID pattern, e.g. "HDFCBK", "VM-HDFCBK")
  bool matchesSender(String sender);

  /// Attempt to parse the SMS body. Returns null if the body doesn't
  /// match this bank's known transaction templates.
  ParsedTransaction? tryParse({
    required int rawSmsId,
    required String sender,
    required String body,
  });
}