import 'package:flutter/foundation.dart';

import '../models/parsed_transaction.dart';
import 'parser_interface.dart';

class HdfcParser implements ParserInterface {
  @override
  String get bankName => 'HDFC';

  @override
  bool matchesSender(String sender) {
    return sender.toUpperCase().contains('HDFCBK');
  }

  // ---------------------------------------------------------------------------
  // HDFC DEBIT SMS
  //
  // Example:
  //
  // Sent Rs.832.00 From HDFC Bank A/C *7124 To SWIGGY INSTAMART
  // On 09/07/26 Ref 619049401286
  // ---------------------------------------------------------------------------

  static final _debitPattern = RegExp(
    r'Sent Rs\.?\s*([\d,]+\.?\d*)\s*'
    r'From HDFC Bank A/C\s*\*?(\d+)\s*'
    r'To\s*(.+?)\s*'
    r'On\s*(\d{2}[/\-]\d{2}[/\-]\d{2,4})',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // HDFC CREDIT SMS
  //
  // Example:
  //
  // Credit Alert! Rs.1880.00 credited to HDFC Bank A/c XX7124
  // on 21-12-25 from VPA harineeanandh@oksbi
  // ---------------------------------------------------------------------------

  static final _creditPattern = RegExp(
    r'Rs\.?\s*([\d,]+\.?\d*)\s*'
    r'credited to HDFC Bank A/c\s*X{0,2}(\d+)\s*'
    r'on\s*(\d{2}[/\-]\d{2}[/\-]\d{2,4})\s*'
    r'from\s*VPA\s*([\w\.\-@]+)',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // HDFC BALANCE ALERT
  //
  // Example:
  //
  // Available Bal in HDFC Bank A/c XX7124 as on yesterday...
  //
  // This is not a transaction.
  // ---------------------------------------------------------------------------

  static final _balanceAlertPattern = RegExp(
    r'Available Bal',
    caseSensitive: false,
  );

  @override
  ParsedTransaction? tryParse({
    required int rawSmsId,
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    // Collapse newlines and repeated whitespace.
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Ignore balance alerts.
    if (_balanceAlertPattern.hasMatch(normalized)) {
      return null;
    }

    // -------------------------------------------------------------------------
    // DEBIT
    // -------------------------------------------------------------------------

    final debitMatch = _debitPattern.firstMatch(normalized);

    if (debitMatch != null) {
      final amount = _parseAmount(debitMatch.group(1));

      if (amount == null) {
        return null;
      }

      final rawDate = debitMatch.group(4);

      final transactionDate = _parseDate(
        rawDate,
        receivedAt,
      );

      debugPrint('===== HDFC DEBIT DEBUG =====');
      debugPrint('SMS: $normalized');
      debugPrint('SMS RECEIVED AT: $receivedAt');
      debugPrint('RAW DATE: $rawDate');
      debugPrint('PARSED DATE: $transactionDate');
      debugPrint('============================');

      return ParsedTransaction(
        bank: bankName,
        amount: amount,
        type: 'debit',
        rawMerchant: debitMatch.group(3)?.trim() ?? '',
        transactionDate: transactionDate,
        confidence: transactionDate == null ? 0.80 : 0.95,
        rawSmsId: rawSmsId,
      );
    }

    // -------------------------------------------------------------------------
    // CREDIT
    // -------------------------------------------------------------------------

    final creditMatch = _creditPattern.firstMatch(normalized);

    if (creditMatch != null) {
      final amount = _parseAmount(creditMatch.group(1));

      if (amount == null) {
        return null;
      }

      final rawDate = creditMatch.group(3);

      final transactionDate = _parseDate(
        rawDate,
        receivedAt,
      );

      debugPrint('===== HDFC CREDIT DEBUG =====');
      debugPrint('SMS: $normalized');
      debugPrint('SMS RECEIVED AT: $receivedAt');
      debugPrint('RAW DATE: $rawDate');
      debugPrint('PARSED DATE: $transactionDate');
      debugPrint('=============================');

      return ParsedTransaction(
        bank: bankName,
        amount: amount,
        type: 'credit',
        rawMerchant: creditMatch.group(4)?.trim() ?? '',
        transactionDate: transactionDate,
        confidence: transactionDate == null ? 0.80 : 0.95,
        rawSmsId: rawSmsId,
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // AMOUNT
  // ---------------------------------------------------------------------------

  double? _parseAmount(String? raw) {
    if (raw == null) {
      return null;
    }

    return double.tryParse(
      raw.replaceAll(',', '').trim(),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE
  //
  // We use the SMS received timestamp to resolve the year.
  //
  // Example:
  //
  // SMS:
  //   On 31/12/26
  //
  // SMS received:
  //   31/12/2025
  //
  // Because the SMS itself was received in 2025, the transaction is
  // interpreted as:
  //
  //   31/12/2025
  //
  // This is more reliable than simply assuming 2000 + twoDigitYear.
  //
  // For normal SMS:
  //
  //   03/01/26 + received in 2026 -> 03/01/2026
  //
  //   26/12/25 + received in 2025 -> 26/12/2025
  //
  // ---------------------------------------------------------------------------

  DateTime? _parseDate(
    String? raw,
    DateTime receivedAt,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final parts = raw.trim().split(
      RegExp(r'[/\-]'),
    );

    if (parts.length != 3) {
      debugPrint(
        'HDFC DATE ERROR: Could not split "$raw"',
      );
      return null;
    }

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final yearValue = int.tryParse(parts[2]);

    if (day == null ||
        month == null ||
        yearValue == null) {
      debugPrint(
        'HDFC DATE ERROR: Invalid date "$raw"',
      );
      return null;
    }

    if (month < 1 || month > 12) {
      debugPrint(
        'HDFC DATE ERROR: Invalid month in "$raw"',
      );
      return null;
    }

    if (day < 1 || day > 31) {
      debugPrint(
        'HDFC DATE ERROR: Invalid day in "$raw"',
      );
      return null;
    }

    // -------------------------------------------------------------------------
    // Four-digit year.
    //
    // If HDFC gives us 2025 or 2026 explicitly, trust it.
    // -------------------------------------------------------------------------

    if (yearValue >= 1000) {
      final parsed = DateTime(
        yearValue,
        month,
        day,
      );

      if (!_isValidCalendarDate(
        parsed,
        yearValue,
        month,
        day,
      )) {
        return null;
      }

      return parsed;
    }

    // -------------------------------------------------------------------------
    // Two-digit year.
    //
    // First determine the year surrounding the SMS received date.
    //
    // We use receivedAt.year as the primary source of truth.
    // -------------------------------------------------------------------------

    int resolvedYear = receivedAt.year;

    DateTime candidate = DateTime(
      resolvedYear,
      month,
      day,
    );

    if (!_isValidCalendarDate(
      candidate,
      resolvedYear,
      month,
      day,
    )) {
      return null;
    }

    // -------------------------------------------------------------------------
    // Compare the two-digit year with the received year.
    //
    // Example:
    //
    // receivedAt = 2025
    // SMS date   = 31/12/26
    //
    // The SMS date has 26, but the SMS itself was received in 2025.
    //
    // For the historical HDFC data we're dealing with, this means the
    // bank SMS is carrying an incorrect/shifted year and we should use
    // receivedAt.year.
    //
    // However, if the two-digit year explicitly corresponds to the
    // received year, we keep that year as well.
    // -------------------------------------------------------------------------

    final twoDigitReceivedYear = receivedAt.year % 100;

    if (yearValue == twoDigitReceivedYear) {
      resolvedYear = receivedAt.year;
    } else {
      // The SMS's displayed two-digit year does not agree with the
      // year in which the SMS was actually received.
      //
      // Use the received year because it represents the historical
      // timestamp of the bank notification.
      resolvedYear = receivedAt.year;
    }

    final parsed = DateTime(
      resolvedYear,
      month,
      day,
    );

    if (!_isValidCalendarDate(
      parsed,
      resolvedYear,
      month,
      day,
    )) {
      return null;
    }

    if (yearValue != twoDigitReceivedYear) {
      debugPrint(
        'HDFC DATE YEAR CORRECTION: '
        '"$raw" received at $receivedAt. '
        'Using SMS received year $resolvedYear.',
      );
    }

    return parsed;
  }

  // ---------------------------------------------------------------------------
  // DATE VALIDATION
  // ---------------------------------------------------------------------------

  bool _isValidCalendarDate(
    DateTime date,
    int expectedYear,
    int expectedMonth,
    int expectedDay,
  ) {
    return date.year == expectedYear &&
        date.month == expectedMonth &&
        date.day == expectedDay;
  }
}