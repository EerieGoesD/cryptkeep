import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../providers/app_state.dart';
import '../../services/crypto_service.dart';
import '../../services/migration_service.dart';
import '../vault/vault_screen.dart';
import '../vault/faq_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final secs = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Too many attempts. Try again in ${secs}s')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();
      final masterPassword = _passwordCtrl.text;

      // Try v2 (PBKDF2) → v1 (SHA-256) → raw legacy password
      int authVersion = 2;
      try {
        final authV2 = CryptoService.deriveAuthPassword(masterPassword, email);
        await supabase.auth.signInWithPassword(email: email, password: authV2);
      } on AuthException {
        try {
          final authV1 = CryptoService.deriveAuthPasswordLegacy(masterPassword, email);
          await supabase.auth.signInWithPassword(email: email, password: authV1);
          authVersion = 1;
        } on AuthException {
          // Last resort: raw master password (pre-migration users only)
          await supabase.auth.signInWithPassword(email: email, password: masterPassword);
          authVersion = 0;
        }
      }

      Uint8List key;
      if (authVersion < 2 || MigrationService.needsMigration()) {
        final result = await MigrationService.migrate(masterPassword, email);
        key = result.key;
        if (result.hadFailures && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '${result.failedEntries} entries and ${result.failedCategories} categories could not be migrated.',
            )),
          );
        }
      } else {
        key = MigrationService.getKey(masterPassword);
      }

      if (!MigrationService.verifyPassword(key)) {
        await supabase.auth.signOut();
        if (!mounted) return;
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _lockoutUntil = DateTime.now().add(Duration(seconds: 30 * (_failedAttempts ~/ 5)));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect master password')),
        );
        return;
      }

      _failedAttempts = 0;
      if (!mounted) return;
      await context.read<AppState>().unlock(key);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VaultScreen()),
        (_) => false,
      );
    } on AuthException {
      if (!mounted) return;
      _failedAttempts++;
      if (_failedAttempts >= 5) {
        _lockoutUntil = DateTime.now().add(Duration(seconds: 30 * (_failedAttempts ~/ 5)));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid email or password')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline, size: 48, color: Color(0xFF8B5CF6)),
                          const SizedBox(height: 20),
                          const Text('Welcome back',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          const Text('Sign in to access your vault.',
                              style: TextStyle(color: Color(0xFF94A3B8))),
                          const SizedBox(height: 20),
                          const Text('CryptKeep is 100% free.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const FaqScreen()),
                            ),
                            icon: const Icon(Icons.help_outline, size: 18, color: Color(0xFF8B5CF6)),
                            label: const Text('What is CryptKeep?',
                                style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 13)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                            validator: (v) =>
                                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Master Password',
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                                    color: const Color(0xFF94A3B8)),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Enter your master password' : null,
                          ),
                          const SizedBox(height: 28),
                          _loading
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _login,
                                  child: const Text('Sign In'),
                                ),
                          const SizedBox(height: 16),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text("Don't have an account? ",
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                  ),
                                  child: const Text('Create one',
                                      style: TextStyle(
                                          color: Color(0xFF8B5CF6),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: InkWell(
                              onTap: () => launchUrl(Uri.parse('https://eeriegoesd.com/')),
                              child: const Text.rich(
                                TextSpan(
                                  text: 'Made by ',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                  children: [
                                    TextSpan(
                                      text: 'EERIE',
                                      style: TextStyle(
                                        color: Color(0xFF8B5CF6),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: InkWell(
                              onTap: () => launchUrl(Uri.parse('https://buymeacoffee.com/eeriegoesd')),
                              child: const Text('☕ Buy Me a Coffee',
                                  style: TextStyle(
                                      color: Color(0xFF8B5CF6),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('https://eeriegoesd.com/privacy-policy/cryptkeep/')),
                    child: const Text('Privacy Policy',
                        style: TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('|', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('mailto:eeriegoesd@gmail.com?subject=CryptKeep%20Support')),
                    child: const Text('Need help?',
                        style: TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('|', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('https://github.com/EerieGoesD/cryptkeep/issues')),
                    child: const Text('Report an Issue',
                        style: TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
