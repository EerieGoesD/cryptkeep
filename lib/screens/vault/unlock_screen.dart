import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../providers/app_state.dart';
import '../../services/crypto_service.dart';
import '../auth/login_screen.dart';
import 'vault_screen.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final key = CryptoService.deriveKey(_passwordCtrl.text, userId);

      await context.read<AppState>().unlock(key);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VaultScreen()),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    context.read<AppState>().lock();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';

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
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline, size: 48, color: Color(0xFF8B5CF6)),
                          const SizedBox(height: 20),
                          const Text('Unlock Vault',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('Signed in as $email',
                              style: const TextStyle(color: Color(0xFF94A3B8))),
                          const SizedBox(height: 36),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            autofocus: true,
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
                            onFieldSubmitted: (_) => _unlock(),
                          ),
                          const SizedBox(height: 28),
                          _loading
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _unlock,
                                  child: const Text('Unlock'),
                                ),
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton(
                              onPressed: _signOut,
                              child: const Text('Sign out'),
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
