import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/raw_sms.dart';
import '../models/parsed_transaction.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static const int _databaseVersion = 6;

  static const String _createRawSmsTable = '''
    CREATE TABLE raw_sms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sender TEXT NOT NULL,
      body TEXT NOT NULL,
      received_at INTEGER NOT NULL,
      sms_hash TEXT NOT NULL UNIQUE
    )
  ''';

  static const String _createParsedTransactionsTable = '''
    CREATE TABLE parsed_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      raw_sms_id INTEGER NOT NULL UNIQUE,
      bank TEXT NOT NULL,
      amount REAL NOT NULL,
      type TEXT NOT NULL,
      raw_merchant TEXT NOT NULL,
      transaction_date INTEGER,
      confidence REAL NOT NULL,
      dedup_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      merchant_id INTEGER,
      FOREIGN KEY (raw_sms_id) REFERENCES raw_sms (id)
    )
  ''';

  // category_source distinguishes labels a model can trust ('user_corrected')
  // from the placeholder default ('default') assigned at merchant creation.
  // This is the label signal Phase 2 training filters on.
  static const String _createMerchantsTable = '''
    CREATE TABLE merchants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      canonical_name TEXT NOT NULL,
      category TEXT NOT NULL,
      category_source TEXT NOT NULL DEFAULT 'default',
      mcc TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER
    )
  ''';

  static const String _createMerchantAliasesTable = '''
    CREATE TABLE merchant_aliases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      merchant_id INTEGER NOT NULL,
      alias_text TEXT NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants (id),
      UNIQUE(alias_text)
    )
  ''';

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'smartspend.db');

    return openDatabase(
      path,
      version: _databaseVersion,

      onCreate: (db, version) async {
        await db.execute(_createRawSmsTable);
        await db.execute(_createParsedTransactionsTable);
        await db.execute(_createMerchantsTable);
        await db.execute(_createMerchantAliasesTable);
      },

      onUpgrade: (db, oldVersion, newVersion) async {
        /*
         * Development-stage migration.
         *
         * The app has previously gone through several database schemas.
         * Since the database has already been cleared during development,
         * this migration mainly protects against older local databases.
         */

        if (oldVersion < 6) {
          // Rebuild the database tables into the current schema.
          //
          // This is acceptable during the current development phase.
          // Once the schema is considered stable, use proper production
          // migrations instead of rebuilding.

          await db.execute('DROP TABLE IF EXISTS merchant_aliases');
          await db.execute('DROP TABLE IF EXISTS merchants');
          await db.execute('DROP TABLE IF EXISTS parsed_transactions');
          await db.execute('DROP TABLE IF EXISTS raw_sms');

          await db.execute(_createRawSmsTable);
          await db.execute(_createParsedTransactionsTable);
          await db.execute(_createMerchantsTable);
          await db.execute(_createMerchantAliasesTable);
        }
      },
    );
  }

  String _computeRawSmsHash(RawSms sms) {
    final key =
        '${sms.sender.trim().toUpperCase()}|'
        '${sms.body.trim()}|'
        '${sms.receivedAt.millisecondsSinceEpoch}';

    return sha256.convert(
      utf8.encode(key),
    ).toString();
  }

  Future<int?> insertRawSms(RawSms sms) async {
    final db = await database;

    final hash = _computeRawSmsHash(sms);

    try {
      final id = await db.insert(
        'raw_sms',
        {
          'sender': sms.sender,
          'body': sms.body,
          'received_at': sms.receivedAt.millisecondsSinceEpoch,
          'sms_hash': hash,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      if (id == 0) {
        return null;
      }

      return id;
    } catch (e) {
      return null;
    }
  }

  Future<List<RawSms>> getAllRawSms() async {
    final db = await database;

    final maps = await db.query(
      'raw_sms',
      orderBy: 'received_at DESC',
    );

    return maps.map((m) => RawSms.fromMap(m)).toList();
  }

  String _computeParsedDedupHash(ParsedTransaction t) {
    final key =
        '${t.rawSmsId}|'
        '${t.amount}|'
        '${t.type}|'
        '${t.rawMerchant.toLowerCase().trim()}|'
        '${t.transactionDate?.toIso8601String().split("T").first ?? "no-date"}';

    return sha256.convert(
      utf8.encode(key),
    ).toString();
  }

  Future<bool> insertParsedTransaction(
    ParsedTransaction t,
  ) async {
    final db = await database;

    final hash = _computeParsedDedupHash(t);

    try {
      final id = await db.insert(
        'parsed_transactions',
        {
          'raw_sms_id': t.rawSmsId,
          'bank': t.bank,
          'amount': t.amount,
          'type': t.type,
          'raw_merchant': t.rawMerchant,
          'transaction_date': t.transactionDate?.millisecondsSinceEpoch,
          'confidence': t.confidence,
          'dedup_hash': hash,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'merchant_id': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      return id != 0;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAllParsedTransactions() async {
    final db = await database;

    return db.query(
      'parsed_transactions',
      orderBy: 'transaction_date DESC',
    );
  }

  /// Joins parsed transactions with their resolved merchant so the UI can
  /// show category and category_source without a second query per row.
  Future<List<Map<String, dynamic>>> getAllParsedTransactionsWithMerchant() async {
    final db = await database;

    return db.rawQuery('''
      SELECT
        pt.id,
        pt.amount,
        pt.type,
        pt.raw_merchant,
        pt.transaction_date,
        pt.confidence,
        pt.merchant_id,
        m.canonical_name AS merchant_name,
        m.category AS category,
        m.category_source AS category_source
      FROM parsed_transactions pt
      LEFT JOIN merchants m ON pt.merchant_id = m.id
      ORDER BY pt.transaction_date DESC
    ''');
  }

  /// Records a user's category correction on the merchant itself, so every
  /// transaction from that merchant inherits it. This is also the labeled
  /// training signal for the Phase 2 categorizer (category_source = 'user_corrected').
  Future<void> updateMerchantCategory(int merchantId, String category) async {
    final db = await database;

    await db.update(
      'merchants',
      {
        'category': category,
        'category_source': 'user_corrected',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [merchantId],
    );
  }

  /// Total spend per category within a date range (inclusive start,
  /// exclusive end). Only debit transactions count as spend.
  Future<List<Map<String, dynamic>>> getCategoryBreakdown({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await database;

    return db.rawQuery('''
      SELECT m.category AS category, SUM(pt.amount) AS total
      FROM parsed_transactions pt
      JOIN merchants m ON pt.merchant_id = m.id
      WHERE pt.type = 'debit'
        AND pt.transaction_date >= ?
        AND pt.transaction_date < ?
      GROUP BY m.category
      ORDER BY total DESC
    ''', [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);
  }

  /// Total spend per calendar month for the last [monthsBack] months,
  /// oldest first -- feeds the trend line chart.
  Future<List<Map<String, dynamic>>> getMonthlyTotals({
    int monthsBack = 6,
  }) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: monthsBack * 31));

    return db.rawQuery('''
      SELECT
        strftime('%Y-%m', datetime(pt.transaction_date / 1000, 'unixepoch')) AS month,
        SUM(pt.amount) AS total
      FROM parsed_transactions pt
      JOIN merchants m ON pt.merchant_id = m.id
      WHERE pt.type = 'debit'
        AND pt.transaction_date >= ?
      GROUP BY month
      ORDER BY month ASC
    ''', [cutoff.millisecondsSinceEpoch]);
  }
}