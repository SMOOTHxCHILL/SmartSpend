import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../db/database_helper.dart';

/// Uploads this phone's parsed transactions to the logged-in account,
/// through the web companion's /api/sync route.
///
/// Every sync sends all local transactions. That is safe to repeat: the
/// server matches rows on the SMS hash, so nothing is duplicated, and
/// only new or re-categorised rows are written.
///
/// Raw SMS bodies are never uploaded — only the parsed fields.
class CloudSync {
  CloudSync._();
  static final CloudSync instance = CloudSync._();

  static const _batchSize = 500;

  /// Shown by the dashboard (spinner / last result).
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus.idle());

  bool get isRunning => status.value.running;

  Future<SyncResult> syncAll() async {
    if (isRunning) return SyncResult.empty;
    status.value = const SyncStatus.running();

    try {
      final result = await _sync();
      status.value = SyncStatus.done(result);
      return result;
    } catch (e) {
      status.value = SyncStatus.failed(e.toString());
      rethrow;
    }
  }

  Future<String> _accessToken() async {
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) throw const SyncException('Log in to sync.');
    if (session.isExpired) {
      session = (await auth.refreshSession()).session;
      if (session == null) throw const SyncException('Session expired. Log in again.');
    }
    return session.accessToken;
  }

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final db = await DatabaseHelper().database;

    final rows = await db.rawQuery('''
      SELECT
        pt.bank,
        pt.amount,
        pt.type,
        pt.raw_merchant,
        pt.transaction_date,
        pt.confidence,
        pt.dedup_hash,
        rs.sms_hash,
        m.canonical_name,
        m.category,
        m.category_source,
        m.mcc
      FROM parsed_transactions pt
      JOIN raw_sms rs ON rs.id = pt.raw_sms_id
      LEFT JOIN merchants m ON m.id = pt.merchant_id
      ORDER BY pt.id
    ''');

    return rows.map((row) {
      final dateMs = row['transaction_date'] as int?;
      final merchantName = row['canonical_name'] as String?;

      return <String, dynamic>{
        'source_hash': row['sms_hash'],
        'dedup_hash': row['dedup_hash'],
        'bank': row['bank'],
        'amount': (row['amount'] as num).toDouble(),
        'type': row['type'],
        'raw_merchant': row['raw_merchant'],
        'transaction_date': dateMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(dateMs, isUtc: true).toIso8601String(),
        'confidence': (row['confidence'] as num?)?.toDouble() ?? 0,
        'merchant': merchantName == null
            ? null
            : {
                'name': merchantName,
                'category': row['category'],
                'category_source': row['category_source'],
                'mcc': row['mcc'],
              },
      };
    }).toList();
  }

  Future<SyncResult> _sync() async {
    if (AppConfig.webBase.isEmpty) {
      throw const SyncException('SMARTSPEND_WEB_URL is not set in env.json.');
    }

    final items = await _loadItems();
    var total = SyncResult.empty;

    for (var start = 0; start < items.length; start += _batchSize) {
      final batch = items.sublist(
        start,
        start + _batchSize > items.length ? items.length : start + _batchSize,
      );

      final response = await http
          .post(
            Uri.parse('${AppConfig.webBase}/api/sync'),
            headers: {
              'Authorization': 'Bearer ${await _accessToken()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'items': batch}),
          )
          .timeout(const Duration(seconds: 90));

      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        body = {};
      }

      if (response.statusCode == 401) {
        throw const SyncException('Session expired. Log in again.');
      }
      if (response.statusCode != 200) {
        throw SyncException(
          (body['error'] as String?) ?? 'Sync failed (HTTP ${response.statusCode}).',
        );
      }

      total = total +
          SyncResult(
            sent: batch.length,
            inserted: (body['inserted'] as num?)?.toInt() ?? 0,
            updated: (body['updated'] as num?)?.toInt() ?? 0,
            warning: body['warning'] as String?,
          );
    }

    debugPrint('SmartSpend sync: $total');
    return total;
  }
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SyncResult {
  const SyncResult({
    required this.sent,
    required this.inserted,
    required this.updated,
    this.warning,
  });

  static const empty = SyncResult(sent: 0, inserted: 0, updated: 0);

  final int sent;
  final int inserted;
  final int updated;
  final String? warning;

  SyncResult operator +(SyncResult other) => SyncResult(
        sent: sent + other.sent,
        inserted: inserted + other.inserted,
        updated: updated + other.updated,
        warning: other.warning ?? warning,
      );

  String get summary {
    if (inserted == 0 && updated == 0) return 'Up to date ($sent transactions checked)';
    final parts = <String>[
      if (inserted > 0) '$inserted new',
      if (updated > 0) '$updated updated',
    ];
    return 'Synced: ${parts.join(', ')}';
  }

  @override
  String toString() => 'sent=$sent inserted=$inserted updated=$updated warning=$warning';
}

class SyncStatus {
  const SyncStatus._(this.running, this.result, this.error, this.at);
  const SyncStatus.idle() : this._(false, null, null, null);
  const SyncStatus.running() : this._(true, null, null, null);
  SyncStatus.done(SyncResult result) : this._(false, result, null, DateTime.now());
  SyncStatus.failed(String error) : this._(false, null, error, DateTime.now());

  final bool running;
  final SyncResult? result;
  final String? error;
  final DateTime? at;
}
