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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
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

  bool isLoading = true;
  String statusMessage = 'Loading SMS messages...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      setState(() {
        isLoading = true;
        statusMessage = 'Requesting SMS permission...';
      });

      final granted = await smsService.requestPermissions();

      if (!granted) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
          statusMessage = 'SMS permission was not granted.';
        });

        return;
      }

      smsService.startListening();

      if (!mounted) return;

      setState(() {
        statusMessage = 'Importing SMS messages...';
      });

      await smsService.importExistingInbox();

      if (!mounted) return;

      setState(() {
        statusMessage = 'Parsing transactions...';
      });

      final parserRunner = ParserTestRunner();

      final persistResult = await parserRunner.runAndPersist();

      if (!mounted) return;

      setState(() {
        statusMessage =
            'Saved ${persistResult.inserted} new transactions.';
      });

      await parserRunner.resolveMerchantsForExisting();

      if (!mounted) return;

      await _refresh();

      if (!mounted) return;

      setState(() {
        isLoading = false;
        statusMessage = 'Ready';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _refresh() async {
    final all = await DatabaseHelper().getAllRawSms();

    if (!mounted) return;

    setState(() {
      messages = all;
    });
  }

  Future<void> _manualSync() async {
    await _init();
  }

  Future<void> _viewMerchants() async {
    final database = await DatabaseHelper().database;

    final merchants = await database.query(
      'merchants',
      orderBy: 'canonical_name',
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Merchants (${merchants.length})',
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: ListView.builder(
            itemCount: merchants.length,
            itemBuilder: (context, i) {
              final merchant = merchants[i];

              return ListTile(
                title: Text(
                  merchant['canonical_name'] as String,
                ),
                subtitle: Text(
                  merchant['category'] as String,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSpend'),
        actions: [
          IconButton(
            tooltip: 'Sync SMS',
            onPressed: isLoading ? null : _manualSync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isLoading)
            const LinearProgressIndicator(),

          if (statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                statusMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'No SMS messages found.',
                    ),
                  )
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final message = messages[i];

                      return ListTile(
                        title: Text(message.sender),
                        subtitle: Text(message.body),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isLoading ? null : _viewMerchants,
        tooltip: 'View merchants',
        child: const Icon(Icons.store),
      ),
    );
  }
}