import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptkeep/services/crypto_service.dart';

void main() {
  group('CryptoService', () {
    late Uint8List testKey;
    late Uint8List testSalt;

    setUp(() {
      // Fixed 32-byte key for deterministic tests
      testKey = Uint8List.fromList(List.generate(32, (i) => i));
      testSalt = Uint8List.fromList(List.generate(16, (i) => i + 100));
    });

    // ── Encrypt / Decrypt round-trip ──

    test('encrypt then decrypt returns original plaintext', () {
      const plaintext = 'hello CryptKeep!';
      final encrypted = CryptoService.encrypt(plaintext, testKey);
      final decrypted = CryptoService.decrypt(encrypted, testKey);
      expect(decrypted, equals(plaintext));
    });

    test('encrypt produces v2 format', () {
      final encrypted = CryptoService.encrypt('test', testKey);
      expect(encrypted, startsWith('v2:'));
      final parts = encrypted.split(':');
      expect(parts.length, equals(3));
    });

    test('encrypt produces unique ciphertext each call (random nonce)', () {
      const plaintext = 'same input';
      final a = CryptoService.encrypt(plaintext, testKey);
      final b = CryptoService.encrypt(plaintext, testKey);
      expect(a, isNot(equals(b)));
    });

    test('decrypt with wrong key throws', () {
      final encrypted = CryptoService.encrypt('secret', testKey);
      final wrongKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      expect(() => CryptoService.decrypt(encrypted, wrongKey), throwsA(anything));
    });

    test('encrypt and decrypt handles empty string', () {
      final encrypted = CryptoService.encrypt('', testKey);
      final decrypted = CryptoService.decrypt(encrypted, testKey);
      expect(decrypted, equals(''));
    });

    test('encrypt and decrypt handles unicode', () {
      const plaintext = 'p\u00e4ssw\u00f6rd \ud83d\udd12 \u6d4b\u8bd5';
      final encrypted = CryptoService.encrypt(plaintext, testKey);
      final decrypted = CryptoService.decrypt(encrypted, testKey);
      expect(decrypted, equals(plaintext));
    });

    test('encrypt and decrypt handles long input', () {
      final plaintext = 'a' * 10000;
      final encrypted = CryptoService.encrypt(plaintext, testKey);
      final decrypted = CryptoService.decrypt(encrypted, testKey);
      expect(decrypted, equals(plaintext));
    });

    // ── Key Derivation ──

    test('deriveKey produces 32-byte key', () {
      final key = CryptoService.deriveKey('password', testSalt, iterations: 1000);
      expect(key.length, equals(32));
    });

    test('deriveKey is deterministic with same inputs', () {
      final a = CryptoService.deriveKey('password', testSalt, iterations: 1000);
      final b = CryptoService.deriveKey('password', testSalt, iterations: 1000);
      expect(a, equals(b));
    });

    test('deriveKey differs with different passwords', () {
      final a = CryptoService.deriveKey('password1', testSalt, iterations: 1000);
      final b = CryptoService.deriveKey('password2', testSalt, iterations: 1000);
      expect(a, isNot(equals(b)));
    });

    test('deriveKey differs with different salts', () {
      final salt2 = Uint8List.fromList(List.generate(16, (i) => i + 200));
      final a = CryptoService.deriveKey('password', testSalt, iterations: 1000);
      final b = CryptoService.deriveKey('password', salt2, iterations: 1000);
      expect(a, isNot(equals(b)));
    });

    // ── Auth Password Derivation ──

    test('deriveAuthPassword is deterministic', () {
      final a = CryptoService.deriveAuthPassword('master', 'user@example.com');
      final b = CryptoService.deriveAuthPassword('master', 'user@example.com');
      expect(a, equals(b));
    });

    test('deriveAuthPassword is case-insensitive for email', () {
      final a = CryptoService.deriveAuthPassword('master', 'User@Example.COM');
      final b = CryptoService.deriveAuthPassword('master', 'user@example.com');
      expect(a, equals(b));
    });

    test('deriveAuthPassword differs from deriveKey (key separation)', () {
      final authPass = CryptoService.deriveAuthPassword('master', 'user@test.com');
      final encKey = CryptoService.deriveKey('master', testSalt, iterations: 100000);
      expect(authPass, isNot(equals(base64.encode(encKey))));
    });

    test('deriveAuthPasswordLegacy differs from v2', () {
      final v1 = CryptoService.deriveAuthPasswordLegacy('master', 'user@test.com');
      final v2 = CryptoService.deriveAuthPassword('master', 'user@test.com');
      expect(v1, isNot(equals(v2)));
    });

    // ── Key Check ──

    test('createKeyCheck and verifyKeyCheck round-trip succeeds', () {
      final check = CryptoService.createKeyCheck(testKey);
      expect(CryptoService.verifyKeyCheck(check, testKey), isTrue);
    });

    test('verifyKeyCheck fails with wrong key', () {
      final check = CryptoService.createKeyCheck(testKey);
      final wrongKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      expect(CryptoService.verifyKeyCheck(check, wrongKey), isFalse);
    });

    test('verifyKeyCheck fails with corrupted data', () {
      expect(CryptoService.verifyKeyCheck('v2:bad:data', testKey), isFalse);
    });

    // ── Salt Generation ──

    test('generateSalt returns requested length', () {
      expect(CryptoService.generateSalt(16).length, equals(16));
      expect(CryptoService.generateSalt(32).length, equals(32));
      expect(CryptoService.generateSalt(12).length, equals(12));
    });

    test('generateSalt produces unique values', () {
      final a = CryptoService.generateSalt();
      final b = CryptoService.generateSalt();
      expect(a, isNot(equals(b)));
    });

    // ── Decrypt format validation ──

    test('decrypt rejects malformed v2 input', () {
      expect(() => CryptoService.decrypt('v2:onlyonepart', testKey), throwsA(anything));
    });

    test('decrypt rejects malformed legacy input', () {
      expect(() => CryptoService.decrypt('nocolon', testKey), throwsA(anything));
    });
  });
}
