import 'package:flutter/material.dart';

import '../../models/vault_entry.dart';
import '../../services/password_health_service.dart';

class PasswordHealthScreen extends StatefulWidget {
  final List<VaultEntry> entries;

  const PasswordHealthScreen({super.key, required this.entries});

  @override
  State<PasswordHealthScreen> createState() => _PasswordHealthScreenState();
}

class _PasswordHealthScreenState extends State<PasswordHealthScreen> {
  late final HealthReport _report;
  Map<String, int> _breaches = {};
  bool _checkingBreaches = false;
  bool _breachesChecked = false;

  @override
  void initState() {
    super.initState();
    _report = PasswordHealthService.analyze(widget.entries);
    _runBreachCheck();
  }

  Future<void> _runBreachCheck() async {
    setState(() => _checkingBreaches = true);
    try {
      final results = await PasswordHealthService.checkBreaches(widget.entries);
      if (!mounted) return;
      setState(() {
        _breaches = results;
        _breachesChecked = true;
      });
    } finally {
      if (mounted) setState(() => _checkingBreaches = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password Health')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildScoreCard(),
          const SizedBox(height: 24),
          if (_breaches.isNotEmpty) ...[
            _buildSection(
              'Breached Passwords',
              Icons.warning_amber_rounded,
              Colors.redAccent,
              _breaches.entries.map((b) {
                final entry = widget.entries.firstWhere(
                  (e) => e.id == b.key,
                  orElse: () => widget.entries.first,
                );
                return _issueTile(
                  entry.title,
                  'Found in ${_formatCount(b.value)} data breaches',
                  Colors.redAccent,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (_checkingBreaches && _breaches.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Checking for breached passwords...',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                ],
              ),
            ),
          if (_report.weakPasswords.isNotEmpty) ...[
            _buildSection(
              'Weak Passwords',
              Icons.shield_outlined,
              Colors.orangeAccent,
              _report.weakPasswords
                  .map((i) => _issueTile(i.entry.title, i.issue, Colors.orangeAccent))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (_report.reusedPasswords.isNotEmpty) ...[
            _buildSection(
              'Reused Passwords',
              Icons.copy_outlined,
              Colors.amberAccent,
              _report.reusedPasswords.map((g) {
                final names = g.entries.map((e) => e.title).join(', ');
                return _issueTile(
                  '${g.entries.length} entries share the same password',
                  names,
                  Colors.amberAccent,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (_report.oldPasswords.isNotEmpty) ...[
            _buildSection(
              'Old Passwords',
              Icons.schedule,
              const Color(0xFF94A3B8),
              _report.oldPasswords
                  .map((i) => _issueTile(i.entry.title, i.issue, const Color(0xFF94A3B8)))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (_report.totalIssues == 0 && _breaches.isEmpty && _breachesChecked)
            const Center(
              child: Column(
                children: [
                  SizedBox(height: 20),
                  Icon(Icons.verified, size: 48, color: Color(0xFF22C55E)),
                  SizedBox(height: 12),
                  Text('All passwords look good!',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreCard() {
    final score = _report.score;
    final color = score >= 80
        ? const Color(0xFF22C55E)
        : score >= 50
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: const Color(0xFF2A2A3E),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score >= 80 ? 'Good health' : score >= 50 ? 'Needs attention' : 'At risk',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.entries.length} entries analyzed',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
                if (_breaches.isNotEmpty)
                  Text(
                    '${_breaches.length} breached',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, Color color, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              '$title (${children.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _issueTile(String title, String subtitle, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            title.isNotEmpty ? title[0].toUpperCase() : '?',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
