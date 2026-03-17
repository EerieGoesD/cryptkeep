import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vault_entry.dart';
import '../../utils/app_notification.dart';
import 'add_edit_entry_screen.dart';

class EntryDetailScreen extends StatefulWidget {
  final VaultEntry entry;

  const EntryDetailScreen({super.key, required this.entry});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late VaultEntry _entry;
  bool _passwordVisible = false;
  bool _wasModified = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    showAppNotification(context, '$label copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<VaultEntry>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_wasModified ? _entry : null);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_entry.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () async {
              final updated = await Navigator.of(context).push<VaultEntry>(
                MaterialPageRoute(
                    builder: (_) => AddEditEntryScreen(entry: _entry)),
              );
              if (updated != null) {
                setState(() {
                  _entry = updated;
                  _wasModified = true;
                });
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          if (_entry.username.isNotEmpty)
            _buildField(
              label: 'Username / Email',
              value: _entry.username,
              icon: Icons.person_outline,
              onCopy: () => _copy(_entry.username, 'Username'),
            ),
          if (_entry.password.isNotEmpty)
            _buildPasswordField(),
          if (_entry.url.isNotEmpty)
            _buildField(
              label: 'URL',
              value: _entry.url,
              icon: Icons.link,
              onCopy: () => _copy(_entry.url, 'URL'),
            ),
          if (_entry.notes.isNotEmpty)
            _buildField(
              label: 'Notes',
              value: _entry.notes,
              icon: Icons.notes_outlined,
            ),
          const SizedBox(height: 24),
          _buildMeta(),
        ],
      ),
    ));
  }

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFF2A2A3E),
          child: Text(
            _entry.title.isNotEmpty ? _entry.title[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.bold,
                fontSize: 22),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            _entry.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onCopy,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8B5CF6), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18, color: Color(0xFF94A3B8)),
              tooltip: 'Copy',
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_outlined, color: Color(0xFF8B5CF6), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Password',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  _passwordVisible ? _entry.password : '••••••••••••',
                  style: const TextStyle(fontSize: 15, letterSpacing: 1),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
                _passwordVisible ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: const Color(0xFF94A3B8)),
            tooltip: _passwordVisible ? 'Hide' : 'Show',
            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18, color: Color(0xFF94A3B8)),
            tooltip: 'Copy',
            onPressed: () => _copy(_entry.password, 'Password'),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta() {
    String fmt(DateTime dt) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Created: ${fmt(_entry.createdAt)}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 4),
        Text('Updated: ${fmt(_entry.updatedAt)}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      ],
    );
  }
}
