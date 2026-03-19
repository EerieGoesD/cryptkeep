import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../app.dart';
import '../models/category.dart';
import 'crypto_service.dart';

class CategoryService {
  static const _table = 'categories';

  static Future<List<Category>> fetchAll(Uint8List key) async {
    final rows = await supabase
        .from(_table)
        .select()
        .order('created_at', ascending: true);
    return rows.map((r) {
      final encryptedName = r['name'] as String;
      String name;
      try {
        name = CryptoService.decrypt(encryptedName, key);
      } catch (_) {
        // Fallback for unencrypted legacy categories
        name = encryptedName;
      }
      return Category(id: r['id'] as String, name: name);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static Future<Category> create(String name, Uint8List key) async {
    final userId = supabase.auth.currentUser!.id;
    final id = const Uuid().v4();
    final encryptedName = CryptoService.encrypt(name.trim(), key);
    await supabase.from(_table).insert({
      'id': id,
      'user_id': userId,
      'name': encryptedName,
    });
    return Category(id: id, name: name.trim());
  }

  static Future<void> rename(String id, String newName, Uint8List key) async {
    final encryptedName = CryptoService.encrypt(newName.trim(), key);
    await supabase.from(_table).update({'name': encryptedName}).eq('id', id);
  }

  static Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }
}
