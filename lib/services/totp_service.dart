import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/totp_config.dart';

/// Generates the rotating two-factor codes (TOTP, RFC 6238) - the same codes
/// Google Authenticator produces.
///
/// Entirely local: a code is derived from a stored seed and the clock, so
/// nothing is sent anywhere and it works offline. The seed lives inside the
/// vault entry, encrypted like any password.
class TotpService {
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Decodes a base32 seed (RFC 4648). Accepts lower case, padding, spaces and
  /// dashes, because that is how sites print them.
  static Uint8List decodeBase32(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp(r'[=\s-]'), '');
    if (clean.isEmpty) throw const FormatException('Empty secret');

    var bits = 0;
    var value = 0;
    final out = <int>[];
    for (final char in clean.split('')) {
      final index = _base32Alphabet.indexOf(char);
      if (index < 0) {
        throw FormatException('Not a valid key (bad character "$char")');
      }
      value = (value << 5) | index;
      bits += 5;
      if (bits >= 8) {
        out.add((value >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  /// True if [secret] can actually produce codes, for validating input.
  static bool isValidSecret(String secret) {
    try {
      return decodeBase32(secret).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// The current code for [config].
  static String generate(TotpConfig config, {DateTime? at}) {
    final key = decodeBase32(config.secret);
    final seconds =
        (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    final counter = seconds ~/ config.period;

    final message = Uint8List(8)
      ..buffer.asByteData().setUint64(0, counter, Endian.big);
    final hash = Hmac(_hashFor(config.algorithm), key).convert(message).bytes;

    // Dynamic truncation (RFC 4226): the low 4 bits of the last byte pick
    // where to read 4 bytes from, and the top bit is dropped so the result is
    // always positive.
    final offset = hash[hash.length - 1] & 0x0F;
    final binary = ((hash[offset] & 0x7F) << 24) |
        ((hash[offset + 1] & 0xFF) << 16) |
        ((hash[offset + 2] & 0xFF) << 8) |
        (hash[offset + 3] & 0xFF);

    var modulus = 1;
    for (var i = 0; i < config.digits; i++) {
      modulus *= 10;
    }
    return (binary % modulus).toString().padLeft(config.digits, '0');
  }

  /// Seconds until the current code is replaced, for the countdown ring.
  static int secondsRemaining(TotpConfig config, [DateTime? at]) {
    final seconds =
        (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return config.period - (seconds % config.period);
  }

  static Hash _hashFor(String algorithm) {
    switch (algorithm.toUpperCase().replaceAll('-', '')) {
      case 'SHA256':
        return sha256;
      case 'SHA512':
        return sha512;
      default:
        return sha1;
    }
  }

  /// Reads whatever the user gave us: a full `otpauth://` link (what a QR code
  /// holds), or a bare key typed in by hand. Returns null if it is unusable.
  ///
  /// The link carries the site's real settings, so a site using 8 digits or a
  /// 60 second window works instead of silently producing wrong codes.
  static TotpConfig? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.toLowerCase().startsWith('otpauth://')) {
      return _parseUri(trimmed);
    }

    // A bare key: assume the defaults, which is all a bare key can mean.
    final secret = trimmed.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!isValidSecret(secret)) return null;
    return TotpConfig(secret: secret);
  }

  static TotpConfig? _parseUri(String uri) {
    try {
      final parsed = Uri.parse(uri);

      // Counter-based (hotp) codes do not advance on a clock, so they cannot
      // be shown as a rotating code. Refuse rather than show a stuck number.
      if (parsed.host.toLowerCase() != 'totp') return null;

      final params = parsed.queryParameters;
      final secret =
          (params['secret'] ?? '').replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
      if (secret.isEmpty || !isValidSecret(secret)) return null;

      // Label is "Issuer:account" or just "account"; the issuer parameter wins
      // when both are present, as the spec recommends.
      final label = parsed.pathSegments.isNotEmpty
          ? Uri.decodeComponent(parsed.pathSegments.first)
          : '';
      var issuer = params['issuer'] ?? '';
      var account = label;
      if (label.contains(':')) {
        final parts = label.split(':');
        if (issuer.isEmpty) issuer = parts.first.trim();
        account = parts.sublist(1).join(':').trim();
      }

      final digits = int.tryParse(params['digits'] ?? '') ?? 6;
      final period = int.tryParse(params['period'] ?? '') ?? 30;

      return TotpConfig(
        secret: secret,
        // Only 6 and 8 exist in practice; anything else is a broken link.
        digits: (digits == 6 || digits == 8) ? digits : 6,
        period: period > 0 ? period : 30,
        algorithm: params['algorithm'] ?? 'SHA1',
        issuer: issuer,
        account: account,
      );
    } catch (_) {
      return null;
    }
  }
}
