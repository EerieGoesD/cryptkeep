import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../app.dart';
import '../models/vault_entry.dart';
import '../services/crypto_service.dart';

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
    for (final row in rows) {
      try {
        final plaintext = CryptoService.decrypt(row['encrypted_data'] as String, key);
        final json = jsonDecode(plaintext) as Map<String, dynamic>;
        entries.add(VaultEntry.fromJson(json));
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to decrypt entry ${row['id']}: $e');
        // Skip entries that can't be decrypted (wrong key from migration)
      }
    }
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

    return entry;
  }

  // ─── Delete an entry ───
  static Future<void> delete(String id) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from(_table).delete().eq('id', id).eq('user_id', userId);
  }
}
