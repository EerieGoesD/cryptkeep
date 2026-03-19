import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pointycastle/export.dart';

class CryptoService {
  // ───────────────────────────────────────────────────────
  // Auth Password Derivation — NEVER sends master password
  // Produces a separate password for Supabase auth so the
  // master password never leaves the device.
  // ───────────────────────────────────────────────────────
  static String deriveAuthPassword(String masterPassword, String email) {
    final salt = Uint8List.fromList(utf8.encode('${email.trim().toLowerCase()}:auth-v2'));
    final password = Uint8List.fromList(utf8.encode(masterPassword.trim()));
    final params = Pbkdf2Parameters(salt, 100000, 32);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
    return base64.encode(pbkdf2.process(password));
  }

  // Legacy auth password (single SHA-256) for migration from v1
  static String deriveAuthPasswordLegacy(String masterPassword, String email) {
    final input = utf8.encode('${masterPassword.trim()}:${email.trim().toLowerCase()}:auth');
    final digest = SHA256Digest().process(Uint8List.fromList(input));
    return base64.encode(digest);
  }

  // ───────────────────────────────────────────────────────
  // Key Derivation — PBKDF2-SHA256
  // Salt = cryptographically random 16 bytes
  // Iterations configurable (stored in user metadata)
  // ───────────────────────────────────────────────────────
  static int get defaultKeyIterations => kIsWeb ? 100000 : 600000;

  static Uint8List deriveKey(String masterPassword, Uint8List salt, {int? iterations}) {
    iterations ??= defaultKeyIterations;
    final password = Uint8List.fromList(utf8.encode(masterPassword));
    final params = Pbkdf2Parameters(salt, iterations, 32);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
    return pbkdf2.process(password);
  }

  // Legacy key derivation for migration (userId salt, 100k iterations)
  static Uint8List deriveKeyLegacy(String masterPassword, String userId) {
    final salt = Uint8List.fromList(utf8.encode(userId));
    final password = Uint8List.fromList(utf8.encode(masterPassword));
    final params = Pbkdf2Parameters(salt, 100000, 32);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
    return pbkdf2.process(password);
  }

  // ───────────────────────────────────────────────────────
  // Generate cryptographically random bytes
  // ───────────────────────────────────────────────────────
  static Uint8List generateSalt([int length = 16]) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  // ───────────────────────────────────────────────────────
  // Key Check — encrypt a known value to verify master password
  // ───────────────────────────────────────────────────────
  static const _keyCheckPlaintext = 'cryptkeep-key-check-v2';

  static String createKeyCheck(Uint8List keyBytes) {
    return encrypt(_keyCheckPlaintext, keyBytes);
  }

  static bool verifyKeyCheck(String encryptedCheck, Uint8List keyBytes) {
    try {
      return decrypt(encryptedCheck, keyBytes) == _keyCheckPlaintext;
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────────────────────────────────────
  // Encrypt — AES-256-GCM with random 12-byte nonce
  // Output: "v2:<base64_nonce>:<base64_ciphertext+tag>"
  // ───────────────────────────────────────────────────────
  static String encrypt(String plaintext, Uint8List keyBytes) {
    final nonce = generateSalt(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(keyBytes), 128, nonce, Uint8List(0)));
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);
    return 'v2:${base64.encode(nonce)}:${base64.encode(output)}';
  }

  // ───────────────────────────────────────────────────────
  // Decrypt — supports both v2 (GCM) and legacy (CBC)
  // ───────────────────────────────────────────────────────
  static String decrypt(String encryptedText, Uint8List keyBytes) {
    if (encryptedText.startsWith('v2:')) {
      return _decryptGCM(encryptedText, keyBytes);
    }
    return _decryptCBCLegacy(encryptedText, keyBytes);
  }

  static String _decryptGCM(String encryptedText, Uint8List keyBytes) {
    final parts = encryptedText.split(':');
    if (parts.length != 3) throw const FormatException('Invalid v2 format');
    final nonce = base64.decode(parts[1]);
    final data = base64.decode(parts[2]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(keyBytes), 128, nonce, Uint8List(0)));
    return utf8.decode(cipher.process(Uint8List.fromList(data)));
  }

  static String _decryptCBCLegacy(String encryptedText, Uint8List keyBytes) {
    final parts = encryptedText.split(':');
    if (parts.length != 2) throw const FormatException('Invalid format');
    final iv = enc.IV.fromBase64(parts[0]);
    final encrypted = enc.Encrypted.fromBase64(parts[1]);
    final key = enc.Key(keyBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(encrypted, iv: iv);
  }
}
