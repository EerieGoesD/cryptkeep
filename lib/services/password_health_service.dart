import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../app.dart';
import '../models/vault_entry.dart';

class PasswordIssue {
  final VaultEntry entry;
  final String issue;
  final String severity; // 'critical', 'warning', 'info'

  const PasswordIssue({
    required this.entry,
    required this.issue,
    required this.severity,
  });
}

class ReusedGroup {
  final List<VaultEntry> entries;
  ReusedGroup(this.entries);
}

class HealthReport {
  final List<PasswordIssue> weakPasswords;
  final List<ReusedGroup> reusedPasswords;
  final List<PasswordIssue> oldPasswords;
  final List<PasswordIssue> emptyPasswords;
  final int totalEntries;

  const HealthReport({
    required this.weakPasswords,
    required this.reusedPasswords,
    required this.oldPasswords,
    required this.emptyPasswords,
    required this.totalEntries,
  });

  int get totalIssues =>
      weakPasswords.length +
      reusedPasswords.fold<int>(0, (sum, g) => sum + g.entries.length) +
      oldPasswords.length +
      emptyPasswords.length;

  int get score {
    if (totalEntries == 0) return 100;
    final issueRatio = totalIssues / totalEntries;
    return (100 * (1 - issueRatio).clamp(0.0, 1.0)).round();
  }
}

class PasswordHealthService {
  /// Analyzes all entries and returns a health report.
  static HealthReport analyze(List<VaultEntry> entries) {
    final weak = <PasswordIssue>[];
    final old = <PasswordIssue>[];
    final empty = <PasswordIssue>[];
    final passwordMap = <String, List<VaultEntry>>{};

    final now = DateTime.now();

    for (final e in entries) {
      // Empty passwords
      if (e.password.isEmpty) {
        empty.add(PasswordIssue(
          entry: e,
          issue: 'No password set',
          severity: 'info',
        ));
        continue;
      }

      // Weak password checks
      final issues = <String>[];
      if (e.password.length < 8) {
        issues.add('Too short (${e.password.length} chars)');
      }
      if (!e.password.contains(RegExp(r'[A-Z]'))) {
        issues.add('No uppercase letters');
      }
      if (!e.password.contains(RegExp(r'[0-9]'))) {
        issues.add('No numbers');
      }
      if (!e.password.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{};:,.<>?/\\|`~"\x27]'))) {
        issues.add('No special characters');
      }
      if (e.password.length < 12 && issues.length >= 2) {
        weak.add(PasswordIssue(
          entry: e,
          issue: issues.join(', '),
          severity: issues.any((i) => i.contains('Too short')) ? 'critical' : 'warning',
        ));
      } else if (issues.length >= 3) {
        weak.add(PasswordIssue(
          entry: e,
          issue: issues.join(', '),
          severity: 'warning',
        ));
      }

      // Track for reuse detection
      passwordMap.putIfAbsent(e.password, () => []).add(e);

      // Old passwords (> 6 months)
      if (now.difference(e.updatedAt).inDays > 180) {
        final months = now.difference(e.updatedAt).inDays ~/ 30;
        old.add(PasswordIssue(
          entry: e,
          issue: 'Not updated in $months months',
          severity: months > 12 ? 'critical' : 'warning',
        ));
      }
    }

    // Reused passwords
    final reused = passwordMap.entries
        .where((e) => e.value.length > 1)
        .map((e) => ReusedGroup(e.value))
        .toList();

    return HealthReport(
      weakPasswords: weak,
      reusedPasswords: reused,
      oldPasswords: old,
      emptyPasswords: empty,
      totalEntries: entries.length,
    );
  }

  /// Checks passwords against Have I Been Pwned via the server-side
  /// breach-check Edge Function. Premium status is verified server-side.
  /// Returns a map of entry ID to breach count.
  static Future<Map<String, int>> checkBreaches(List<VaultEntry> entries) async {
    final hashes = <Map<String, String>>[];
    final seen = <String, String>{}; // hash -> first entry id (dedup)

    for (final e in entries) {
      if (e.password.isEmpty) continue;

      final hash = sha1.convert(utf8.encode(e.password)).toString().toUpperCase();
      if (seen.containsKey(hash)) continue;
      seen[hash] = e.id;

      hashes.add({
        'id': e.id,
        'prefix': hash.substring(0, 5),
        'suffix': hash.substring(5),
      });
    }

    if (hashes.isEmpty) return {};

    try {
      final response = await supabase.functions.invoke(
        'breach-check',
        body: {'hashes': hashes},
      );

      if (response.status != 200) return {};

      final data = response.data as Map<String, dynamic>;
      final results = <String, int>{};

      final serverResults = data['results'] as Map<String, dynamic>? ?? {};
      for (final entry in serverResults.entries) {
        results[entry.key] = (entry.value as num).toInt();
      }

      // Map duplicated passwords to the same breach count
      for (final e in entries) {
        if (e.password.isEmpty) continue;
        final hash = sha1.convert(utf8.encode(e.password)).toString().toUpperCase();
        final originalId = seen[hash];
        if (originalId != null && originalId != e.id && results.containsKey(originalId)) {
          results[e.id] = results[originalId]!;
        }
      }

      return results;
    } catch (_) {
      return {};
    }
  }
}
