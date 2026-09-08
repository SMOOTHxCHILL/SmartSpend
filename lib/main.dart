import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'sms/sms_listener.dart';
import 'parsers/parser_test_runner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String status = 'Starting SmartSpend...';
  String? error;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final smsService = SmsListenerService();

      // ------------------------------------------------------------
      // 1. Request SMS permissions
      // ------------------------------------------------------------
      setState(() {
        status = 'Requesting SMS permission...';
      });

      final permissionGranted = await smsService.requestPermissions();

      if (!permissionGranted) {
        setState(() {
          error = 'SMS permission was not granted.';
          status =
              'SmartSpend needs SMS permission to import bank transactions.';
        });
        return;
      }

      // ------------------------------------------------------------
      // 2. Import existing SMS inbox
      // ------------------------------------------------------------
      setState(() {
        status = 'Importing existing SMS messages...';
      });

      await smsService.importExistingInbox();

      // ------------------------------------------------------------
      // 3. Parse and persist transactions
      // ------------------------------------------------------------
      setState(() {
        status = 'Parsing bank transactions...';
      });

      final parserRunner = ParserTestRunner();

      final persistResult = await parserRunner.runAndPersist();

      // ------------------------------------------------------------
      // 4. Resolve merchants
      // ------------------------------------------------------------
      setState(() {
        status = 'Resolving merchants...';
      });

      await parserRunner.resolveMerchantsForExisting();

      // ------------------------------------------------------------
      // 5. Start listening for future SMS
      // ------------------------------------------------------------
      smsService.startListening();

      debugPrint(
        'SmartSpend startup complete. '
        'Inserted: ${persistResult.inserted}, '
        'Duplicates: ${persistResult.duplicates}, '
        'Invalid: ${persistResult.invalid}, '
        'Needs review: ${persistResult.needsReview}',
      );

      if (!mounted) return;

      setState(() {
        finished = true;
        status = 'Ready';
      });
    } catch (e, stackTrace) {
      debugPrint('SmartSpend startup error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        error = e.toString();
        status = 'Startup failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (finished) {
      return const DashboardScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSpend'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (error == null)
                const CircularProgressIndicator(),

              const SizedBox(height: 24),

              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),

              if (error != null) ...[
                const SizedBox(height: 16),

                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      error = null;
                      finished = false;
                    });

                    _initializeApp();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}