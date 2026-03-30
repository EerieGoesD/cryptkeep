import 'package:flutter/foundation.dart';
import 'package:kdbx/kdbx.dart';

import '../models/category.dart' as models;
import '../models/vault_entry.dart';

class KdbxExportService {
  /// Creates a KDBX file from the given entries and categories,
  /// protected with [password]. Returns the file bytes.
  static Future<Uint8List> export({
    required List<VaultEntry> entries,
    required List<models.Category> categories,
    required String password,
  }) async {
    final credentials = Credentials(ProtectedValue.fromString(password));
    KdbxFormat.dartWebWorkaround = kIsWeb;
    final kdbxFormat = KdbxFormat();
    final file = kdbxFormat.create(credentials, 'CryptKeep Export');
    final rootGroup = file.body.rootGroup;

    // Build category groups using the DAO extension
    final catMap = <String, KdbxGroup>{};
    for (final cat in categories) {
      final group = file.createGroup(parent: rootGroup, name: cat.name);
      catMap[cat.id] = group;
    }

    for (final e in entries) {
      final parent = (e.category.isNotEmpty && catMap.containsKey(e.category))
          ? catMap[e.category]!
          : rootGroup;

      final kdbxEntry = KdbxEntry.create(file, parent);
      kdbxEntry.setString(
          KdbxKeyCommon.TITLE, PlainValue(e.title));
      kdbxEntry.setString(
          KdbxKeyCommon.USER_NAME, PlainValue(e.username));
      kdbxEntry.setString(
          KdbxKeyCommon.PASSWORD, ProtectedValue.fromString(e.password));
      kdbxEntry.setString(KdbxKeyCommon.URL, PlainValue(e.url));
      kdbxEntry.setString(KdbxKey('Notes'), PlainValue(e.notes));

      parent.addEntry(kdbxEntry);
    }

    return file.save();
  }
}
