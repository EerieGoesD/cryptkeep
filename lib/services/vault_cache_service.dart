import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app.dart';
import '../models/vault_entry.dart';
import 'crypto_service.dart';

/// A local copy of the vault so autofill can read it without a network round
/// trip - the autofill service is launched by another app and often has no
/// chance to wait on Supabase, or no connection at all.
///
/// Entries are stored exactly as the server holds them: still AES-256-GCM
/// ciphertext that only the master key opens. Nothing is written in the clear,
/// so this adds no secret to the device that biometric unlock did not already
/// keep there. See [BiometricService], which holds the key itself.
///
/// Android only: that is where autofill runs, and a cache with no reader is
/// only extra exposure.
class VaultCacheService {
  static const _cacheKey = 'cryptkeep_vault_cache';
  static const _version = 1;

  static const _storage = FlutterSecureStorage();

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stores the encrypted rows for the signed-in user. Failures are ignored:
  /// the cache is an optimisation, never the source of truth.
  static Future<void> save(List<String> encryptedRows) async {
    if (!_supported) return;
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _storage.write(
        key: _cacheKey,
        value: jsonEncode({
          'v': _version,
          'user_id': userId,
          'rows': encryptedRows,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Vault cache save failed: $e');
    }
  }

  /// Returns the cached entries, or null if there is no usable cache: no cache
  /// stored, a different user, an old format, or rows that [key] cannot open
  /// (a stale cache from a changed master password).
  static Future<List<VaultEntry>?> load(Uint8List key) async {
    if (!_supported) return null;
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final raw = await _storage.read(key: _cacheKey);
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['v'] != _version || json['user_id'] != userId) return null;

      final rows = (json['rows'] as List).cast<String>();
      final entries = <VaultEntry>[];
      for (final row in rows) {
        try {
          final plaintext = CryptoService.decrypt(row, key);
          entries.add(
              VaultEntry.fromJson(jsonDecode(plaintext) as Map<String, dynamic>));
        } catch (_) {
          // Skip rows this key cannot open, as fetchAll does.
        }
      }

      // Rows that all fail to decrypt mean the cache is unusable, not that the
      // vault is empty. Fall back to the network rather than show nothing.
      if (rows.isNotEmpty && entries.isEmpty) return null;
      return entries;
    } catch (e) {
      if (kDebugMode) debugPrint('Vault cache load failed: $e');
      return null;
    }
  }

  /// Removes the cached vault. Call on sign out and account deletion.
  static Future<void> clear() async {
    try {
      await _storage.delete(key: _cacheKey);
    } catch (_) {}
  }
}
