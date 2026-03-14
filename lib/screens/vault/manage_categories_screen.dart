import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';

class ManageCategoriesScreen extends StatelessWidget {
  const ManageCategoriesScreen({super.key});

  Future<void> _addCategory(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('New Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    await context.read<AppState>().addCategory(name);
  }

  Future<void> _renameCategory(
      BuildContext context, String id, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Rename Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    await context.read<AppState>().renameCategory(id, name);
  }

  Future<void> _deleteCategory(
      BuildContext context, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Category'),
        content: Text(
            'Delete "$name"? Entries in this category won\'t be deleted, just uncategorised.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    await context.read<AppState>().deleteCategory(id);
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add category',
            onPressed: () => _addCategory(context),
          ),
        ],
      ),
      body: categories.isEmpty
          ? const Center(
              child: Text('No categories yet. Tap + to create one.',
                  style: TextStyle(color: Color(0xFF94A3B8))),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: categories.length,
              itemBuilder: (_, i) {
                final cat = categories[i];
                return ListTile(
                  leading: const Icon(Icons.folder_outlined,
                      color: Color(0xFF8B5CF6)),
                  title: Text(cat.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: Color(0xFF94A3B8)),
                        tooltip: 'Rename',
                        onPressed: () =>
                            _renameCategory(context, cat.id, cat.name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Colors.redAccent),
                        tooltip: 'Delete',
                        onPressed: () =>
                            _deleteCategory(context, cat.id, cat.name),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
