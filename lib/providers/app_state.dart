import 'dart:typed_data';

import 'package:flutter/foundation.dart' hide Category;

import '../models/category.dart';
import '../services/category_service.dart';

// Holds the derived encryption key and categories in memory for the session.
// Never persisted to disk — user must re-enter master password on restart.
class AppState extends ChangeNotifier {
  Uint8List? _encryptionKey;
  List<Category> _categories = [];

  bool get isUnlocked => _encryptionKey != null;

  Uint8List get encryptionKey {
    assert(_encryptionKey != null, 'Vault is locked');
    return _encryptionKey!;
  }

  List<Category> get categories => List.unmodifiable(_categories);

  Future<void> unlock(Uint8List key) async {
    _encryptionKey = key;
    await _loadCategories();
    notifyListeners();
  }

  void lock() {
    _encryptionKey = null;
    _categories = [];
    notifyListeners();
  }

  Future<void> _loadCategories() async {
    _categories = await CategoryService.fetchAll();
  }

  Future<void> reloadCategories() async {
    await _loadCategories();
    notifyListeners();
  }

  Future<Category> addCategory(String name) async {
    final cat = await CategoryService.create(name);
    _categories = [..._categories, cat]
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return cat;
  }

  Future<void> renameCategory(String id, String newName) async {
    await CategoryService.rename(id, newName);
    _categories = _categories
        .map((c) => c.id == id ? Category(id: id, name: newName) : c)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    await CategoryService.delete(id);
    _categories = _categories.where((c) => c.id != id).toList();
    notifyListeners();
  }
}
