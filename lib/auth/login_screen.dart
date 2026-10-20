import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Phone-number + OTP login, using the same Supabase accounts as the
/// web companion. After a successful login the AuthGate in main.dart
/// switches to the app automatically.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _resendSeconds = 60; // Supabase allows one OTP per minute

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  SupabaseClient get _supabase => Supabase.instance.client;

  /// "98765 43210" → "+919876543210". Ten digits are treated as Indian.
  String get _e164 {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10 ? '+91$digits' : '+$digits';
  }

  bool get _phoneValid => RegExp(r'^\+\d{11,15}$').hasMatch(_e164);

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!_phoneValid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _supabase.auth.signInWithOtp(phone: _e164);
      _codeController.clear();
      setState(() => _codeSent = true);
      _startResendTimer();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not send the code. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _supabase.auth.verifyOTP(type: OtpType.sms, phone: _e164, token: code);
      // Join the invited account or create a new one (same as the website)
      await _supabase.rpc('ensure_account');
      // AuthGate rebuilds on the auth state change.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('SmartSpend')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _codeSent ? 'Enter the code' : 'Log in',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'We sent a 6-digit code to $_e164.'
                  : 'Use the same phone number as on the SmartSpend website. '
                      'Your transactions will sync to that account.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (!_codeSent)
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+91 98765 43210',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _sendCode(),
              )
            else
              TextField(
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 12),
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {});
                  if (value.length == 6) _verify();
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : _codeSent
                      ? (_codeController.text.length == 6 ? _verify : null)
                      : (_phoneValid ? _sendCode : null),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_codeSent ? 'Log in' : 'Send code'),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _error = null;
                            }),
                    child: const Text('Change number'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy || _resendIn > 0 ? null : _sendCode,
                    child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
