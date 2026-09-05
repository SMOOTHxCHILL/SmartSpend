import '../models/parsed_transaction.dart';

enum ValidationStatus {
  valid,
  needsReview,
  invalid,
}

class ValidationResult {
  final ValidationStatus status;
  final List<String> reasons;

  const ValidationResult({
    required this.status,
    this.reasons = const [],
  });

  bool get isValid => status == ValidationStatus.valid;
}

class TransactionValidator {
  ValidationResult validate(ParsedTransaction transaction) {
    final errors = <String>[];
    final warnings = <String>[];

    // Amount must be positive.
    if (transaction.amount <= 0) {
      errors.add('INVALID_AMOUNT');
    }

    // Transaction type must be debit or credit.
    if (transaction.type != 'debit' && transaction.type != 'credit') {
      errors.add('INVALID_TRANSACTION_TYPE');
    }

    // Merchant should not be empty.
    if (transaction.rawMerchant.trim().isEmpty) {
      errors.add('MISSING_MERCHANT');
    }

    // A transaction should have a date.
    if (transaction.transactionDate == null) {
      errors.add('MISSING_TRANSACTION_DATE');
    }

    // Parser confidence should be between 0 and 1.
    if (transaction.confidence < 0 || transaction.confidence > 1) {
      errors.add('INVALID_CONFIDENCE');
    }

    // Low confidence isn't necessarily invalid.
    // It means we should eventually ask the user to review it.
    if (transaction.confidence < 0.80) {
      warnings.add('LOW_PARSE_CONFIDENCE');
    }

    // Hard validation failure.
    if (errors.isNotEmpty) {
      return ValidationResult(
        status: ValidationStatus.invalid,
        reasons: errors,
      );
    }

    // Transaction is structurally valid, but may need review.
    if (warnings.isNotEmpty) {
      return ValidationResult(
        status: ValidationStatus.needsReview,
        reasons: warnings,
      );
    }

    return const ValidationResult(
      status: ValidationStatus.valid,
    );
  }
}