import '../models/parsed_transaction.dart';
import 'parser_interface.dart';

class HdfcParser implements ParserInterface {
  @override
  String get bankName => 'HDFC';

  @override
  bool matchesSender(String sender) {
    return sender.toUpperCase().contains('HDFCBK');
  }

  // Debit: "Sent Rs.832.00 From HDFC Bank A/C *7124 To SWIGGY INSTAMART On 09/07/26 Ref 619049401286"
  static final _debitPattern = RegExp(
    r'Sent Rs\.?\s*([\d,]+\.?\d*)\s*From HDFC Bank A/C\s*\*?(\d+)\s*To\s*(.+?)\s*On\s*(\d{2}[/\-]\d{2}[/\-]\d{2})',
    caseSensitive: false,
  );

  // Credit: "Rs.722.00 credited to HDFC Bank A/c XX7124 on 16-06-26 from VPA harineeanandh-1@okhdfcbank (UPI 124823352879)"
  static final _creditPattern = RegExp(
    r'Rs\.?\s*([\d,]+\.?\d*)\s*credited to HDFC Bank A/c\s*X{0,2}(\d+)\s*on\s*(\d{2}[/\-]\d{2}[/\-]\d{2})\s*from\s*VPA\s*([\w\.\-@]+)',
    caseSensitive: false,
  );

  // Balance alert: "Available Bal in HDFC Bank A/c XX7124 as on yesterday..."
  // Not a transaction — must be explicitly excluded, not left to fall through
  // as an "unmatched" record (which would wrongly suggest a missing template).
  static final _balanceAlertPattern = RegExp(
    r'Available Bal',
    caseSensitive: false,
  );

  @override
  ParsedTransaction? tryParse({
    required int rawSmsId,
    required String sender,
    required String body,
  }) {
    // Normalize: collapse newlines/extra whitespace into single spaces
    // so the patterns above don't need to account for line breaks.
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (_balanceAlertPattern.hasMatch(normalized)) {
      return null; // known non-transaction type, intentionally skipped
    }

    final debitMatch = _debitPattern.firstMatch(normalized);
    if (debitMatch != null) {
      final amount = _parseAmount(debitMatch.group(1));
      if (amount == null) return null;
      return ParsedTransaction(
        bank: bankName,
        amount: amount,
        type: 'debit',
        rawMerchant: debitMatch.group(3)?.trim() ?? '',
        transactionDate: _parseDate(debitMatch.group(4)),
        confidence: 0.95,
        rawSmsId: rawSmsId,
      );
    }

    final creditMatch = _creditPattern.firstMatch(normalized);
    if (creditMatch != null) {
      final amount = _parseAmount(creditMatch.group(1));
      if (amount == null) return null;
      return ParsedTransaction(
        bank: bankName,
        amount: amount,
        type: 'credit',
        rawMerchant: creditMatch.group(4)?.trim() ?? '', // VPA as merchant for now
        transactionDate: _parseDate(creditMatch.group(3)),
        confidence: 0.95,
        rawSmsId: rawSmsId,
      );
    }

    return null; // genuinely unmatched — new format or different message type
  }

  double? _parseAmount(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(',', ''));
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(RegExp(r'[/\-]'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(2000 + year, month, day);
  }
}