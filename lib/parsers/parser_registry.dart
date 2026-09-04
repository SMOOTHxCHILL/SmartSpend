import '../models/parsed_transaction.dart';
import 'parser_interface.dart';
import 'hdfc_parser.dart';

class ParserRegistry {
  final List<ParserInterface> parsers = [
    HdfcParser(),
    // add more bank parsers here as you build them
  ];

  ParsedTransaction? parse({
    required int rawSmsId,
    required String sender,
    required String body,
  }) {
    for (final parser in parsers) {
      if (parser.matchesSender(sender)) {
        final result = parser.tryParse(
          rawSmsId: rawSmsId,
          sender: sender,
          body: body,
        );
        if (result != null) return result;
      }
    }
    return null; // no parser matched — this is either non-bank SMS,
                 // or a bank we don't support yet, or a format drift case
  }
}