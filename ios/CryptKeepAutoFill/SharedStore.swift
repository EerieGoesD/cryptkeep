import Foundation
import LocalAuthentication

/// Reads what the Flutter app wrote into the shared keychain group.
///
/// The app stores through flutter_secure_storage, so the query attributes here
/// are not a free choice: they must match what that plugin writes byte for
/// byte, or the lookup silently returns nothing. Confirmed against
/// flutter_secure_storage_darwin 0.3.2:
///
///   kSecClass          kSecClassGenericPassword
///   kSecAttrService    "flutter_secure_storage_service"   (its default)
///   kSecAttrAccount    the Dart-side key name
///   kSecAttrAccessGroup kAppleGroupId, exactly as Dart passes it
///
/// Note the access group is the UNPREFIXED string, because that is what the
/// Dart side passes to the plugin. Both sides therefore agree. Do not "fix"
/// this by adding the team prefix here alone - that would break the match.
enum SharedStore {

    /// Must equal kAppleGroupId in lib/config.dart.
    static let accessGroup = "group.com.eerie.cryptkeep"

    /// flutter_secure_storage's default kSecAttrService.
    private static let service = "flutter_secure_storage_service"

    // Account names, from BiometricService and VaultCacheService.
    private static let vaultKeyAccount = "cryptkeep_vault_key"
    private static let vaultCacheAccount = "cryptkeep_vault_cache"
    private static let emailAccount = "cryptkeep_biometric_email"

    private static func read(account: String, context: LAContext? = nil) -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: accessGroup,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let context {
            query[kSecUseAuthenticationContext] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                NSLog("CryptKeep autofill: keychain read of \(account) failed (\(status))")
            }
            return nil
        }
        return item as? Data
    }

    /// The vault key, already derived from the master password by the app.
    ///
    /// The extension never sees the master password and never derives anything.
    /// If the user has not turned on biometric unlock in the app, this is
    /// absent and autofill cannot work - that is the intended behaviour, not a
    /// bug to work around.
    static func vaultKey(context: LAContext? = nil) -> Data? {
        guard let raw = read(account: vaultKeyAccount, context: context),
              let base64 = String(data: raw, encoding: .utf8),
              let key = Data(base64Encoded: base64),
              key.count == 32
        else { return nil }
        return key
    }

    /// The account the stored key belongs to, shown so the user can see which
    /// vault they are filling from.
    static func accountEmail() -> String? {
        guard let raw = read(account: emailAccount) else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    /// The offline copy of the vault: still ciphertext, exactly as the server
    /// holds it. Written by VaultCacheService.
    static func cachedRows() -> [String]? {
        guard let raw = read(account: vaultCacheAccount) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return nil }

        // Version gate, matching VaultCacheService._version.
        guard let version = json["v"] as? Int, version == 1 else { return nil }
        return json["rows"] as? [String]
    }
}
