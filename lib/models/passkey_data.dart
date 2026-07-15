/// The stored half of a passkey (a WebAuthn discoverable credential).
///
/// Lives inside a [VaultEntry], so it is encrypted, synced and counted against
/// the free entry limit exactly like a password. The private key is the secret
/// here: it never leaves the vault and is only used to sign a challenge.
class PasskeyData {
  /// The site or app the passkey belongs to, e.g. "letterboxd.com".
  final String rpId;

  /// Random 32-byte credential handle, base64url, no padding.
  final String credentialId;

  /// The private key in PKCS8, base64. Never leaves the device unencrypted.
  final String privateKeyPkcs8;

  /// The relying party's opaque user id, base64url, no padding.
  final String userHandle;

  /// Signature counter. WebAuthn allows a fixed 0 for cloud-synced passkeys,
  /// which is what this is - a counter cannot be kept consistent across
  /// devices sharing one vault.
  final int signCount;

  const PasskeyData({
    required this.rpId,
    required this.credentialId,
    required this.privateKeyPkcs8,
    required this.userHandle,
    this.signCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'rp_id': rpId,
        'credential_id': credentialId,
        'private_key_pkcs8': privateKeyPkcs8,
        'user_handle': userHandle,
        'sign_count': signCount,
      };

  factory PasskeyData.fromJson(Map<String, dynamic> json) => PasskeyData(
        rpId: json['rp_id'] as String,
        credentialId: json['credential_id'] as String,
        privateKeyPkcs8: json['private_key_pkcs8'] as String,
        userHandle: (json['user_handle'] as String?) ?? '',
        signCount: (json['sign_count'] as int?) ?? 0,
      );
}
