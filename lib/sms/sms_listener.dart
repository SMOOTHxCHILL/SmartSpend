import 'package:another_telephony/telephony.dart';

import '../db/database_helper.dart';
import '../models/raw_sms.dart';

class SmsListenerService {
  final Telephony telephony = Telephony.instance;
  final DatabaseHelper dbHelper = DatabaseHelper();

  Future<bool> requestPermissions() async {
    final granted = await telephony.requestPhoneAndSmsPermissions;
    return granted ?? false;
  }

  void startListening() {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        final receivedAt = message.date != null
            ? DateTime.fromMillisecondsSinceEpoch(
                message.date!,
              )
            : DateTime.now();

        final raw = RawSms(
          sender: message.address ?? 'unknown',
          body: message.body ?? '',
          receivedAt: receivedAt,
        );

        await dbHelper.insertRawSms(raw);
      },
      listenInBackground: false,
    );
  }

  /// Imports existing SMS messages from the device inbox.
  ///
  /// Android provides the actual SMS timestamp through SmsColumn.DATE,
  /// so historical messages retain their original received date.
  Future<void> importExistingInbox() async {
    final messages = await telephony.getInboxSms(
      columns: [
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
      ],
    );

    for (final message in messages) {
      final raw = RawSms(
        sender: message.address ?? 'unknown',
        body: message.body ?? '',
        receivedAt: message.date != null
            ? DateTime.fromMillisecondsSinceEpoch(
                message.date!,
              )
            : DateTime.now(),
      );

      await dbHelper.insertRawSms(raw);
    }
  }
}