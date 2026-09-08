class RawSms {
  final int? id;
  final String sender;
  final String body;
  final DateTime receivedAt;

  RawSms({
    this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sender': sender,
      'body': body,
      'received_at': receivedAt.millisecondsSinceEpoch,
    };
  }

  factory RawSms.fromMap(Map<String, dynamic> map) {
    return RawSms(
      id: map['id'] as int?,
      sender: map['sender'] as String,
      body: map['body'] as String,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        map['received_at'] as int,
      ),
    );
  }
}