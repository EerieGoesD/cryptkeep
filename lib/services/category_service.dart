import 'package:uuid/uuid.dart';

import '../app.dart';
import '../models/category.dart';

class CategoryService {
  static const _table = 'categories';

  static Future<List<Category>> fetchAll() async {
    final rows = await supabase
        .from(_table)
        .select()
        .order('name', ascending: true);
    return rows.map((r) => Category.fromJson(r)).toList();
  }

  static Future<Category> create(String name) async {
    final userId = supabase.auth.currentUser!.id;
    final id = const Uuid().v4();
    await supabase.from(_table).insert({
      'id': id,
      'user_id': userId,
      'name': name.trim(),
    });
    return Category(id: id, name: name.trim());
  }

  static Future<void> rename(String id, String newName) async {
    await supabase.from(_table).update({'name': newName.trim()}).eq('id', id);
  }

  static Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }
}
