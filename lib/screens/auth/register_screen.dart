import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../services/crypto_service.dart';

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
  String _loadingStatus = '';
  bool _obscure = true;

  String get _password => _passwordCtrl.text;
  String get _confirm => _confirmCtrl.text;

  bool get _hasMinLength => _password.length >= 12;
  bool get _hasUppercase => _password.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase => _password.contains(RegExp(r'[a-z]'));
  bool get _hasDigit => _password.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial => _password.contains(RegExp(r'[^A-Za-z0-9]'));
  bool get _passwordsMatch => _password.isNotEmpty && _confirm.isNotEmpty && _password == _confirm;

  bool get _allRequirementsMet =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasDigit && _hasSpecial && _passwordsMatch;

  int get _strengthCount =>
      [_hasMinLength, _hasUppercase, _hasLowercase, _hasDigit, _hasSpecial].where((e) => e).length;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
    _confirmCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _loadingStatus = 'Creating vault'; });

    try {
      final email = _emailCtrl.text.trim();
      final masterPassword = _passwordCtrl.text;
      final authPassword = await CryptoService.deriveAuthPasswordAsync(masterPassword, email);
      final salt = CryptoService.generateSalt(16);
      final key = await CryptoService.deriveKeyAsync(masterPassword, salt);
      final keyCheck = CryptoService.createKeyCheck(key);

      await supabase.auth.signUp(
        email: email,
        password: authPassword,
        data: {
          'crypto_salt': base64.encode(salt),
          'key_check': keyCheck,
          'key_iterations': CryptoService.defaultKeyIterations,
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
    } on AuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color get _strengthColor {
    if (_strengthCount <= 1) return Colors.red;
    if (_strengthCount <= 2) return Colors.orange;
    if (_strengthCount <= 3) return Colors.amber;
    if (_strengthCount <= 4) return Colors.lightGreen;
    return Colors.green;
  }

  String get _strengthLabel {
    if (_strengthCount <= 1) return 'Weak';
    if (_strengthCount <= 2) return 'Fair';
    if (_strengthCount <= 3) return 'Good';
    if (_strengthCount <= 4) return 'Strong';
    return 'Excellent';
  }

  Widget _buildRequirement(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: met ? Colors.green : const Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: met ? Colors.green : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
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
                              if (v.length < 12) return 'Must be at least 12 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _strengthCount / 5,
                                    minHeight: 4,
                                    backgroundColor: const Color(0xFF2A2A3E),
                                    valueColor: AlwaysStoppedAnimation(_strengthColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _strengthLabel,
                                style: TextStyle(fontSize: 11.5, color: _strengthColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 0,
                            children: [
                              _buildRequirement('12+ chars', _hasMinLength),
                              _buildRequirement('Uppercase', _hasUppercase),
                              _buildRequirement('Lowercase', _hasLowercase),
                              _buildRequirement('Digit', _hasDigit),
                              _buildRequirement('Special', _hasSpecial),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscure,
                            decoration: const InputDecoration(labelText: 'Confirm Password'),
                            validator: (v) =>
                                v != _passwordCtrl.text ? 'Passwords do not match' : null,
                          ),
                          const SizedBox(height: 6),
                          _buildRequirement('Passwords match', _passwordsMatch),
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
                          ElevatedButton(
                            onPressed: _loading || !_allRequirementsMet ? null : _register,
                            child: _loading
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 16, height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(_loadingStatus),
                                    ],
                                  )
                                : const Text('Create Vault'),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
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
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('|', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                                ),
                                InkWell(
                                  onTap: () => launchUrl(Uri.parse('https://buymeacoffee.com/eeriegoesd')),
                                  child: const Text('☕ Buy Me a Coffee',
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
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('|', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('https://github.com/EerieGoesD/cryptkeep/discussions')),
                    child: const Text('Feedback',
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
