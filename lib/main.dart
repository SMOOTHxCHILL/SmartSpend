import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/login_screen.dart';
import 'config.dart';
import 'screens/dashboard_screen.dart';
import 'sms/sms_listener.dart';
import 'sync/cloud_sync.dart';
import 'parsers/parser_test_runner.dart';
import 'ml/ml_categorizer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

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
      home: AppConfig.isConfigured ? const AuthGate() : const MissingConfigScreen(),
    );
  }
}

/// Shows the login screen until there is a session, then the app.
/// Logging out (from the account menu) brings the login screen back.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        // Keyed by user so a different login restarts the pipeline
        return StartupScreen(key: ValueKey(session.user.id));
      },
    );
  }
}

class MissingConfigScreen extends StatelessWidget {
  const MissingConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This build has no server settings.\n\n'
            'Build with --dart-define-from-file=env.json '
            '(see env.example.json).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
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
      // 4. Load the on-device ML categorizer
      // ------------------------------------------------------------
      setState(() {
        status = 'Loading ML categorizer...';
      });

      await MlCategorizer().load();

      // ------------------------------------------------------------
      // 5. Resolve merchants
      // ------------------------------------------------------------
      setState(() {
        status = 'Resolving merchants...';
      });

      await parserRunner.resolveMerchantsForExisting();

      // ------------------------------------------------------------
      // 6. Start listening for future SMS
      // ------------------------------------------------------------
      smsService.startListening();

      debugPrint(
        'SmartSpend startup complete. '
        'Inserted: ${persistResult.inserted}, '
        'Duplicates: ${persistResult.duplicates}, '
        'Invalid: ${persistResult.invalid}, '
        'Needs review: ${persistResult.needsReview}',
      );

      // ------------------------------------------------------------
      // 7. Upload to the account in the background. A failure here is
      //    shown on the dashboard's sync icon and never blocks the app.
      // ------------------------------------------------------------
      CloudSync.instance.syncAll().catchError((Object e) {
        debugPrint('SmartSpend background sync failed: $e');
        return SyncResult.empty;
      });

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
