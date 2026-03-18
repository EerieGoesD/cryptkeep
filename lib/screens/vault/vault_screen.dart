import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../models/category.dart';
import '../../models/vault_entry.dart';
import '../../providers/app_state.dart';
import '../../services/vault_service.dart';
import '../auth/login_screen.dart';
import 'add_edit_entry_screen.dart';
import 'entry_detail_screen.dart';
import 'import_screen.dart';
import 'faq_screen.dart';
import 'manage_categories_screen.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<VaultEntry> _entries = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String? _selectedCategoryId; // null = All

  // Selection mode
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  // Collapsed groups (set of category ids / '' for uncategorised)
  final Set<String> _collapsed = {};

  bool _syncing = false;
  DateTime? _lastSync;
  String? _notification;
  Timer? _notifTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notifTimer?.cancel();
    super.dispose();
  }

  void _showNotification(String message) {
    _notifTimer?.cancel();
    setState(() => _notification = message);
    _notifTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notification = null);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final key = context.read<AppState>().encryptionKey;
      final entries = await VaultService.fetchAll(key);
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      _showNotification('Failed to load vault: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    final now = DateTime.now();
    if (_lastSync != null && now.difference(_lastSync!).inSeconds < 30) {
      final secs = 30 - now.difference(_lastSync!).inSeconds;
      _showNotification('Wait ${secs}s before syncing again');
      return;
    }
    setState(() => _syncing = true);
    try {
      await _load();
      _lastSync = DateTime.now();
      if (!mounted) return;
      _showNotification('Vault synced');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<VaultEntry> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    return _entries.where((e) {
      final matchesSearch = q.isEmpty ||
          e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.url.toLowerCase().contains(q);
      final matchesCategory =
          _selectedCategoryId == null || e.category == _selectedCategoryId;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    context.read<AppState>().lock();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _deleteEntry(VaultEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Entry'),
        content: Text('Delete "${entry.title}"? This cannot be undone.'),
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
    await VaultService.delete(entry.id);
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Entries'),
        content: Text(
            'Delete $count selected ${count == 1 ? 'entry' : 'entries'}? This cannot be undone.'),
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

    final idsToDelete = Set<String>.from(_selected);
    setState(() {
      _entries.removeWhere((e) => idsToDelete.contains(e.id));
      _selected.clear();
    });

    for (final id in idsToDelete) {
      await VaultService.delete(id);
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() => _selected.addAll(_filtered.map((e) => e.id)));
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  // Build grouped data: list of (categoryLabel, categoryId, entries)
  List<({String label, String id, List<VaultEntry> entries})> _buildGroups(
      List<VaultEntry> entries, List<Category> categories) {
    final catMap = {for (final c in categories) c.id: c.name};
    final Map<String, List<VaultEntry>> grouped = {};

    for (final e in entries) {
      final key = e.category.isNotEmpty && catMap.containsKey(e.category)
          ? e.category
          : '';
      grouped.putIfAbsent(key, () => []).add(e);
    }

    final result =
        <({String label, String id, List<VaultEntry> entries})>[];

    // Known categories first (sorted by name)
    for (final cat in categories) {
      if (grouped.containsKey(cat.id)) {
        result.add((label: cat.name, id: cat.id, entries: grouped[cat.id]!));
      }
    }

    // Uncategorised last
    if (grouped.containsKey('') && grouped['']!.isNotEmpty) {
      result.add(
          (label: 'Uncategorised', id: '', entries: grouped['']!));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;
    final filtered = _filtered;
    final groups = _buildGroups(filtered, categories);

    return Scaffold(
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: Column(
        children: [
          if (!_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  prefixIcon:
                      Icon(Icons.search, color: Color(0xFF94A3B8)),
                ),
              ),
            ),
          if (!_selectionMode && categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                children: [
                  _categoryChip(null, 'All'),
                  ...categories.map((c) => _categoryChip(c.id, c.name)),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _countItems(groups),
                          itemBuilder: (_, i) =>
                              _buildItem(i, groups, categories),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final created = await Navigator.of(context).push<VaultEntry>(
                  MaterialPageRoute(
                      builder: (_) => const AddEditEntryScreen()),
                );
                if (created != null) {
                  setState(() => _entries.insert(0, created));
                }
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: Row(
        children: [
          const Text('CryptKeep',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          if (_notification != null)
            Expanded(
              child: Text(
                _notification!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFE2E8F0),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
      actions: [
        _syncing
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                icon: const Icon(Icons.sync, size: 22),
                tooltip: 'Sync (pull from server)',
                onPressed: _sync,
              ),
        IconButton(
          icon: const Icon(Icons.help_outline, size: 22),
          tooltip: 'FAQ & About',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FaqScreen()),
          ),
        ),
        PopupMenuButton<String>(
          color: const Color(0xFF1A1A2E),
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'import') {
              final count = await Navigator.of(context).push<int>(
                MaterialPageRoute(builder: (_) => const ImportScreen()),
              );
              if (count != null && count > 0) {
                await _load();
                if (!mounted) return;
                _showNotification('Imported $count entries');
              }
            } else if (value == 'categories') {
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ManageCategoriesScreen()),
              );
              setState(() {});
            } else if (value == 'signout') {
              await _signOut();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'import',
                child: Row(children: [
                  Icon(Icons.download_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Import KeePass (.kdbx)'),
                ])),
            PopupMenuItem(
                value: 'categories',
                child: Row(children: [
                  Icon(Icons.folder_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Manage Categories'),
                ])),
            PopupMenuDivider(),
            PopupMenuItem(
                value: 'signout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 10),
                  Text('Sign out'),
                ])),
          ],
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        TextButton(
          onPressed: _selectAll,
          child: const Text('All',
              style: TextStyle(color: Color(0xFF8B5CF6))),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          tooltip: 'Delete selected',
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  // ─── Grouped list helpers ───────────────────────────────────────────────────

  /// Total item count: one header + entries per group (if not collapsed).
  int _countItems(
      List<({String label, String id, List<VaultEntry> entries})> groups) {
    int count = 0;
    for (final g in groups) {
      count++; // header
      if (!_collapsed.contains(g.id)) count += g.entries.length;
    }
    return count;
  }

  Widget _buildItem(
      int index,
      List<({String label, String id, List<VaultEntry> entries})> groups,
      List<Category> categories) {
    int cursor = 0;
    for (final g in groups) {
      if (index == cursor) return _buildGroupHeader(g.label, g.id, g.entries.length);
      cursor++;
      if (!_collapsed.contains(g.id)) {
        for (final entry in g.entries) {
          if (index == cursor) return _buildEntryTile(entry, categories);
          cursor++;
        }
      }
    }
    return const SizedBox.shrink();
  }

  Widget _buildGroupHeader(String label, String id, int count) {
    final isCollapsed = _collapsed.contains(id);
    return InkWell(
      onTap: () => setState(() {
        if (isCollapsed) {
          _collapsed.remove(id);
        } else {
          _collapsed.add(id);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(
              isCollapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryTile(VaultEntry entry, List<Category> categories) {
    final isSelected = _selected.contains(entry.id);

    return InkWell(
      onTap: () async {
        if (_selectionMode) {
          _toggleSelect(entry.id);
        } else {
          final updated = await Navigator.of(context).push<VaultEntry>(
            MaterialPageRoute(
                builder: (_) => EntryDetailScreen(entry: entry)),
          );
          if (updated != null && mounted) {
            setState(() {
              final i = _entries.indexWhere((e) => e.id == updated.id);
              if (i != -1) _entries[i] = updated;
            });
          }
        }
      },
      onLongPress: () => _toggleSelect(entry.id),
      child: Container(
        color: isSelected
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
            : Colors.transparent,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            // Checkbox or avatar
            if (_selectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelect(entry.id),
                activeColor: const Color(0xFF8B5CF6),
                side: const BorderSide(color: Color(0xFF94A3B8)),
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFF2A2A3E),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.title.isNotEmpty
                      ? entry.title[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            const SizedBox(width: 12),
            // Title + username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (entry.username.isNotEmpty)
                    Text(entry.username,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Edit / delete popup (only when not selecting)
            if (!_selectionMode)
              PopupMenuButton<String>(
                color: const Color(0xFF1A1A2E),
                icon: const Icon(Icons.more_vert,
                    color: Color(0xFF94A3B8), size: 18),
                onSelected: (value) async {
                  if (value == 'edit') {
                    final updated =
                        await Navigator.of(context).push<VaultEntry>(
                      MaterialPageRoute(
                          builder: (_) =>
                              AddEditEntryScreen(entry: entry)),
                    );
                    if (updated != null) {
                      setState(() {
                        final i =
                            _entries.indexWhere((e) => e.id == updated.id);
                        if (i != -1) _entries[i] = updated;
                      });
                    }
                  } else if (value == 'delete') {
                    await _deleteEntry(entry);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Colors.redAccent))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String? categoryId, String label) {
    final selected = _selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedCategoryId = categoryId),
        selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
        checkmarkColor: const Color(0xFF8B5CF6),
        labelStyle: TextStyle(
          color: selected
              ? const Color(0xFF8B5CF6)
              : const Color(0xFF94A3B8),
          fontSize: 13,
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        side: BorderSide(
          color:
              selected ? const Color(0xFF8B5CF6) : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final searching =
        _searchCtrl.text.isNotEmpty || _selectedCategoryId != null;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
              searching
                  ? Icons.search_off
                  : Icons.lock_open_outlined,
              size: 56,
              color: const Color(0xFF8B5CF6)),
          const SizedBox(height: 16),
          Text(
            searching ? 'No results found' : 'Your vault is empty',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (!searching) ...[
            const SizedBox(height: 8),
            const Text('Tap + to add your first password.',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ],
        ],
      ),
    );
  }
}
