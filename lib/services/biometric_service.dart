import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../config.dart';

/// Stores the derived vault key behind the device's secure hardware
/// (Android Keystore / iOS Keychain) so the user can unlock with fingerprint or
/// face instead of retyping the master password. The key is only released after
/// a successful biometric check - the same convenience-unlock pattern used by
/// Bitwarden and 1Password.
///
/// Note: the stored value is the key DERIVED from the master password. If the
/// master password ever changes, biometric unlock must be re-enabled so a fresh
/// key is stored.
class BiometricService {
  static const _keyStoreKey = 'cryptkeep_vault_key';
  static const _emailStoreKey = 'cryptkeep_biometric_email';

  // Shared keychain group on Apple platforms so the autofill/passkey extension
  // can release the same key after its own Face ID / Touch ID check. Ignored on
  // Android and Windows.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(groupId: kAppleGroupId),
    mOptions: MacOsOptions(groupId: kAppleGroupId),
  );
  static final LocalAuthentication _auth = LocalAuthentication();

  /// True if the device has usable, enrolled biometrics.
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// True if biometric unlock is set up for [email].
  static Future<bool> isEnabledFor(String email) async {
    try {
      final storedEmail = await _storage.read(key: _emailStoreKey);
      final hasKey = await _storage.containsKey(key: _keyStoreKey);
      return hasKey && storedEmail == email;
    } catch (_) {
      return false;
    }
  }

  /// Stores the current vault [key] for [email] behind biometrics.
  static Future<void> enable(String email, Uint8List key) async {
    await _storage.write(key: _keyStoreKey, value: base64.encode(key));
    await _storage.write(key: _emailStoreKey, value: email);
  }

  /// Removes the stored key (disable biometric unlock, or on sign out).
  static Future<void> disable() async {
    await _storage.delete(key: _keyStoreKey);
    await _storage.delete(key: _emailStoreKey);
  }

  /// Prompts for biometrics and, on success, returns the stored vault key.
  /// Returns null if the check fails or nothing is stored.
  static Future<Uint8List?> unlock() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock your CryptKeep vault',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!ok) return null;
      final b64 = await _storage.read(key: _keyStoreKey);
      if (b64 == null) return null;
      return base64.decode(b64);
    } catch (_) {
      return null;
    }
  }
}
