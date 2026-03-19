import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_notification.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  /// Shows the dialog and returns the chosen password, or null if dismissed.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const PasswordGeneratorDialog(),
    );
  }

  @override
  State<PasswordGeneratorDialog> createState() =>
      _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = '0123456789';
  static const _symbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

  int _length = 20;
  bool _useUpper = true;
  bool _useLower = true;
  bool _useDigits = true;
  bool _useSymbols = true;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    final charset = [
      if (_useUpper) _upper,
      if (_useLower) _lower,
      if (_useDigits) _digits,
      if (_useSymbols) _symbols,
    ].join();

    if (charset.isEmpty) {
      setState(() => _password = '');
      return;
    }

    final rng = Random.secure();
    setState(() {
      _password =
          List.generate(_length, (_) => charset[rng.nextInt(charset.length)])
              .join();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Password Generator'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Generated password display
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _password.isEmpty ? '—' : _password,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        letterSpacing: 1.2,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        size: 18, color: Color(0xFF94A3B8)),
                    tooltip: 'Copy',
                    onPressed: _password.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(
                                ClipboardData(text: _password));
                            showAppNotification(context, 'Copied — clipboard clears in 30s');
                            Timer(const Duration(seconds: 30), () {
                              Clipboard.setData(const ClipboardData(text: ''));
                            });
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Length slider
            Row(
              children: [
                const Text('Length: ',
                    style: TextStyle(color: Color(0xFF94A3B8))),
                Text('$_length',
                    style: const TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _length.toDouble(),
              min: 8,
              max: 64,
              divisions: 56,
              activeColor: const Color(0xFF8B5CF6),
              inactiveColor: const Color(0xFF2A2A3E),
              onChanged: (v) {
                setState(() => _length = v.round());
                _generate();
              },
            ),
            const SizedBox(height: 8),

            // Character set toggles
            _toggle('Uppercase (A–Z)', _useUpper, (v) {
              setState(() => _useUpper = v);
              _generate();
            }),
            _toggle('Lowercase (a–z)', _useLower, (v) {
              setState(() => _useLower = v);
              _generate();
            }),
            _toggle('Digits (0–9)', _useDigits, (v) {
              setState(() => _useDigits = v);
              _generate();
            }),
            _toggle('Symbols (!@#…)', _useSymbols, (v) {
              setState(() => _useSymbols = v);
              _generate();
            }),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Regenerate'),
          onPressed: _generate,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              _password.isEmpty ? null : () => Navigator.pop(context, _password),
          child: const Text('Use'),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF8B5CF6),
        ),
      ],
    );
  }
}
