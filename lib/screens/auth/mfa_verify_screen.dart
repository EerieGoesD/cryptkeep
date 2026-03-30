import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../providers/app_state.dart';
import '../../services/migration_service.dart';
import '../vault/vault_screen.dart';

/// Shown after password login when the user has 2FA enabled.
/// Collects a TOTP code, verifies it, then derives the encryption key
/// and unlocks the vault.
class MfaVerifyScreen extends StatefulWidget {
  final String email;
  final String masterPassword;

  const MfaVerifyScreen({
    super.key,
    required this.email,
    required this.masterPassword,
  });

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  int _failedAttempts = 0;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a 6-digit code')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final factors = await supabase.auth.mfa.listFactors();
      final totpFactor = factors.totp.firstWhere(
        (f) => f.status == FactorStatus.verified,
      );

      final challenge = await supabase.auth.mfa.challenge(
        factorId: totpFactor.id,
      );
      await supabase.auth.mfa.verify(
        factorId: totpFactor.id,
        challengeId: challenge.id,
        code: code,
      );

      // MFA passed - now derive key and unlock vault
      Uint8List key;
      if (MigrationService.needsMigration()) {
        final result = await MigrationService.migrate(
          widget.masterPassword,
          widget.email,
        );
        key = result.key;
        if (result.hadFailures && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '${result.failedEntries} entries and ${result.failedCategories} categories could not be migrated.',
            )),
          );
        }
      } else {
        key = MigrationService.getKey(widget.masterPassword);
      }

      if (!MigrationService.verifyPassword(key)) {
        await supabase.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect master password')),
        );
        Navigator.of(context).pop();
        return;
      }

      if (!mounted) return;
      await context.read<AppState>().unlock(key);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VaultScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _failedAttempts++;
      _codeCtrl.clear();

      if (_failedAttempts >= 5) {
        await supabase.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Too many failed attempts. Please sign in again.')),
        );
        Navigator.of(context).pop();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          e.message.contains('invalid') ? 'Invalid code. Try again.' : 'Verification failed.',
        )),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification failed. Please try again.')),
      );
    }
  }

  Future<void> _cancel() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.security, size: 48, color: Color(0xFF8B5CF6)),
                  const SizedBox(height: 20),
                  const Text(
                    'Two-factor verification',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter the 6-digit code from your authenticator app.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 10),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '000000',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      if (value.length == 6) _verify();
                    },
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 28),
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _verify,
                          child: const Text('Verify'),
                        ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _cancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
