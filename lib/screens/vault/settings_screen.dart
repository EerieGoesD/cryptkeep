import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../providers/app_state.dart';
import '../auth/login_screen.dart';
import 'faq_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _deleting = false;

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    context.read<AppState>().lock();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all vault data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final email = supabase.auth.currentUser?.email ?? '';
    final controller = TextEditingController();
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Are you sure?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type "$email" to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Enter your email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().toLowerCase() == email.toLowerCase()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Delete my account',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (finalConfirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await supabase.rpc('delete_own_account');

      if (!mounted) return;
      context.read<AppState>().lock();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete account. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _deleting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Deleting account...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'ACCOUNT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _tile(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: email,
                ),
                _tile(
                  icon: Icons.logout,
                  title: 'Sign out',
                  onTap: _signOut,
                ),
                const SizedBox(height: 28),
                const Text(
                  'SUPPORT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _tile(
                  icon: Icons.help_outline,
                  title: 'FAQ & About',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FaqScreen()),
                  ),
                ),
                _tile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => launchUrl(
                    Uri.parse('https://eeriegoesd.com/privacy-policy/cryptkeep/'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _tile(
                  icon: Icons.mail_outline,
                  title: 'Need help?',
                  onTap: () => launchUrl(
                    Uri.parse('mailto:eeriegoesd@gmail.com?subject=CryptKeep%20Support'),
                  ),
                ),
                _tile(
                  icon: Icons.bug_report_outlined,
                  title: 'Report an Issue',
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/EerieGoesD/cryptkeep/issues'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'DANGER ZONE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _tile(
                  icon: Icons.delete_forever,
                  title: 'Delete account',
                  subtitle: 'Permanently delete all data',
                  titleColor: Colors.redAccent,
                  onTap: _deleteAccount,
                ),
                const SizedBox(height: 40),
                const Text(
                  'v1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: titleColor ?? const Color(0xFF8B5CF6), size: 22),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: titleColor,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12))
            : null,
        trailing: onTap != null
            ? const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20)
            : null,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
