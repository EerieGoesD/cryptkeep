import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../providers/app_state.dart';
import '../../services/crypto_service.dart';
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final response = await supabase.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final userId = response.user!.id;
      final key = CryptoService.deriveKey(_passwordCtrl.text, userId);

      if (!mounted) return;
      await context.read<AppState>().unlock(key);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VaultScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
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
                          const Center(
                            child: Text('Using CryptKeep is 100% free.',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                          ),
                          const SizedBox(height: 4),
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
              child: InkWell(
                onTap: () => launchUrl(Uri.parse('https://eeriegoesd.com/privacy-policy/cryptkeep/')),
                child: const Text('Privacy Policy',
                    style: TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
