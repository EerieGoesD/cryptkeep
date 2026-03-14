import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/vault_entry.dart';
import '../../providers/app_state.dart';
import '../../services/vault_service.dart';
import '../../utils/app_notification.dart';
import 'password_generator_dialog.dart';

class AddEditEntryScreen extends StatefulWidget {
  final VaultEntry? entry;

  const AddEditEntryScreen({super.key, this.entry});

  @override
  State<AddEditEntryScreen> createState() => _AddEditEntryScreenState();
}

class _AddEditEntryScreenState extends State<AddEditEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _notesCtrl;
  String _category = '';
  bool _loading = false;
  bool _obscurePassword = true;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _passwordCtrl = TextEditingController(text: e?.password ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final key = context.read<AppState>().encryptionKey;
      final now = DateTime.now();

      final entry = _isEditing
          ? widget.entry!.copyWith(
              title: _titleCtrl.text.trim(),
              username: _usernameCtrl.text.trim(),
              password: _passwordCtrl.text,
              url: _urlCtrl.text.trim(),
              notes: _notesCtrl.text.trim(),
              category: _category,
            )
          : VaultEntry(
              id: const Uuid().v4(),
              title: _titleCtrl.text.trim(),
              username: _usernameCtrl.text.trim(),
              password: _passwordCtrl.text,
              url: _urlCtrl.text.trim(),
              notes: _notesCtrl.text.trim(),
              category: _category,
              createdAt: now,
              updatedAt: now,
            );

      final saved = _isEditing
          ? await VaultService.update(entry, key)
          : await VaultService.create(entry, key);

      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      showAppNotification(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _promptNewCategory() async {
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

    if (name == null || name.isEmpty || !mounted) return;

    final cat = await context.read<AppState>().addCategory(name);
    setState(() => _category = cat.id);
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;

    // Ensure selected category id is still valid (e.g. after deletion)
    final validId = categories.any((c) => c.id == _category) ? _category : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Entry' : 'New Entry'),
        actions: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('Save',
                      style: TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username / Email',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: const Color(0xFF94A3B8)),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Password is required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Generate password',
                    child: IconButton(
                      icon: const Icon(Icons.auto_awesome,
                          color: Color(0xFF8B5CF6)),
                      onPressed: () async {
                        final generated =
                            await PasswordGeneratorDialog.show(context);
                        if (generated != null) {
                          _passwordCtrl.text = generated;
                          setState(() => _obscurePassword = false);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL (optional)',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: validId.isEmpty ? null : validId,
                      decoration: const InputDecoration(
                        labelText: 'Category (optional)',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                      dropdownColor: const Color(0xFF1A1A2E),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('None')),
                        ...categories.map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() => _category = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'New category',
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF8B5CF6)),
                    onPressed: _promptNewCategory,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
