import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/kdbx_import_service.dart';
import '../../services/vault_service.dart';
import '../../utils/app_notification.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  String? _fileName;
  Uint8List? _fileBytes;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    setState(() {
      _fileName = result.files.single.name;
      _fileBytes = result.files.single.bytes;
    });
  }

  Future<void> _import() async {
    if (_fileBytes == null) {
      showAppNotification(context, 'Please select a .kdbx file first');
      return;
    }

    setState(() => _loading = true);

    try {
      final entries = await KdbxImportService.parse(
        _fileBytes!,
        _passwordCtrl.text,
      );

      if (!mounted) return;
      final key = context.read<AppState>().encryptionKey;

      int imported = 0;
      for (final entry in entries) {
        await VaultService.create(entry, key);
        imported++;
      }

      if (!mounted) return;
      Navigator.of(context).pop(imported);
    } catch (e) {
      if (!mounted) return;
      showAppNotification(
        context,
        e.toString().contains('invalid')
            ? 'Wrong password or invalid file'
            : 'Import failed: $e',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from KeePass')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import a .kdbx database',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select your KeePass file and enter its master password. '
              'All entries will be imported and encrypted with your CryptKeep key.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _fileBytes != null
                        ? const Color(0xFF8B5CF6)
                        : const Color(0xFF2A2A3E),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _fileBytes != null
                          ? Icons.check_circle_outline
                          : Icons.upload_file_outlined,
                      size: 40,
                      color: _fileBytes != null
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _fileBytes != null ? _fileName! : 'Tap to select .kdbx file',
                      style: TextStyle(
                        color: _fileBytes != null
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'KeePass Master Password',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF94A3B8),
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Import Entries'),
                  ),
          ],
        ),
      ),
    );
  }
}
