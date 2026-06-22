import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Tiny footer showing the real installed app version per platform
/// (Android version code, MSIX package version, web build version, etc.).
class AppVersionFooter extends StatefulWidget {
  /// Optional text appended after the version, e.g. "Built with Flutter".
  final String? suffix;

  const AppVersionFooter({super.key, this.suffix});

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  String _text = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber;
      var version = build.isNotEmpty && build != '0'
          ? 'v${info.version} ($build)'
          : 'v${info.version}';
      if (widget.suffix != null) version = '$version · ${widget.suffix}';
      if (mounted) setState(() => _text = version);
    } catch (_) {
      // Leave the footer empty if version info is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return const SizedBox.shrink();
    return Text(
      _text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
    );
  }
}
