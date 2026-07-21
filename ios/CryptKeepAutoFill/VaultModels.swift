import Foundation

/// Mirrors lib/models/passkey_data.dart.
struct PasskeyData {
    let rpId: String
    /// Base64url, no padding.
    let credentialId: String
    /// PKCS#8, standard base64.
    let privateKeyPkcs8: String
    /// Base64url, no padding.
    let userHandle: String
    let signCount: Int

    init?(json: [String: Any]) {
        guard let rpId = json["rp_id"] as? String,
              let credentialId = json["credential_id"] as? String,
              let privateKey = json["private_key_pkcs8"] as? String
        else { return nil }
        self.rpId = rpId
        self.credentialId = credentialId
        self.privateKeyPkcs8 = privateKey
        self.userHandle = json["user_handle"] as? String ?? ""
        self.signCount = json["sign_count"] as? Int ?? 0
    }
}

/// Mirrors lib/models/vault_entry.dart. Only the fields autofill needs are
/// kept; the rest of the row is ignored rather than failing to parse.
struct VaultEntry {
    let id: String
    let title: String
    let username: String
    let password: String
    let url: String
    let passkey: PasskeyData?

    var isPasskey: Bool { passkey != nil }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        self.title = json["title"] as? String ?? ""
        self.username = json["username"] as? String ?? ""
        self.password = json["password"] as? String ?? ""
        self.url = json["url"] as? String ?? ""
        if let passkeyJson = json["passkey"] as? [String: Any] {
            self.passkey = PasskeyData(json: passkeyJson)
        } else {
            self.passkey = nil
        }
    }

    /// The host this entry belongs to, lowercased and without "www.".
    var host: String? {
        Self.host(from: url)
    }

    static func host(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: withScheme)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Last two labels of a host. Good enough for the sites people save; a
    /// two-part suffix like .co.uk matches more broadly, which errs towards
    /// offering an entry rather than hiding it. Same rule as the browser
    /// extension.
    static func registrableDomain(_ host: String) -> String {
        let parts = host.split(separator: ".")
        guard parts.count > 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }

    func matches(host target: String) -> Bool {
        guard let mine = host else { return false }
        if mine == target { return true }
        return Self.registrableDomain(mine) == Self.registrableDomain(target)
    }
}

/// Turns the cached ciphertext rows into entries.
enum VaultLoader {

    /// Rows that will not open are skipped rather than failing the whole load,
    /// matching VaultService.fetchAll and VaultCacheService.load.
    static func entries(rows: [String], key: Data) -> [VaultEntry] {
        var result: [VaultEntry] = []
        for row in rows {
            guard let plaintext = try? VaultCrypto.decrypt(row, key: key),
                  let data = plaintext.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = VaultEntry(json: json)
            else { continue }
            result.append(entry)
        }
        return result
    }
}

// MARK: - base64url

extension Data {
    /// WebAuthn uses base64url with no padding throughout.
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded input: String) {
        var value = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 {
            value += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: value)
    }
}
