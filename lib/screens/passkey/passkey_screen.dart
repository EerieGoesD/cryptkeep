import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../models/vault_entry.dart';
import '../../services/biometric_service.dart';
import '../../services/migration_service.dart';
import '../../services/passkey_service.dart';
import '../../services/vault_cache_service.dart';
import '../../services/vault_service.dart';

/// Shown when another app or site asks CryptKeep to save a passkey.
/// Runs via the `passkeyEntryPoint` Dart entrypoint from PasskeyActivity.
class PasskeyApp extends StatelessWidget {
  const PasskeyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptKeep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          surface: Color(0xFF12121E),
          onSurface: Color(0xFFE2E8F0),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A12),
          foregroundColor: Color(0xFFE2E8F0),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const PasskeyScreen(),
    );
  }
}

class PasskeyScreen extends StatefulWidget {
  const PasskeyScreen({super.key});

  @override
  State<PasskeyScreen> createState() => _PasskeyScreenState();
}

class _PasskeyScreenState extends State<PasskeyScreen> {
  static const _channel = MethodChannel('cryptkeep/passkey');

  final _passwordCtrl = TextEditingController();
  Map<String, dynamic>? _request;
  bool _loading = true;
  bool _needsPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  String get _siteName =>
      (_request?['rpName'] as String?) ?? (_request?['rpId'] as String?) ?? '';

  String get _mode => (_request?['mode'] as String?) ?? '';

  Future<void> _start() async {
    try {
      _request = await _channel.invokeMapMethod<String, dynamic>('getRequest');
    } catch (_) {
      _request = null;
    }
    if (_request == null) {
      _fail('Could not read the passkey request.');
      return;
    }

    if (supabase.auth.currentUser?.email == null) {
      _fail('Open CryptKeep and sign in first.');
      return;
    }

    // User verification before using a passkey is required of a provider, and
    // biometric unlock is exactly that. Falls back to the master password.
    final email = supabase.auth.currentUser!.email!;
    if (await BiometricService.isEnabledFor(email)) {
      final key = await BiometricService.unlock();
      if (key != null) {
        await _runMode(key);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _needsPassword = true;
    });
  }

  Future<void> _runMode(Uint8List key) async {
    switch (_mode) {
      case 'create':
        await _createPasskey(key);
      case 'unlock':
        await _listPasskeys(key);
      case 'get':
        await _signWithPasskey(key);
      default:
        _fail('Could not read the passkey request.');
    }
  }

  /// The vault was locked when the platform asked which passkeys exist, so
  /// answer now: hand back the ones for this site.
  Future<void> _listPasskeys(Uint8List key) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _needsPassword = false;
      _error = null;
    });
    try {
      final rpId = (_request!['rpId'] as String?) ?? '';
      final entries = await VaultCacheService.load(key) ??
          await VaultService.fetchAll(key);

      final matches = entries
          .where((e) => e.passkey != null && e.passkey!.rpId == rpId)
          .map((e) => {
                'credentialId': e.passkey!.credentialId,
                'username': e.username.isNotEmpty ? e.username : e.title,
              })
          .toList();

      await _channel.invokeMethod('completeUnlock', {'passkeys': matches});
    } catch (e) {
      debugPrint('CRYPTKEEP_PASSKEY list failed: $e');
      _fail('Could not read your passkeys.');
    }
  }

  /// The user picked one of those entries: sign the site's challenge with it.
  Future<void> _signWithPasskey(Uint8List key) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _needsPassword = false;
      _error = null;
    });
    try {
      final credentialId = _request!['credentialId'] as String?;
      final entries = await VaultCacheService.load(key) ??
          await VaultService.fetchAll(key);

      final entry = entries.firstWhere(
        (e) => e.passkey != null && e.passkey!.credentialId == credentialId,
        orElse: () => throw StateError('passkey $credentialId not in vault'),
      );

      final hash = _request!['clientDataHash'] as Uint8List?;
      final responseJson = await PasskeyService.assertion(
        passkey: entry.passkey!,
        clientDataJson: _request!['clientDataJson'] as String,
        includeClientDataJson:
            (_request!['includeClientDataJson'] as bool?) ?? true,
        clientDataHash: hash,
      );

      await _channel.invokeMethod('completeGet', {'responseJson': responseJson});
    } catch (e) {
      debugPrint('CRYPTKEEP_PASSKEY sign failed: $e');
      _fail('Could not sign in with that passkey.');
    }
  }

  Future<void> _unlockWithPassword() async {
    if (_passwordCtrl.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final key = await MigrationService.getKeyAsync(_passwordCtrl.text);
      if (!MigrationService.verifyPassword(key)) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _needsPassword = true;
          _error = 'Incorrect master password';
        });
        return;
      }
      await _runMode(key);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsPassword = true;
        _error = 'Could not unlock the vault';
      });
    }
  }

  Future<void> _createPasskey(Uint8List key) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _needsPassword = false;
      _error = null;
    });

    try {
      final creation = await PasskeyService.create(
        rpId: _request!['rpId'] as String,
        userHandle: _request!['userHandle'] as String,
        clientDataJson: _request!['clientDataJson'] as String,
        includeClientDataJson:
            (_request!['includeClientDataJson'] as bool?) ?? true,
      );

      final now = DateTime.now();
      await VaultService.create(
        VaultEntry(
          id: const Uuid().v4(),
          title: _siteName,
          username: (_request!['userName'] as String?) ?? '',
          password: '',
          // Saved so the entry matches this site later, and so it reads as a
          // real login in the vault rather than a bare name.
          url: _request!['rpId'] as String,
          passkey: creation.data,
          createdAt: now,
          updatedAt: now,
        ),
        key,
      );

      await _channel.invokeMethod('completeCreate', {
        'responseJson': creation.registrationResponseJson,
      });
    } catch (e) {
      debugPrint('CRYPTKEEP_PASSKEY create failed: $e');
      _fail('Could not save the passkey. Check your connection and try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _needsPassword = false;
      _error = message;
    });
  }

  Future<void> _cancel() async {
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CryptKeep')),
      body: _loading
          ? _buildBusy()
          : _needsPassword
              ? _buildUnlock()
              : _buildError(),
    );
  }

  String get _busyLabel {
    final where = _siteName.isEmpty ? '' : ' for $_siteName';
    return switch (_mode) {
      'create' => 'Saving passkey$where',
      'get' => 'Signing in$where',
      _ => 'Unlocking',
    };
  }

  Widget _buildBusy() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _busyLabel,
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Color(0xFFFBBF24)),
              const SizedBox(height: 14),
              Text(
                _error ?? 'Something went wrong',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 20),
              TextButton(onPressed: _cancel, child: const Text('Close')),
            ],
          ),
        ),
      );

  Widget _buildUnlock() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.key, size: 48, color: Color(0xFF8B5CF6)),
              const SizedBox(height: 16),
              Text(
                  _mode == 'create'
                      ? 'Unlock to save a passkey'
                      : 'Unlock to use your passkey',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              if (_siteName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('for $_siteName',
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Master Password'),
                onSubmitted: (_) => _unlockWithPassword(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFFBBF24), fontSize: 13)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _unlockWithPassword,
                  child: const Text('Unlock'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ],
          ),
        ),
      ),
    );
  }
}
