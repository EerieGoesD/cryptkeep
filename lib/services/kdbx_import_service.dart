import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kdbx/kdbx.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_entry.dart';

class KdbxImportService {
  /// Parses a KDBX file and returns a list of [VaultEntry] objects.
  /// Throws if the password is wrong or the file is invalid.
  static Future<List<VaultEntry>> parse(
      Uint8List fileBytes, String password) async {
    final credentials = Credentials(ProtectedValue.fromString(password));
    final kdbxFormat = KdbxFormat();
    final file = await kdbxFormat.read(fileBytes, credentials);

    final entries = <VaultEntry>[];
    final now = DateTime.now();

    for (final entry in file.body.rootGroup.getAllEntries()) {
      final title =
          entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? 'Untitled';
      final username =
          entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '';
      final password =
          entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '';
      final url = entry.getString(KdbxKeyCommon.URL)?.getText() ?? '';

      // Try standard 'Notes' key, then iterate all string keys as fallback
      var notes = entry.getString(KdbxKey('Notes'))?.getText() ?? '';
      if (notes.isEmpty) {
        for (final se in entry.stringEntries) {
          final keyLower = se.key.key.toLowerCase();
          if (keyLower == 'notes') {
            notes = se.value?.getText() ?? '';
            break;
          }
        }
      }

      if (kDebugMode) {
        debugPrint('KDBX Import [$title] keys: ${entry.stringEntries.map((e) => e.key.key).toList()}');
        debugPrint('KDBX Import [$title] notes: "$notes"');
      }

      entries.add(VaultEntry(
        id: const Uuid().v4(),
        title: title,
        username: username,
        password: password,
        url: url,
        notes: notes,
        category: '',
        createdAt: now,
        updatedAt: now,
      ));
    }

    return entries;
  }
}
