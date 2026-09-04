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
      UNIQUE(dedup_hash)
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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE raw_sms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            body TEXT NOT NULL,
            received_at INTEGER NOT NULL
          )
        ''');
        await db.execute(_createParsedTransactionsTable);
        await db.execute(_createMerchantsTable);
        await db.execute(_createMerchantAliasesTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(_createParsedTransactionsTable);
        }
        if (oldVersion < 3) {
          await db.execute(_createMerchantsTable);
          await db.execute(_createMerchantAliasesTable);
          await db.execute(
            'ALTER TABLE parsed_transactions ADD COLUMN merchant_id INTEGER',
          );
        }
      },
    );
  }

  Future<int> insertRawSms(RawSms sms) async {
    final db = await database;
    return db.insert('raw_sms', sms.toMap());
  }

  Future<List<RawSms>> getAllRawSms() async {
    final db = await database;
    final maps = await db.query('raw_sms', orderBy: 'received_at DESC');
    return maps.map((m) => RawSms.fromMap(m)).toList();
  }

  String _computeDedupHash(ParsedTransaction t) {
    final key = '${t.amount}|${t.rawMerchant.toLowerCase().trim()}|'
        '${t.transactionDate?.toIso8601String().split("T").first ?? "no-date"}';
    return sha256.convert(utf8.encode(key)).toString();
  }

  /// Inserts a parsed transaction. Returns true if inserted, false if it was a duplicate.
  Future<bool> insertParsedTransaction(ParsedTransaction t) async {
    final db = await database;
    final hash = _computeDedupHash(t);

    try {
      await db.insert('parsed_transactions', {
        'raw_sms_id': t.rawSmsId,
        'bank': t.bank,
        'amount': t.amount,
        'type': t.type,
        'raw_merchant': t.rawMerchant,
        'transaction_date': t.transactionDate?.millisecondsSinceEpoch,
        'confidence': t.confidence,
        'dedup_hash': hash,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      return false; // UNIQUE constraint hit — duplicate, silently skipped
    }
  }

  Future<List<Map<String, dynamic>>> getAllParsedTransactions() async {
    final db = await database;
    return db.query('parsed_transactions', orderBy: 'transaction_date DESC');
  }
}