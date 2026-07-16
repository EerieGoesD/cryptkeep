import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/totp_config.dart';
import '../../services/totp_service.dart';

/// Points the camera at the QR code a site shows when turning on two-factor.
/// This is how nearly everyone sets these up; typing the key by hand is the
/// fallback, not the main path.
///
/// Pops with a [TotpConfig] on success, or null if cancelled.
class TotpScanScreen extends StatefulWidget {
  const TotpScanScreen({super.key});

  @override
  State<TotpScanScreen> createState() => _TotpScanScreenState();
}

class _TotpScanScreenState extends State<TotpScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// The camera fires repeatedly on the same code; only the first counts.
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final config = TotpService.parse(raw);
      if (config != null) {
        _handled = true;
        Navigator.of(context).pop(config);
        return;
      }

      // A QR code that is not a two-factor setup: say so instead of just
      // sitting there looking broken.
      if (mounted) {
        setState(() => _error = raw.toLowerCase().startsWith('otpauth://hotp')
            ? 'That is a counter-based code, which CryptKeep cannot show.'
            : 'That QR code is not a two-factor setup code.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Aiming frame.
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF8B5CF6), width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F1D1D),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Point the camera at the QR code the site is showing you',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
