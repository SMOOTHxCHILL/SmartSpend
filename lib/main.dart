import 'package:flutter/material.dart';
import 'sms/sms_listener.dart';
import 'db/database_helper.dart';
import 'models/raw_sms.dart';
import 'parsers/parser_test_runner.dart';

void main() {
  runApp(const SmartSpendApp());
}

class SmartSpendApp extends StatelessWidget {
  const SmartSpendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartSpend',
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SmsListenerService smsService = SmsListenerService();
  List<RawSms> messages = [];

  Future<void> _runParserTest() async {
    final result = await ParserTestRunner().run();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Parsed ${result.matched.length} / ${result.total}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView(
            children: [
              const Text('✅ MATCHED', style: TextStyle(fontWeight: FontWeight.bold)),
              ...result.matched.map((m) => Text(m)),
              const SizedBox(height: 16),
              const Text('❌ UNMATCHED', style: TextStyle(fontWeight: FontWeight.bold)),
              ...result.unmatched.map((m) => Text(m, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _persistParsedTransactions() async {
    final (inserted, duplicates) = await ParserTestRunner().runAndPersist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Inserted: $inserted, Duplicates skipped: $duplicates')),
    );
  }

  Future<void> _resolveMerchants() async {
    final resolvedCount = await ParserTestRunner().resolveMerchantsForExisting();
    if (!mounted) return;

    final database = await DatabaseHelper().database;
    final merchants = await database.query('merchants');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Resolved: $resolvedCount, Distinct merchants: ${merchants.length}',
        ),
      ),
    );
  }

  Future<void> _viewMerchants() async {
    final database = await DatabaseHelper().database;
    final merchants = await database.query('merchants', orderBy: 'canonical_name');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Merchants (${merchants.length})'),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: ListView.builder(
            itemCount: merchants.length,
            itemBuilder: (context, i) {
              final m = merchants[i];
              return ListTile(
                title: Text(m['canonical_name'] as String),
                subtitle: Text(m['category'] as String),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _init() async {
    final granted = await smsService.requestPermissions();
    if (granted) {
      smsService.startListening();
      await smsService.importExistingInbox();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final all = await DatabaseHelper().getAllRawSms();
    setState(() => messages = all);
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SmartSpend — Raw SMS')),
      body: ListView.builder(
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final m = messages[i];
          return ListTile(
            title: Text(m.sender),
            subtitle: Text(m.body),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'viewMerchants',
            onPressed: _viewMerchants,
            child: const Icon(Icons.visibility),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'resolve',
            onPressed: _resolveMerchants,
            child: const Icon(Icons.account_tree),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'persist',
            onPressed: _persistParsedTransactions,
            child: const Icon(Icons.save),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'parse',
            onPressed: _runParserTest,
            child: const Icon(Icons.science),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'refresh',
            onPressed: _refresh,
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}