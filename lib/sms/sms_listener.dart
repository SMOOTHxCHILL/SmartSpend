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
        final raw = RawSms(
          sender: message.address ?? 'unknown',
          body: message.body ?? '',
          receivedAt: DateTime.now(),
        );
        await dbHelper.insertRawSms(raw);
      },
      listenInBackground: false, // keep it foreground-only for now
    );
  }

  // Useful for testing: pull existing inbox messages instead of waiting for a live SMS
  Future<void> importExistingInbox() async {
    final messages = await telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    );
    for (final m in messages) {
      final raw = RawSms(
        sender: m.address ?? 'unknown',
        body: m.body ?? '',
        receivedAt: m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : DateTime.now(),
      );
      await DatabaseHelper().insertRawSms(raw);
    }
  }
}