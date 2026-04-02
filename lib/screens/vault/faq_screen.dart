import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  // ── Replace with your actual Buy Me a Coffee URL ──────────────────────────
  static const _buyMeCoffeeUrl = 'https://buymeacoffee.com/eeriegoesd';

  static const _faqs = [
    (
      q: 'What is CryptKeep?',
      a: 'CryptKeep is a zero-knowledge password manager. '
          'Your passwords are encrypted on your device before being sent to the server. '
          'Only you, with your master password, can ever decrypt and read them.',
    ),
    (
      q: 'How does sync work?',
      a: 'Every change (add, edit, delete) is saved to the database instantly. '
          'When you open the app on any device and unlock the vault, '
          'it fetches the latest data automatically. '
          'Use the sync button to manually pull the latest from the server '
          'if you need to refresh after changes made on another device.',
    ),
    (
      q: 'Are my changes saved automatically?',
      a: 'Yes. Every action (adding, editing, or deleting an entry) is '
          'saved to the database instantly. '
          'There is no save button to press and no manual upload needed.',
    ),
    (
      q: 'Is my master password stored anywhere?',
      a: 'No. Your master password never leaves your device and is never stored anywhere. '
          'It is used to derive an encryption key in memory, '
          'which is discarded when you lock the vault or close the app.',
    ),
    (
      q: 'What encryption does CryptKeep use?',
      a: 'AES-256-GCM with authenticated encryption and a random nonce per entry. '
          'The encryption key is derived from your master password using '
          'PBKDF2-SHA256 with up to 600,000 iterations and a cryptographically random salt.',
    ),
    (
      q: 'How do I import from KeePass?',
      a: '1. Open the menu and tap "Import KeePass (.kdbx)".\n'
          '2. Select your .kdbx file.\n'
          '3. Enter the master password for that KeePass database.\n'
          '4. Tap Import. All entries will be imported and re-encrypted '
          'with your CryptKeep key.',
    ),
    (
      q: 'How do I export my vault?',
      a: '1. Open the menu and tap "Export KeePass (.kdbx)".\n'
          '2. Choose a password to protect the exported file.\n'
          '3. Pick a location to save it.\n\n'
          'The exported .kdbx file can be opened in KeePass, KeePassXC, '
          'or any compatible password manager.',
    ),
    (
      q: 'How do I enable Two-Factor Authentication?',
      a: '1. Go to Settings > Two-Factor Authentication.\n'
          '2. Tap "Enable 2FA".\n'
          '3. Scan the QR code with your authenticator app '
          '(Google Authenticator, Authy, etc.).\n'
          '4. Enter the 6-digit code to verify.\n\n'
          'Once enabled, you will need to enter a code from your authenticator app '
          'each time you sign in. You can disable 2FA from the same settings page.',
    ),
    (
      q: 'How do I bulk delete entries?',
      a: 'Long-press any entry to enter selection mode. '
          'Tap entries to select them, tap "All" to select everything, '
          'then tap the delete icon in the top bar.',
    ),
    (
      q: 'What happens if I forget my master password?',
      a: 'There is no recovery option. Your master password is never stored anywhere. '
          'If you lose it, your vault cannot be decrypted. '
          'Keep your master password in a safe place.',
    ),
    (
      q: 'Can I use CryptKeep on multiple devices?',
      a: 'Yes. Install the app on any device, log in with the same account '
          'and master password, and your vault will be available instantly.',
    ),
    (
      q: 'Can I permanently delete my account?',
      a: 'Yes. Go to Settings and tap "Delete Account." '
          'This will permanently remove your account and all vault data from the server. '
          'This action cannot be undone.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ & About')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Header ──────────────────────────────────────────────────────
          const Icon(Icons.lock_outline, size: 52, color: Color(0xFF8B5CF6)),
          const SizedBox(height: 12),
          const Text(
            'CryptKeep',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Zero-knowledge password manager',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 4),
          Center(
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://eeriegoesd.com/'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text.rich(
                TextSpan(
                  text: 'Made by ',
                  style: TextStyle(color: Color(0xFF94A3B8), letterSpacing: 1),
                  children: [
                    TextSpan(
                      text: 'EERIE',
                      style: TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Buy Me a Coffee ──────────────────────────────────────────────
          Center(
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_buyMeCoffeeUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Text('☕', style: TextStyle(fontSize: 18)),
              label: const Text('Buy Me a Coffee'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                side: const BorderSide(color: Color(0xFF8B5CF6)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── FAQ ──────────────────────────────────────────────────────────
          const Text(
            'Frequently Asked Questions',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),

          ...List.generate(_faqs.length, (i) {
            final item = _faqs[i];
            return _FaqTile(question: item.q, answer: item.a);
          }),

          const SizedBox(height: 32),
          const Text(
            'v1.0.0 · Built with Flutter & Supabase',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF8B5CF6),
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                Text(
                  widget.answer,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      height: 1.5,
                      fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
