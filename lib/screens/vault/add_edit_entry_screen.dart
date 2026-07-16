import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/totp_config.dart';
import '../../models/vault_entry.dart';
import '../../providers/app_state.dart';
import '../../services/premium_service.dart';
import '../../services/totp_service.dart';
import '../../services/vault_service.dart';
import '../../utils/app_notification.dart';
import 'password_generator_dialog.dart';
import 'premium_screen.dart';
import 'totp_scan_screen.dart';

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
  TotpConfig? _totp;
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
    _totp = e?.totp;
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

  /// Two-factor setup. Scanning the site's QR code is the main path; typing
  /// the key by hand is the fallback for when there is no camera or the code
  /// is on the same screen you are reading.
  Widget _buildTotpField() {
    if (!PremiumService.isPremium()) {
      return _totpBox(
        child: Row(
          children: [
            const Icon(Icons.lock_clock_outlined,
                color: Color(0xFF94A3B8), size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Two-factor code',
                      style: TextStyle(fontSize: 14)),
                  SizedBox(height: 2),
                  Text(
                    'Replace your authenticator app. Included with Pro.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
              ),
              child: const Text('Get Pro'),
            ),
          ],
        ),
      );
    }

    final totp = _totp;
    if (totp != null) {
      // Already set up: confirm it, and say if the site uses unusual settings
      // so it is obvious we kept them.
      final unusual = <String>[
        if (totp.digits != 6) '${totp.digits} digits',
        if (totp.period != 30) 'every ${totp.period}s',
        if (totp.algorithm.toUpperCase() != 'SHA1') totp.algorithm,
      ].join(', ');

      return _totpBox(
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF8B5CF6), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Two-factor code is set up',
                      style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    unusual.isEmpty
                        ? (totp.issuer.isNotEmpty ? totp.issuer : 'Ready to use')
                        : unusual,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: Color(0xFF94A3B8)),
              tooltip: 'Remove',
              onPressed: () => setState(() => _totp = null),
            ),
          ],
        ),
      );
    }

    return _totpBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_outlined,
                  color: Color(0xFF8B5CF6), size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Two-factor code (optional)',
                    style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'If this site asks for a code from an authenticator app, add it '
            'here and CryptKeep will show the code for you.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanTotp,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR code'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _enterTotpByHand,
                child: const Text('Enter key'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totpBox({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: child,
      );

  Future<void> _scanTotp() async {
    final config = await Navigator.of(context).push<TotpConfig>(
      MaterialPageRoute(builder: (_) => const TotpScanScreen()),
    );
    if (config != null && mounted) {
      setState(() => _totp = config);
      showAppNotification(context, 'Two-factor code added');
    }
  }

  /// For when the QR cannot be scanned, e.g. setting it up on this same phone.
  Future<void> _enterTotpByHand() async {
    final ctrl = TextEditingController();
    String? error;

    final config = await showDialog<TotpConfig>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Enter setup key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'On the site, look for "enter this key instead" or "can\'t '
                'scan" next to the QR code, and paste what it shows.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'e.g. JBSW Y3DP EHPK 3PXP',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                // Reject it here rather than save a key that can never produce
                // a code and fail silently at the site.
                final parsed = TotpService.parse(ctrl.text);
                if (parsed == null) {
                  setDialogState(() => error = 'That key is not valid');
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();

    if (config != null && mounted) {
      setState(() => _totp = config);
    }
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
              totp: _totp,
              clearTotp: _totp == null,
            )
          : VaultEntry(
              id: const Uuid().v4(),
              title: _titleCtrl.text.trim(),
              username: _usernameCtrl.text.trim(),
              password: _passwordCtrl.text,
              url: _urlCtrl.text.trim(),
              notes: _notesCtrl.text.trim(),
              category: _category,
              totp: _totp,
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
      showAppNotification(context, 'Failed to save. Please try again.');
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
              _buildTotpField(),
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
                      initialValue: validId.isEmpty ? null : validId,
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
