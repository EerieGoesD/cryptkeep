import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptkeep/services/passkey_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webcrypto/webcrypto.dart';

/// Checks the bytes we hand a relying party actually match the WebAuthn spec.
/// A wrong offset or CBOR key here fails at the website with no useful error,
/// so it gets pinned down here instead.
///
/// Runs on a device rather than the host: the crypto is native (BoringSSL via
/// FFI), so this also exercises the real target rather than a desktop stand-in.
/// Pulls the public key back out of a registration response, the way a relying
/// party's server would, so assertions are checked against the published key
/// rather than one we kept lying around.
Future<EcdsaPublicKey> _publicKeyFrom(String registrationResponseJson) async {
  final json = jsonDecode(registrationResponseJson);
  final authData = Uint8List.fromList(
    ((cborDecode(PasskeyService.b64UrlDecode(
                json['response']['attestationObject'])) as CborMap)[
            CborString('authData')]!
        .toObject() as List)
        .cast<int>(),
  );
  // rpIdHash(32)+flags(1)+signCount(4)+aaguid(16)+credIdLen(2)+credId(32) = 87
  final cose = cborDecode(authData.sublist(87)) as CborMap;
  final x = (cose[CborSmallInt(-2)]!.toObject() as List).cast<int>();
  final y = (cose[CborSmallInt(-3)]!.toObject() as List).cast<int>();
  return EcdsaPublicKey.importRawKey(
    Uint8List.fromList([0x04, ...x, ...y]),
    EllipticCurve.p256,
  );
}

/// WebCrypto verifies raw r||s, so unpack the DER we produce back into it.
Uint8List _derToRawSignature(Uint8List der) {
  var i = 2; // skip SEQUENCE tag + length
  Uint8List readInt() {
    // der[i] is the INTEGER tag
    final len = der[i + 1];
    var bytes = der.sublist(i + 2, i + 2 + len);
    i += 2 + len;
    // Drop the sign-padding byte, then left-pad back to 32.
    if (bytes.length > 32) bytes = bytes.sublist(bytes.length - 32);
    return Uint8List.fromList(
        [...List.filled(32 - bytes.length, 0), ...bytes]);
  }

  final r = readInt();
  final s = readInt();
  return Uint8List.fromList([...r, ...s]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const rpId = 'letterboxd.com';
  final clientDataJson = jsonEncode({
    'type': 'webauthn.create',
    'challenge': 'dGVzdC1jaGFsbGVuZ2U',
    'origin': 'https://letterboxd.com',
  });

  test('registration response is spec-shaped', () async {
    final result = await PasskeyService.create(
      rpId: rpId,
      userHandle: 'dXNlci1oYW5kbGU',
      clientDataJson: clientDataJson,
      includeClientDataJson: true,
    );

    final json = jsonDecode(result.registrationResponseJson);
    expect(json['type'], 'public-key');
    expect(json['id'], isNotEmpty);
    expect(json['id'], json['rawId']);
    expect(json['authenticatorAttachment'], 'platform');
    expect(json['clientExtensionResults']['credProps']['rk'], isTrue);

    // clientDataJSON must survive the round trip unchanged.
    final response = json['response'] as Map<String, dynamic>;
    expect(
      utf8.decode(PasskeyService.b64UrlDecode(response['clientDataJSON'])),
      clientDataJson,
    );

    // Fields the caller needs alongside the attestation object.
    expect(response['publicKeyAlgorithm'], -7);
    expect(response['publicKey'], isNotEmpty);
    expect(response['authenticatorData'], isNotEmpty);

    // base64url must be unpadded: '=' breaks strict parsers.
    expect(json['id'], isNot(contains('=')));
    expect(response['attestationObject'], isNot(contains('=')));
  });

  test('clientDataJSON is omitted, not blanked, for a privileged browser',
      () async {
    // A browser builds its own client data and only hands us the hash. Sending
    // ours (even as a placeholder) makes the browser reject the whole thing,
    // which surfaces to the user as "an unknown error".
    final result = await PasskeyService.create(
      rpId: rpId,
      userHandle: 'dXNlci1oYW5kbGU',
      clientDataJson: clientDataJson,
      includeClientDataJson: false,
    );

    final response =
        jsonDecode(result.registrationResponseJson)['response'] as Map;
    expect(response.containsKey('clientDataJSON'), isFalse);
    expect(response['attestationObject'], isNotEmpty);
  });

  test('attestation object and authenticator data match the spec', () async {
    final result = await PasskeyService.create(
      rpId: rpId,
      userHandle: 'dXNlci1oYW5kbGU',
      clientDataJson: clientDataJson,
      includeClientDataJson: true,
    );

    final json = jsonDecode(result.registrationResponseJson);
    final attestation = cborDecode(PasskeyService.b64UrlDecode(
      json['response']['attestationObject'],
    )) as CborMap;

    Object? at(String key) =>
        attestation[CborString(key)]?.toObject();

    expect(at('fmt'), 'none');
    expect(at('attStmt'), isEmpty);

    final authData =
        Uint8List.fromList((at('authData') as List).cast<int>());

    // rpIdHash(32) | flags(1) | signCount(4) | aaguid(16) | credIdLen(2) | ...
    expect(
      authData.sublist(0, 32),
      crypto.sha256.convert(utf8.encode(rpId)).bytes,
      reason: 'rpIdHash must be SHA-256 of the rpId',
    );

    final flags = authData[32];
    expect(flags & 0x01, 0x01, reason: 'user present');
    expect(flags & 0x04, 0x04, reason: 'user verified');
    expect(flags & 0x40, 0x40, reason: 'attested credential data included');
    expect(flags & 0x08, 0x08, reason: 'backup eligible (synced vault)');
    expect(flags & 0x10, 0x10, reason: 'backed up (synced vault)');

    final signCount =
        ByteData.sublistView(authData, 33, 37).getUint32(0, Endian.big);
    expect(signCount, 0);

    expect(authData.sublist(37, 53), List.filled(16, 0),
        reason: 'all-zero AAGUID for a software authenticator');

    final credIdLen =
        ByteData.sublistView(authData, 53, 55).getUint16(0, Endian.big);
    expect(credIdLen, 32);

    final credentialId = authData.sublist(55, 55 + credIdLen);
    expect(PasskeyService.b64Url(credentialId), json['id'],
        reason: 'credential id in authData must match the reported id');

    // Remaining bytes are the COSE public key.
    final cose = cborDecode(authData.sublist(55 + credIdLen)) as CborMap;
    Object? cbor(int key) => cose[CborSmallInt(key)]?.toObject();

    expect(cbor(1), 2, reason: 'kty EC2');
    expect(cbor(3), -7, reason: 'alg ES256');
    expect(cbor(-1), 1, reason: 'crv P-256');
    expect((cbor(-2) as List).length, 32, reason: 'x coordinate');
    expect((cbor(-3) as List).length, 32, reason: 'y coordinate');
  });

  test('assertion is DER-signed and verifies against the published key',
      () async {
    // The whole point of a passkey: the site must be able to verify our
    // signature with the public key we gave it at registration.
    final created = await PasskeyService.create(
      rpId: rpId,
      userHandle: 'dXNlci1oYW5kbGU',
      clientDataJson: clientDataJson,
      includeClientDataJson: true,
    );

    final getClientData = jsonEncode({
      'type': 'webauthn.get',
      'challenge': 'YW5vdGhlci1jaGFsbGVuZ2U',
      'origin': 'https://letterboxd.com',
    });

    final assertionJson = jsonDecode(await PasskeyService.assertion(
      passkey: created.data,
      clientDataJson: getClientData,
      includeClientDataJson: true,
    ));

    final response = assertionJson['response'] as Map<String, dynamic>;
    expect(assertionJson['id'], created.data.credentialId);
    expect(response['userHandle'], 'dXNlci1oYW5kbGU');

    final authData =
        PasskeyService.b64UrlDecode(response['authenticatorData']);
    // Assertions carry no attested credential data, so no 0x40 flag and a
    // bare 37-byte header.
    expect(authData.length, 37);
    expect(authData[32] & 0x40, 0, reason: 'no attested credential data');
    expect(authData[32] & 0x04, 0x04, reason: 'user verified');

    final signature = PasskeyService.b64UrlDecode(response['signature']);
    // DER: SEQUENCE of two INTEGERs. A raw r||s pair would be a bare 64 bytes
    // and every relying party would reject it.
    expect(signature[0], 0x30, reason: 'must be an ASN.1 SEQUENCE');
    expect(signature.length, signature[1] + 2);
    expect(signature[2], 0x02, reason: 'r must be an INTEGER');

    // Verify exactly as a site would: over authenticatorData + SHA-256(clientDataJSON).
    final clientDataHash =
        crypto.sha256.convert(utf8.encode(getClientData)).bytes;
    final signedPayload =
        Uint8List.fromList([...authData, ...clientDataHash]);

    final publicKey = await _publicKeyFrom(created.registrationResponseJson);
    expect(
      await publicKey.verifyBytes(
        _derToRawSignature(signature),
        signedPayload,
        Hash.sha256,
      ),
      isTrue,
      reason: 'the site must be able to verify our assertion',
    );
  });

  test('stored private key can be reimported and signs verifiably', () async {
    final result = await PasskeyService.create(
      rpId: rpId,
      userHandle: 'dXNlci1oYW5kbGU',
      clientDataJson: clientDataJson,
      includeClientDataJson: true,
    );

    // Slice 3 depends on this: the key we store must come back and sign.
    final privateKey = await EcdsaPrivateKey.importPkcs8Key(
      base64.decode(result.data.privateKeyPkcs8),
      EllipticCurve.p256,
    );

    final payload = Uint8List.fromList(utf8.encode('challenge bytes'));
    final signature = await privateKey.signBytes(payload, Hash.sha256);

    // The public key from the attestation must verify that signature, proving
    // the stored key and the published key are the same pair.
    final json = jsonDecode(result.registrationResponseJson);
    final authData = Uint8List.fromList(
      ((cborDecode(PasskeyService.b64UrlDecode(
                  json['response']['attestationObject'])) as CborMap)[
              CborString('authData')]!
          .toObject() as List)
          .cast<int>(),
    );
    final cose = cborDecode(authData.sublist(87)) as CborMap;
    final x = (cose[CborSmallInt(-2)]!.toObject() as List).cast<int>();
    final y = (cose[CborSmallInt(-3)]!.toObject() as List).cast<int>();

    final publicKey = await EcdsaPublicKey.importRawKey(
      Uint8List.fromList([0x04, ...x, ...y]),
      EllipticCurve.p256,
    );

    expect(
      await publicKey.verifyBytes(signature, payload, Hash.sha256),
      isTrue,
      reason: 'stored private key must match the published public key',
    );
  });
}
