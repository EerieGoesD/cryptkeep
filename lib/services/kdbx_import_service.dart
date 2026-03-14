import 'dart:typed_data';

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
      final notes =
          entry.getString(KdbxKey('Notes'))?.getText() ?? '';

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
