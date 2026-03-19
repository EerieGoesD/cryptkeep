import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../services/crypto_service.dart';
import '../vault/faq_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();
      final masterPassword = _passwordCtrl.text;
      final authPassword = CryptoService.deriveAuthPassword(masterPassword, email);
      final salt = CryptoService.generateSalt(16);
      final key = CryptoService.deriveKey(masterPassword, salt);
      final keyCheck = CryptoService.createKeyCheck(key);

      await supabase.auth.signUp(
        email: email,
        password: authPassword,
        data: {
          'crypto_salt': base64.encode(salt),
          'key_check': keyCheck,
        },
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: Color(0xFF8B5CF6)),
              SizedBox(width: 12),
              Text('Check your email'),
            ],
          ),
          content: Text(
            'We sent a verification link to ${_emailCtrl.text.trim()}.\n\n'
            'Please confirm your email before signing in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
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
      appBar: AppBar(title: const Text('Create Account')),
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
                          const Text('Create your vault',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          const Text(
                            'Your master password encrypts everything locally.\nWe never see your passwords.',
                            style: TextStyle(color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 36),
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
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Enter a master password';
                              if (v.length < 8) return 'Must be at least 8 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscure,
                            decoration: const InputDecoration(labelText: 'Confirm Password'),
                            validator: (v) =>
                                v != _passwordCtrl.text ? 'Passwords do not match' : null,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF8B5CF6), width: 1),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Color(0xFF8B5CF6), size: 18),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'If you lose your master password, your vault cannot be recovered.',
                                    style: TextStyle(
                                        color: Color(0xFF94A3B8), fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          _loading
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _register,
                                  child: const Text('Create Vault'),
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
