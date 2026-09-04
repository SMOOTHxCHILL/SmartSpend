class ParsedTransaction {
  final String bank;
  final double amount;
  final String type; // 'debit' or 'credit'
  final String rawMerchant;
  final DateTime? transactionDate;
  final double confidence;
  final int rawSmsId;

  ParsedTransaction({
    required this.bank,
    required this.amount,
    required this.type,
    required this.rawMerchant,
    this.transactionDate,
    required this.confidence,
    required this.rawSmsId,
  });

  Map<String, dynamic> toMap() {
    return {
      'bank': bank,
      'amount': amount,
      'type': type,
      'raw_merchant': rawMerchant,
      'transaction_date': transactionDate?.millisecondsSinceEpoch,
      'confidence': confidence,
      'raw_sms_id': rawSmsId,
    };
  }
}