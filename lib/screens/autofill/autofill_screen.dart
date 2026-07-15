import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';

import '../../app.dart';
import '../../models/vault_entry.dart';
import '../../services/biometric_service.dart';
import '../../services/migration_service.dart';
import '../../services/vault_cache_service.dart';
import '../../services/vault_service.dart';

/// Minimal app shown when another app asks CryptKeep to fill a login.
/// Runs via the `autofillEntryPoint` Dart entrypoint from AutofillActivity.
class AutofillApp extends StatelessWidget {
  const AutofillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptKeep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          surface: Color(0xFF12121E),
          onSurface: Color(0xFFE2E8F0),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A12),
          foregroundColor: Color(0xFFE2E8F0),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AutofillScreen(),
    );
  }
}

class AutofillScreen extends StatefulWidget {
  const AutofillScreen({super.key});

  @override
  State<AutofillScreen> createState() => _AutofillScreenState();
}

class _AutofillScreenState extends State<AutofillScreen> {
  final _passwordCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _query = '';
  AutofillMetadata? _meta;
  List<VaultEntry> _all = [];
  List<VaultEntry> _matches = [];
  bool _loading = true;
  bool _needsPassword = false;
  bool _showAll = false;
  bool _interactive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _meta = await AutofillService().autofillMetadata;
      _interactive = await AutofillService().fillRequestedInteractive;
    } catch (_) {
      // Metadata is best-effort; without it we just show all entries.
    }

    final email = supabase.auth.currentUser?.email;
    if (email == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Open CryptKeep and sign in first.';
      });
      return;
    }

    // Prefer biometrics; fall back to the master password.
    if (await BiometricService.isEnabledFor(email)) {
      final key = await BiometricService.unlock();
      if (key != null) {
        await _loadVault(key);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _needsPassword = true;
    });
  }

  Future<void> _unlockWithPassword() async {
    if (_passwordCtrl.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final key = await MigrationService.getKeyAsync(_passwordCtrl.text);
      if (!MigrationService.verifyPassword(key)) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _needsPassword = true;
          _error = 'Incorrect master password';
        });
        return;
      }
      await _loadVault(key);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsPassword = true;
        _error = 'Could not unlock the vault';
      });
    }
  }

  Future<void> _loadVault(Uint8List key) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _needsPassword = false;
      _error = null;
    });
    try {
      // Prefer the local copy: autofill is launched from another app and may
      // have no connection, and a network round trip here is a visible stall.
      final entries =
          await VaultCacheService.load(key) ?? await VaultService.fetchAll(key);
      final matches = entries.where(_matchesRequest).toList();

      // Android authenticated the whole fill response here, so it expects a
      // FillResponse back and shows its own picker: hand it the datasets and
      // finish. Only the interactive flow ("Pick a different entry") is
      // allowed to return one chosen dataset, which is what our list does.
      if (!_interactive) {
        final offer = matches.isNotEmpty ? matches : entries;
        await AutofillService().resultWithDatasets(
          offer
              .map((e) => PwDataset(
                    label: e.title,
                    username: e.username,
                    password: e.password,
                  ))
              .toList(),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _all = entries;
        _matches = matches;
        _showAll = matches.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your vault';
      });
    }
  }

  // Generic tokens that say nothing about which app a package belongs to.
  static const _ignoredTokens = {
    'com', 'net', 'org', 'www', 'android', 'app', 'apps', 'mobile', 'client',
    'io', 'co', 'inc', 'ltd', 'the',
  };

  String? _host(String url) {
    if (url.isEmpty) return null;
    try {
      var u = url;
      if (!u.contains('://')) u = 'https://$u';
      final h = Uri.parse(u).host.toLowerCase();
      return h.isEmpty ? null : h;
    } catch (_) {
      return null;
    }
  }

  /// The recognisable part of a host, used to match entries that have no URL
  /// saved: letterboxd.com -> letterboxd, accounts.google.com -> google,
  /// example.co.uk -> example.
  String? _siteName(String host) {
    final parts =
        host.split('.').where((p) => p.isNotEmpty && p != 'www').toList();
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first.length > 3 ? parts.first : null;
    var i = parts.length - 2;
    var name = parts[i];
    // Step over short public suffix pieces, e.g. the "co" in example.co.uk.
    if (name.length <= 3 && i > 0) name = parts[i - 1];
    return name.length > 3 ? name : null;
  }

  /// Matches an entry against the requesting website domain or app package.
  bool _matchesRequest(VaultEntry e) {
    final meta = _meta;
    if (meta == null) return false;
    final host = _host(e.url);
    final title = e.title.toLowerCase();

    // Website: compare hosts (allowing subdomains either way).
    for (final d in meta.webDomains) {
      final dom = d.domain.toLowerCase();
      if (dom.isEmpty) continue;
      if (host != null &&
          (host == dom || host.endsWith('.$dom') || dom.endsWith('.$host'))) {
        return true;
      }
      // The URL field is optional and most people leave it blank, so fall
      // back to the site name against the title.
      final name = _siteName(dom);
      if (name != null && title.contains(name)) return true;
    }

    // App: pull meaningful tokens out of the package name
    // (e.g. com.instagram.android -> "instagram") and look for them.
    for (final p in meta.packageNames) {
      final tokens = p
          .toLowerCase()
          .split('.')
          .where((t) => t.length > 3 && !_ignoredTokens.contains(t));
      for (final t in tokens) {
        if (host != null && host.contains(t)) return true;
        if (title.contains(t)) return true;
      }
    }
    return false;
  }

  Future<void> _fill(VaultEntry e) async {
    await AutofillService().resultWithDataset(
      label: e.title,
      username: e.username,
      password: e.password,
    );
  }

  String get _requestLabel {
    final meta = _meta;
    if (meta == null) return '';
    if (meta.webDomains.isNotEmpty) return meta.webDomains.first.domain;
    if (meta.packageNames.isNotEmpty) return meta.packageNames.first;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CryptKeep')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _needsPassword
              ? _buildUnlock()
              : _error != null
                  ? _buildError()
                  : _buildList(_showAll ? _all : _matches),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );

  Widget _buildUnlock() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Color(0xFF8B5CF6)),
              const SizedBox(height: 16),
              const Text('Unlock to fill',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (_requestLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('for $_requestLabel',
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Master Password'),
                onSubmitted: (_) => _unlockWithPassword(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFFBBF24), fontSize: 13)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _unlockWithPassword,
                  child: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<VaultEntry> all) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.username.toLowerCase().contains(q) ||
                e.url.toLowerCase().contains(q))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _showAll
                  ? 'All entries'
                  : 'Matches for ${_requestLabel.isEmpty ? "this app" : _requestLabel}',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search entries',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                      q.isEmpty ? 'No entries found' : 'No matches for "$_query"',
                      style: const TextStyle(color: Color(0xFF94A3B8))),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final e = list[i];
                    return ListTile(
                      leading:
                          const Icon(Icons.key, color: Color(0xFF8B5CF6)),
                      title: Text(e.title),
                      subtitle: e.username.isNotEmpty
                          ? Text(e.username,
                              style:
                                  const TextStyle(color: Color(0xFF94A3B8)))
                          : null,
                      onTap: () => _fill(e),
                    );
                  },
                ),
        ),
        if (!_showAll && _all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: const Text('Show all entries'),
            ),
          ),
      ],
    );
  }
}
