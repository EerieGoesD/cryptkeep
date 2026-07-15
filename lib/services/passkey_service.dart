import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
// Prefixed: both packages export `Hash`.
import 'package:crypto/crypto.dart' as crypto;
import 'package:webcrypto/webcrypto.dart';

import '../models/passkey_data.dart';
import 'crypto_service.dart';

/// The result of creating a passkey: the half we keep, and the half the site
/// gets back.
class PasskeyCreation {
  final PasskeyData data;

  /// WebAuthn registration response JSON, handed to the site via Android.
  final String registrationResponseJson;

  const PasskeyCreation(this.data, this.registrationResponseJson);
}

/// The WebAuthn authenticator behind CryptKeep's passkey support.
///
/// Android's credential provider API hands over a request and expects a
/// spec-shaped response: every byte below (authenticator data, the COSE public
/// key, the CBOR attestation object) is ours to assemble. Getting any of it
/// wrong fails at the relying party, usually silently, so the layout follows
/// the spec section by section.
///
/// Reference: https://www.w3.org/TR/webauthn-2/
class PasskeyService {
  /// Identifies the authenticator model. All zeroes is the correct value for a
  /// software authenticator making no claim about hardware ("none" attestation).
  static final Uint8List _aaguid = Uint8List(16);

  // Authenticator data flags (WebAuthn 6.1).
  static const int _flagUserPresent = 0x01;
  static const int _flagUserVerified = 0x04;
  static const int _flagBackupEligible = 0x08;
  static const int _flagBackedUp = 0x10;
  static const int _flagAttestedCredentialData = 0x40;

  /// base64url without padding, the encoding WebAuthn uses throughout.
  static String b64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List b64UrlDecode(String value) {
    final padded = value + '=' * ((4 - value.length % 4) % 4);
    return Uint8List.fromList(base64Url.decode(padded));
  }

  /// Creates a passkey for [rpId].
  ///
  /// [clientDataJson] is built by the caller, which is the only side that can
  /// know the real origin (the calling app's signature, or a browser's own
  /// origin). We only encode it.
  ///
  /// [includeClientDataJson] must be false when a privileged browser supplied
  /// its own clientDataHash: the field is then left out entirely rather than
  /// sent as a placeholder, because the browser owns the real client data.
  static Future<PasskeyCreation> create({
    required String rpId,
    required String userHandle,
    required String clientDataJson,
    required bool includeClientDataJson,
  }) async {
    final keyPair = await EcdsaPrivateKey.generateKey(EllipticCurve.p256);
    final privateKeyPkcs8 = await keyPair.privateKey.exportPkcs8Key();
    final rawPublicKey = await keyPair.publicKey.exportRawKey();
    final spkiPublicKey = await keyPair.publicKey.exportSpkiKey();

    final credentialId = CryptoService.generateSalt(32);

    final authData = _authenticatorData(
      rpId: rpId,
      credentialId: credentialId,
      coseKey: _coseKey(rawPublicKey),
    );

    // Attestation object (WebAuthn 6.5). "none" attestation: we make no claim
    // about the hardware, so the statement is empty. Key order here is already
    // canonical CBOR (shorter keys first).
    final attestationObject = cborEncode(CborMap({
      CborString('fmt'): CborString('none'),
      CborString('attStmt'): CborMap({}),
      CborString('authData'): CborBytes(authData),
    }));

    final data = PasskeyData(
      rpId: rpId,
      credentialId: b64Url(credentialId),
      privateKeyPkcs8: base64.encode(privateKeyPkcs8),
      userHandle: userHandle,
    );

    // AuthenticatorAttestationResponseJSON (WebAuthn). clientDataJSON is
    // omitted, not blanked, when the browser owns it.
    final response = <String, dynamic>{
      if (includeClientDataJson)
        'clientDataJSON': b64Url(utf8.encode(clientDataJson)),
      'attestationObject': b64Url(attestationObject),
      'transports': ['internal', 'hybrid'],
      'authenticatorData': b64Url(authData),
      'publicKeyAlgorithm': -7, // ES256
      'publicKey': b64Url(spkiPublicKey),
    };

    final responseJson = jsonEncode({
      'id': b64Url(credentialId),
      'rawId': b64Url(credentialId),
      'type': 'public-key',
      'authenticatorAttachment': 'platform',
      'response': response,
      // Discoverable ("resident") credential: it lives in the vault and can be
      // found without the site naming it first.
      'clientExtensionResults': {
        'credProps': {'rk': true},
      },
    });

    return PasskeyCreation(data, responseJson);
  }

  /// Signs a challenge with a stored passkey, proving the user holds the
  /// private key without revealing it. This is what signing in actually is.
  ///
  /// [clientDataHash] is supplied by privileged browsers and must be signed
  /// as-is; for a native caller we hash the client data ourselves.
  static Future<String> assertion({
    required PasskeyData passkey,
    required String clientDataJson,
    required bool includeClientDataJson,
    Uint8List? clientDataHash,
  }) async {
    final privateKey = await EcdsaPrivateKey.importPkcs8Key(
      base64.decode(passkey.privateKeyPkcs8),
      EllipticCurve.p256,
    );

    // No attested credential data on an assertion: just the header.
    final authData =
        _authenticatorData(rpId: passkey.rpId, signCount: passkey.signCount);

    final hash = clientDataHash ??
        Uint8List.fromList(
            crypto.sha256.convert(utf8.encode(clientDataJson)).bytes);

    final signature = await privateKey.signBytes(
      Uint8List.fromList([...authData, ...hash]),
      Hash.sha256,
    );

    final response = <String, dynamic>{
      if (includeClientDataJson)
        'clientDataJSON': b64Url(utf8.encode(clientDataJson)),
      'authenticatorData': b64Url(authData),
      'signature': b64Url(_signatureToDer(Uint8List.fromList(signature))),
      'userHandle': passkey.userHandle,
    };

    return jsonEncode({
      'id': passkey.credentialId,
      'rawId': passkey.credentialId,
      'type': 'public-key',
      'authenticatorAttachment': 'platform',
      'response': response,
      'clientExtensionResults': <String, dynamic>{},
    });
  }

  /// WebAuthn wants an ES256 signature in ASN.1 DER, but WebCrypto emits the
  /// raw r||s pair. Without this every assertion is rejected as a bad
  /// signature, with nothing to say why.
  static Uint8List _signatureToDer(Uint8List raw) {
    final body = [
      ..._derInteger(raw.sublist(0, 32)),
      ..._derInteger(raw.sublist(32, 64)),
    ];
    // r and s are 32 bytes, so the body never reaches the 128-byte mark that
    // would need a long-form length.
    return Uint8List.fromList([0x30, body.length, ...body]);
  }

  static List<int> _derInteger(Uint8List value) {
    var start = 0;
    while (start < value.length - 1 && value[start] == 0) {
      start++;
    }
    var trimmed = value.sublist(start);
    // A leading high bit would read as negative, so pad it.
    if (trimmed[0] & 0x80 != 0) {
      trimmed = Uint8List.fromList([0, ...trimmed]);
    }
    return [0x02, trimmed.length, ...trimmed];
  }

  /// Authenticator data (WebAuthn 6.1):
  /// rpIdHash(32) | flags(1) | signCount(4) | [attested credential data]
  static Uint8List _authenticatorData({
    required String rpId,
    Uint8List? credentialId,
    Uint8List? coseKey,
    int signCount = 0,
  }) {
    final attested = credentialId != null && coseKey != null;

    // Marked backup eligible and backed up: this passkey lives in a synced
    // vault rather than on one device.
    var flags = _flagUserPresent |
        _flagUserVerified |
        _flagBackupEligible |
        _flagBackedUp;
    if (attested) flags |= _flagAttestedCredentialData;

    final builder = BytesBuilder();
    builder.add(crypto.sha256.convert(utf8.encode(rpId)).bytes);
    builder.addByte(flags);
    builder.add(_uint32(signCount));

    if (attested) {
      // Attested credential data (WebAuthn 6.5.1):
      // aaguid(16) | credentialIdLength(2) | credentialId | COSE public key
      builder.add(_aaguid);
      builder.add(_uint16(credentialId.length));
      builder.add(credentialId);
      builder.add(coseKey);
    }
    return builder.toBytes();
  }

  /// The public key as a COSE_Key (RFC 8152). Raw EC keys are the uncompressed
  /// point 0x04 | x(32) | y(32); COSE wants x and y separately.
  static Uint8List _coseKey(Uint8List rawPublicKey) {
    final x = rawPublicKey.sublist(1, 33);
    final y = rawPublicKey.sublist(33, 65);
    return Uint8List.fromList(cborEncode(CborMap({
      CborSmallInt(1): CborSmallInt(2), // kty: EC2
      CborSmallInt(3): CborSmallInt(-7), // alg: ES256
      CborSmallInt(-1): CborSmallInt(1), // crv: P-256
      CborSmallInt(-2): CborBytes(x),
      CborSmallInt(-3): CborBytes(y),
    })));
  }

  static Uint8List _uint16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.big);

  static Uint8List _uint32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);
}
