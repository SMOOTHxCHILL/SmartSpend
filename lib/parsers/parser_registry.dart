import '../models/parsed_transaction.dart';
import 'parser_interface.dart';
import 'hdfc_parser.dart';

class ParserRegistry {
  final List<ParserInterface> parsers = [
    HdfcParser(),
    // Add more bank parsers here as you build them.
  ];

  ParsedTransaction? parse({
    required int rawSmsId,
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    for (final parser in parsers) {
      if (parser.matchesSender(sender)) {
        final result = parser.tryParse(
          rawSmsId: rawSmsId,
          sender: sender,
          body: body,
          receivedAt: receivedAt,
        );

        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }
}