import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart';

class CryptoService {
  // ───────────────────────────────────────────────────────
  // Key Derivation — PBKDF2-SHA256, 100,000 iterations
  // Salt = userId (stable, unique per user)
  // ───────────────────────────────────────────────────────
  static Uint8List deriveKey(String masterPassword, String userId) {
    final salt = Uint8List.fromList(utf8.encode(userId));
    final password = Uint8List.fromList(utf8.encode(masterPassword));

    final params = Pbkdf2Parameters(salt, 100000, 32);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);

    return pbkdf2.process(password);
  }

  // ───────────────────────────────────────────────────────
  // Encrypt — AES-256-CBC with random IV
  // Output format: "<base64_iv>:<base64_ciphertext>"
  // ───────────────────────────────────────────────────────
  static String encrypt(String plaintext, Uint8List keyBytes) {
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  // ───────────────────────────────────────────────────────
  // Decrypt
  // ───────────────────────────────────────────────────────
  static String decrypt(String encryptedText, Uint8List keyBytes) {
    final parts = encryptedText.split(':');
    if (parts.length != 2) throw const FormatException('Invalid encrypted format');

    final iv = enc.IV.fromBase64(parts[0]);
    final encrypted = enc.Encrypted.fromBase64(parts[1]);
    final key = enc.Key(keyBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    return encrypter.decrypt(encrypted, iv: iv);
  }
}
