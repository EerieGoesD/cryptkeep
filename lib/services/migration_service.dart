import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import 'crypto_service.dart';

class MigrationResult {
  final Uint8List key;
  final int failedEntries;
  final int failedCategories;

  MigrationResult({required this.key, this.failedEntries = 0, this.failedCategories = 0});

  bool get hadFailures => failedEntries > 0 || failedCategories > 0;
}

class MigrationService {
  /// Check if the current user needs migration (no crypto_salt in metadata).
  static bool needsMigration() {
    final meta = supabase.auth.currentUser?.userMetadata;
    return meta == null || meta['crypto_salt'] == null;
  }

  /// Migrate a legacy user:
  /// 1. Decrypt all vault entries + categories with the legacy key
  /// 2. Generate a new random salt and derive a new key
  /// 3. Re-encrypt everything with the new key
  /// 4. Store the new salt and key check in user metadata
  /// 5. Update the Supabase auth password to the derived auth password
  ///
  /// Returns MigrationResult with the new key and failure counts.
  static Future<MigrationResult> migrate(String masterPassword, String email, {bool changeAuthPassword = true}) async {
    final userId = supabase.auth.currentUser!.id;
    final legacyKey = CryptoService.deriveKeyLegacy(masterPassword, userId);

    // Also try existing migrated key (if partially migrated with old 600k iterations)
    final existingMeta = supabase.auth.currentUser?.userMetadata;
    Uint8List? existingKey;
    if (existingMeta != null && existingMeta['crypto_salt'] != null) {
      final existingSalt = base64.decode(existingMeta['crypto_salt'] as String);
      final existingIterations = existingMeta['key_iterations'] as int? ?? 600000;
      existingKey = CryptoService.deriveKey(masterPassword, existingSalt, iterations: existingIterations);
    }

    // Generate new crypto params with default iterations
    final newSalt = CryptoService.generateSalt(16);
    final newIterations = CryptoService.defaultKeyIterations;
    final newKey = CryptoService.deriveKey(masterPassword, newSalt, iterations: newIterations);
    final keyCheck = CryptoService.createKeyCheck(newKey);

    int failedEntries = 0;
    int failedCategories = 0;

    // Re-encrypt vault entries
    final vaultRows = await supabase
        .from('vault_entries')
        .select()
        .eq('user_id', userId);

    for (final row in vaultRows) {
      try {
        final data = row['encrypted_data'] as String;
        String plaintext;
        try {
          plaintext = CryptoService.decrypt(data, legacyKey);
        } catch (_) {
          try {
            if (existingKey != null) {
              plaintext = CryptoService.decrypt(data, existingKey);
            } else {
              rethrow;
            }
          } catch (_) {
            plaintext = CryptoService.decrypt(data, newKey);
          }
        }
        final reEncrypted = CryptoService.encrypt(plaintext, newKey);
        await supabase.from('vault_entries').update({
          'encrypted_data': reEncrypted,
        }).eq('id', row['id']).eq('user_id', userId);
      } catch (e) {
        failedEntries++;
        if (kDebugMode) debugPrint('Migration failed for entry ${row['id']}: $e');
      }
    }

    // Re-encrypt categories
    final catRows = await supabase
        .from('categories')
        .select()
        .eq('user_id', userId);

    for (final row in catRows) {
      try {
        final name = row['name'] as String;
        String plainName;
        try {
          plainName = CryptoService.decrypt(name, legacyKey);
        } catch (_) {
          try {
            if (existingKey != null) {
              plainName = CryptoService.decrypt(name, existingKey);
            } else {
              rethrow;
            }
          } catch (_) {
            try {
              plainName = CryptoService.decrypt(name, newKey);
            } catch (_) {
              plainName = name;
            }
          }
        }
        final reEncrypted = CryptoService.encrypt(plainName, newKey);
        await supabase.from('categories').update({
          'name': reEncrypted,
        }).eq('id', row['id']).eq('user_id', userId);
      } catch (e) {
        failedCategories++;
        if (kDebugMode) debugPrint('Migration failed for category ${row['id']}: $e');
      }
    }

    // Update metadata first (always works without reauthentication)
    await supabase.auth.updateUser(UserAttributes(
      data: {
        'crypto_salt': base64.encode(newSalt),
        'key_check': keyCheck,
        'key_iterations': newIterations,
      },
    ));

    // Only change auth password when migrating from legacy/v1
    if (changeAuthPassword) {
      try {
        final newAuthPassword = CryptoService.deriveAuthPassword(masterPassword, email);
        await supabase.auth.updateUser(UserAttributes(password: newAuthPassword));
      } catch (_) {
        // Password change may require reauthentication — metadata is already saved
      }
    }

    return MigrationResult(
      key: newKey,
      failedEntries: failedEntries,
      failedCategories: failedCategories,
    );
  }

  /// For already-migrated users, get the encryption key from metadata.
  static Uint8List getKey(String masterPassword) {
    final meta = supabase.auth.currentUser!.userMetadata!;
    final salt = base64.decode(meta['crypto_salt'] as String);
    final iterations = meta['key_iterations'] as int? ?? 600000;
    return CryptoService.deriveKey(masterPassword, salt, iterations: iterations);
  }

  /// Check if user needs re-migration to lower iterations (e.g. 600k → 100k).
  static bool needsIterationUpdate() {
    final meta = supabase.auth.currentUser?.userMetadata;
    if (meta == null || meta['crypto_salt'] == null) return false;
    final iterations = meta['key_iterations'] as int? ?? 600000;
    return iterations != CryptoService.defaultKeyIterations;
  }

  /// Verify master password against stored key check.
  static bool verifyPassword(Uint8List key) {
    final meta = supabase.auth.currentUser?.userMetadata;
    if (meta == null || meta['key_check'] == null) return true;
    return CryptoService.verifyKeyCheck(meta['key_check'] as String, key);
  }
}
