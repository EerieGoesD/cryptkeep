import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';

class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  bool _loading = true;
  bool _enrolled = false;
  String? _enrolledFactorId;

  // Enrollment state
  bool _enrolling = false;
  String? _totpUri;
  String? _totpSecret;
  String? _pendingFactorId;
  final _codeCtrl = TextEditingController();
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() => _loading = true);
    try {
      final factors = await supabase.auth.mfa.listFactors();
      final totpFactors = factors.totp.where((f) => f.status == FactorStatus.verified).toList();
      setState(() {
        _enrolled = totpFactors.isNotEmpty;
        _enrolledFactorId = totpFactors.isNotEmpty ? totpFactors.first.id : null;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _startEnrollment() async {
    setState(() => _enrolling = true);
    try {
      final response = await supabase.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'CryptKeep',
        friendlyName: 'CryptKeep',
      );
      setState(() {
        _pendingFactorId = response.id;
        _totpUri = response.totp?.uri;
        _totpSecret = response.totp?.secret;
      });
    } catch (e) {
      debugPrint('MFA enroll error: $e');
      if (!mounted) return;
      setState(() => _enrolling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('2FA setup failed: $e')),
      );
    }
  }

  Future<void> _verifyAndActivate() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a 6-digit code')),
      );
      return;
    }

    setState(() => _verifying = true);
    try {
      final challenge = await supabase.auth.mfa.challenge(
        factorId: _pendingFactorId!,
      );
      await supabase.auth.mfa.verify(
        factorId: _pendingFactorId!,
        challengeId: challenge.id,
        code: code,
      );

      if (!mounted) return;
      setState(() {
        _enrolled = true;
        _enrolledFactorId = _pendingFactorId;
        _enrolling = false;
        _totpUri = null;
        _totpSecret = null;
        _pendingFactorId = null;
        _verifying = false;
      });
      _codeCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor authentication enabled')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message.contains('invalid') ? 'Invalid code. Try again.' : 'Verification failed.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification failed. Please try again.')),
      );
    }
  }

  Future<void> _disable2FA() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Disable 2FA'),
        content: const Text(
          'This will remove two-factor authentication from your account. '
          'You will only need your master password to sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await supabase.auth.mfa.unenroll(_enrolledFactorId!);
      if (!mounted) return;
      setState(() {
        _enrolled = false;
        _enrolledFactorId = null;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor authentication disabled')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to disable 2FA. Please try again.')),
      );
    }
  }

  void _cancelEnrollment() {
    // Clean up the pending unverified factor
    if (_pendingFactorId != null) {
      supabase.auth.mfa.unenroll(_pendingFactorId!).ignore();
    }
    setState(() {
      _enrolling = false;
      _totpUri = null;
      _totpSecret = null;
      _pendingFactorId = null;
    });
    _codeCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _enrolling ? _buildEnrollmentView() : _buildStatusView(),
                ),
              ),
            ),
    );
  }

  Widget _buildStatusView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _enrolled ? Icons.verified_user : Icons.shield_outlined,
          size: 48,
          color: _enrolled ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
        ),
        const SizedBox(height: 16),
        Text(
          _enrolled ? '2FA is enabled' : '2FA is disabled',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _enrolled
              ? 'Your account is protected with an authenticator app. '
                'You will be asked for a verification code each time you sign in.'
              : 'Add an extra layer of security to your account by requiring a '
                'verification code from an authenticator app when signing in.',
          style: const TextStyle(color: Color(0xFF94A3B8), height: 1.5),
        ),
        const SizedBox(height: 32),
        if (_enrolled)
          ElevatedButton(
            onPressed: _disable2FA,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Disable 2FA'),
          )
        else
          ElevatedButton(
            onPressed: _startEnrollment,
            child: const Text('Enable 2FA'),
          ),
      ],
    );
  }

  Widget _buildEnrollmentView() {
    if (_totpUri == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set up authenticator',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Scan this QR code with your authenticator app (Google Authenticator, Authy, etc.).',
          style: TextStyle(color: Color(0xFF94A3B8), height: 1.5),
        ),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _totpUri!,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Or enter this key manually:',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _totpSecret ?? '',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Color(0xFF8B5CF6)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _totpSecret ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Secret copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Enter verification code',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the 6-digit code from your authenticator app to verify setup.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '000000',
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            if (value.length == 6) _verifyAndActivate();
          },
          onSubmitted: (_) => _verifyAndActivate(),
        ),
        const SizedBox(height: 24),
        _verifying
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton(
                onPressed: _verifyAndActivate,
                child: const Text('Verify & Enable'),
              ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _cancelEnrollment,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}
