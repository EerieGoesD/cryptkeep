import CryptoKit
import Foundation

/// The signing half of lib/services/passkey_service.dart, ported to Swift.
///
/// Every byte below is dictated by the WebAuthn spec, and getting any of it
/// wrong fails at the relying party, usually silently. The layout follows the
/// same sections the Dart original does.
///
/// Reference: https://www.w3.org/TR/webauthn-2/
///
/// SCOPE: this signs assertions, which is what signing in with an existing
/// passkey means. It deliberately does NOT create new passkeys. Registration
/// would have to write the new credential back into the vault, and the vault
/// copy this extension reads is written by the app, not by us. A passkey we
/// created here would be one the user could never use again. Creating passkeys
/// stays in the app.
enum PasskeyAuthenticator {

    enum Failure: Error {
        case badPrivateKey
        case signingFailed
    }

    // Authenticator data flags (WebAuthn 6.1).
    private static let flagUserPresent: UInt8 = 0x01
    private static let flagUserVerified: UInt8 = 0x04
    private static let flagBackupEligible: UInt8 = 0x08
    private static let flagBackedUp: UInt8 = 0x10

    /// Authenticator data for an assertion: the header only, with no attested
    /// credential data. Matches _authenticatorData in the Dart original.
    ///
    /// Backup eligible and backed up are both set because this passkey lives in
    /// a synced vault rather than on one device.
    static func authenticatorData(rpId: String, signCount: Int) -> Data {
        var out = Data()
        out.append(contentsOf: SHA256.hash(data: Data(rpId.utf8)))
        out.append(flagUserPresent | flagUserVerified | flagBackupEligible | flagBackedUp)
        out.append(uint32(UInt32(truncatingIfNeeded: signCount)))
        return out
    }

    /// Signs `authenticatorData || clientDataHash` with the stored private key.
    ///
    /// Returns a DER signature, which is what WebAuthn expects and what the
    /// Dart side produces via _signatureToDer.
    static func sign(
        passkey: PasskeyData,
        clientDataHash: Data
    ) throws -> (authenticatorData: Data, signature: Data) {
        guard let pkcs8 = Data(base64Encoded: passkey.privateKeyPkcs8),
              let scalar = privateKeyScalar(fromPKCS8: pkcs8),
              let key = try? P256.Signing.PrivateKey(rawRepresentation: scalar)
        else { throw Failure.badPrivateKey }

        let authData = authenticatorData(rpId: passkey.rpId, signCount: passkey.signCount)

        // P256.Signing hashes with SHA-256 internally, which is what the Dart
        // side asks for explicitly. Do not pre-hash here or it is hashed twice.
        guard let signature = try? key.signature(for: authData + clientDataHash) else {
            throw Failure.signingFailed
        }
        return (authData, signature.derRepresentation)
    }

    // MARK: - PKCS#8

    /// Pulls the 32-byte private scalar out of a PKCS#8 EC key.
    ///
    /// The vault stores PKCS#8 because that is what the Dart WebCrypto binding
    /// exports. CryptoKit wants the bare scalar, so the wrapper is unpicked
    /// here rather than trusting a DER initialiser to accept both shapes.
    ///
    /// Structure:
    ///   SEQUENCE {
    ///     INTEGER 0
    ///     SEQUENCE { OID ecPublicKey, OID prime256v1 }
    ///     OCTET STRING {
    ///       SEQUENCE { INTEGER 1, OCTET STRING <32 bytes>, ... }
    ///     }
    ///   }
    static func privateKeyScalar(fromPKCS8 der: Data) -> Data? {
        var reader = DERReader(der)
        guard let outer = reader.readSequence() else { return nil }

        var top = DERReader(outer)
        guard top.skipElement(tag: 0x02) else { return nil }        // version
        guard top.skipElement(tag: 0x30) else { return nil }        // algorithm
        guard let wrapper = top.readElement(tag: 0x04) else { return nil }

        var inner = DERReader(wrapper)
        guard let ecKey = inner.readSequence() else { return nil }

        var ec = DERReader(ecKey)
        guard ec.skipElement(tag: 0x02) else { return nil }         // version
        guard let scalar = ec.readElement(tag: 0x04) else { return nil }

        // P-256 scalars are 32 bytes. A shorter one is left-padded rather than
        // rejected, since DER may drop leading zero bytes.
        if scalar.count == 32 { return scalar }
        if scalar.count < 32 {
            return Data(repeating: 0, count: 32 - scalar.count) + scalar
        }
        return scalar.suffix(32)
    }

    private static func uint32(_ value: UInt32) -> Data {
        var big = value.bigEndian
        return Data(bytes: &big, count: 4)
    }
}

/// A minimal DER walker. Only what unwrapping a PKCS#8 EC key needs: read a
/// tag, read its length, hand back or skip its contents.
private struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        self.bytes = [UInt8](data)
    }

    mutating func readSequence() -> Data? {
        readElement(tag: 0x30)
    }

    mutating func readElement(tag: UInt8) -> Data? {
        guard index < bytes.count, bytes[index] == tag else { return nil }
        index += 1
        guard let length = readLength(), index + length <= bytes.count else { return nil }
        let content = Data(bytes[index..<(index + length)])
        index += length
        return content
    }

    mutating func skipElement(tag: UInt8) -> Bool {
        readElement(tag: tag) != nil
    }

    /// DER length: short form is one byte under 0x80; long form has the top bit
    /// set and the low bits give how many bytes hold the length.
    private mutating func readLength() -> Int? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        index += 1

        if first < 0x80 { return Int(first) }

        let count = Int(first & 0x7F)
        guard count > 0, count <= 4, index + count <= bytes.count else { return nil }

        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
