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

  static const String _createParsedTransactionsTable = '''
    CREATE TABLE parsed_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      raw_sms_id INTEGER NOT NULL,
      bank TEXT NOT NULL,
      amount REAL NOT NULL,
      type TEXT NOT NULL,
      raw_merchant TEXT NOT NULL,
      transaction_date INTEGER,
      confidence REAL NOT NULL,
      dedup_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      UNIQUE(raw_sms_id)
    )
  ''';

  static const String _createMerchantsTable = '''
    CREATE TABLE merchants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      canonical_name TEXT NOT NULL,
      category TEXT NOT NULL,
      mcc TEXT,
      created_at INTEGER NOT NULL
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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE raw_sms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            body TEXT NOT NULL,
            received_at INTEGER NOT NULL,
            sms_hash TEXT NOT NULL UNIQUE
          )
        ''');

        await db.execute(_createParsedTransactionsTable);
        await db.execute(_createMerchantsTable);
        await db.execute(_createMerchantAliasesTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Version 2
        if (oldVersion < 2) {
          await db.execute(_createParsedTransactionsTable);
        }

        // Version 3
        if (oldVersion < 3) {
          await db.execute(_createMerchantsTable);
          await db.execute(_createMerchantAliasesTable);

          await db.execute(
            'ALTER TABLE parsed_transactions ADD COLUMN merchant_id INTEGER',
          );
        }

        // Version 4
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE raw_sms ADD COLUMN sms_hash TEXT',
          );

          final rows = await db.query('raw_sms');

          for (final row in rows) {
            final sender = row['sender'] as String;
            final body = row['body'] as String;
            final receivedAt = row['received_at'] as int;

            final hash = _computeRawSmsHash(
              sender: sender,
              body: body,
              receivedAt: receivedAt,
            );

            await db.update(
              'raw_sms',
              {'sms_hash': hash},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }

          // Remove duplicate raw SMS records before adding
          // the unique index.
          await db.execute('''
            DELETE FROM raw_sms
            WHERE id NOT IN (
              SELECT MIN(id)
              FROM raw_sms
              GROUP BY sms_hash
            )
          ''');

          await db.execute(
            'CREATE UNIQUE INDEX idx_raw_sms_hash ON raw_sms(sms_hash)',
          );
        }

        // Version 5
        //
        // Previously parsed_transactions used:
        //
        //   UNIQUE(dedup_hash)
        //
        // where dedup_hash was based on:
        //
        //   amount + merchant + date
        //
        // This incorrectly treated two legitimate transactions
        // with the same amount, merchant and date as duplicates.
        //
        // Version 5 changes the uniqueness rule to raw_sms_id,
        // because each parsed transaction should originate from
        // one unique SMS.
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE parsed_transactions_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_sms_id INTEGER NOT NULL,
              bank TEXT NOT NULL,
              amount REAL NOT NULL,
              type TEXT NOT NULL,
              raw_merchant TEXT NOT NULL,
              transaction_date INTEGER,
              confidence REAL NOT NULL,
              dedup_hash TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              UNIQUE(raw_sms_id)
            )
          ''');

          // Keep the existing parsed transactions.
          // If multiple parsed records came from the same raw SMS,
          // keep the first one.
          await db.execute('''
            INSERT OR IGNORE INTO parsed_transactions_new
            SELECT
              id,
              raw_sms_id,
              bank,
              amount,
              type,
              raw_merchant,
              transaction_date,
              confidence,
              dedup_hash,
              created_at
            FROM parsed_transactions
            ORDER BY id ASC
          ''');

          await db.execute(
            'DROP TABLE parsed_transactions',
          );

          await db.execute(
            'ALTER TABLE parsed_transactions_new '
            'RENAME TO parsed_transactions',
          );
        }
      },
    );
  }

  // ------------------------------------------------------------
  // RAW SMS
  // ------------------------------------------------------------

  String _computeRawSmsHash({
    required String sender,
    required String body,
    required int receivedAt,
  }) {
    final key = '$sender|$body|$receivedAt';

    return sha256
        .convert(utf8.encode(key))
        .toString();
  }

  Future<int> insertRawSms(RawSms sms) async {
    final db = await database;

    final hash = _computeRawSmsHash(
      sender: sms.sender,
      body: sms.body,
      receivedAt: sms.receivedAt.millisecondsSinceEpoch,
    );

    return db.insert(
      'raw_sms',
      {
        ...sms.toMap(),
        'sms_hash': hash,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<RawSms>> getAllRawSms() async {
    final db = await database;

    final maps = await db.query(
      'raw_sms',
      orderBy: 'received_at DESC',
    );

    return maps
        .map((m) => RawSms.fromMap(m))
        .toList();
  }

  // ------------------------------------------------------------
  // PARSED TRANSACTIONS
  // ------------------------------------------------------------

  String _computeDedupHash(ParsedTransaction t) {
    final key =
        '${t.amount}|'
        '${t.rawMerchant.toLowerCase().trim()}|'
        '${t.transactionDate?.toIso8601String().split("T").first ?? "no-date"}';

    return sha256
        .convert(utf8.encode(key))
        .toString();
  }

  /// Inserts a parsed transaction.
  ///
  /// A transaction is considered a duplicate when the same
  /// raw SMS has already produced a parsed transaction.
  Future<bool> insertParsedTransaction(
    ParsedTransaction t,
  ) async {
    final db = await database;

    final hash = _computeDedupHash(t);

    try {
      await db.insert(
        'parsed_transactions',
        {
          'raw_sms_id': t.rawSmsId,
          'bank': t.bank,
          'amount': t.amount,
          'type': t.type,
          'raw_merchant': t.rawMerchant,
          'transaction_date':
              t.transactionDate?.millisecondsSinceEpoch,
          'confidence': t.confidence,
          'dedup_hash': hash,
          'created_at':
              DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return true;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return false;
      }

      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>>
      getAllParsedTransactions() async {
    final db = await database;

    return db.query(
      'parsed_transactions',
      orderBy: 'transaction_date DESC',
    );
  }
}