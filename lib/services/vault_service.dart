import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app.dart';
import '../models/vault_entry.dart';
import '../services/crypto_service.dart';
import '../services/vault_cache_service.dart';

class VaultService {
  static const _table = 'vault_entries';

  // ─── Fetch all entries for the current user, decrypted ───
  static Future<List<VaultEntry>> fetchAll(Uint8List key) async {
    final userId = supabase.auth.currentUser!.id;

    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final entries = <VaultEntry>[];
    final encryptedRows = <String>[];
    for (final row in rows) {
      final encryptedData = row['encrypted_data'] as String;
      try {
        final plaintext = CryptoService.decrypt(encryptedData, key);
        final json = jsonDecode(plaintext) as Map<String, dynamic>;
        entries.add(VaultEntry.fromJson(json));
        encryptedRows.add(encryptedData);
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to decrypt entry ${row['id']}: $e');
        // Skip entries that can't be decrypted (wrong key from migration)
      }
    }

    // Rebuild the offline copy from the server on every load. Writes clear it
    // rather than patch it, so a stale copy can never outlive a change - the
    // passkey flow writes without ever going through the vault screen.
    await VaultCacheService.save(encryptedRows);
    return entries;
  }

  // ─── Create a new entry ───
  static Future<VaultEntry> create(VaultEntry entry, Uint8List key) async {
    final userId = supabase.auth.currentUser!.id;
    final plaintext = jsonEncode(entry.toJson());
    final encryptedData = CryptoService.encrypt(plaintext, key);

    await supabase.from(_table).insert({
      'id': entry.id,
      'user_id': userId,
      'encrypted_data': encryptedData,
      'created_at': entry.createdAt.toIso8601String(),
      'updated_at': entry.updatedAt.toIso8601String(),
    });

    await VaultCacheService.clear();
    return entry;
  }

  // ─── Update an existing entry ───
  static Future<VaultEntry> update(VaultEntry entry, Uint8List key) async {
    final plaintext = jsonEncode(entry.toJson());
    final encryptedData = CryptoService.encrypt(plaintext, key);

    final userId = supabase.auth.currentUser!.id;
    await supabase.from(_table).update({
      'encrypted_data': encryptedData,
      'updated_at': entry.updatedAt.toIso8601String(),
    }).eq('id', entry.id).eq('user_id', userId);

    await VaultCacheService.clear();
    return entry;
  }

  // ─── Delete an entry ───
  static Future<void> delete(String id) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from(_table).delete().eq('id', id).eq('user_id', userId);
    await VaultCacheService.clear();
  }
}
