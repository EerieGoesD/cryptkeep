import CommonCrypto
import CryptoKit
import Foundation

/// The decrypt half of lib/services/crypto_service.dart, ported to Swift.
///
/// Only decryption is here. The extension never encrypts and never derives a
/// key from a master password - it reads the already-derived key out of the
/// shared keychain. That keeps PBKDF2, and its 600,000 iterations, out of a
/// process Apple holds to a tight memory and time budget.
///
/// The two ciphertext shapes must match the Dart side exactly:
///
///   v2       "v2:<base64 nonce>:<base64 ciphertext+tag>"
///            AES-256-GCM, 12-byte nonce, 16-byte tag appended to the ciphertext.
///   legacy   "<base64 iv>:<base64 ciphertext>"
///            AES-256-CBC with PKCS#7 padding. Old entries, still in vaults
///            that have not been rewritten.
enum VaultCrypto {

    enum Failure: Error {
        case malformed
        case decryptFailed
    }

    static func decrypt(_ text: String, key: Data) throws -> String {
        if text.hasPrefix("v2:") {
            return try decryptGCM(text, key: key)
        }
        return try decryptCBCLegacy(text, key: key)
    }

    private static func decryptGCM(_ text: String, key: Data) throws -> String {
        let parts = text.components(separatedBy: ":")
        guard parts.count == 3,
              let nonceData = Data(base64Encoded: parts[1]),
              let body = Data(base64Encoded: parts[2]),
              body.count > 16
        else { throw Failure.malformed }

        // CryptoKit wants the tag separately; the Dart side appends it.
        let ciphertext = body.prefix(body.count - 16)
        let tag = body.suffix(16)

        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let plain = try AES.GCM.open(box, using: SymmetricKey(data: key))
            guard let string = String(data: plain, encoding: .utf8) else {
                throw Failure.decryptFailed
            }
            return string
        } catch {
            throw Failure.decryptFailed
        }
    }

    private static func decryptCBCLegacy(_ text: String, key: Data) throws -> String {
        let parts = text.components(separatedBy: ":")
        guard parts.count == 2,
              let iv = Data(base64Encoded: parts[0]),
              let ciphertext = Data(base64Encoded: parts[1])
        else { throw Failure.malformed }

        // CryptoKit has no CBC, so this drops to CommonCrypto.
        var out = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0

        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outBuf in
            ciphertext.withUnsafeBytes { inBuf in
                iv.withUnsafeBytes { ivBuf in
                    key.withUnsafeBytes { keyBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, key.count,
                            ivBuf.baseAddress,
                            inBuf.baseAddress, ciphertext.count,
                            outBuf.baseAddress, out.count,
                            &written
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw Failure.decryptFailed }
        out.removeSubrange(written..<out.count)
        guard let string = String(data: out, encoding: .utf8) else {
            throw Failure.decryptFailed
        }
        return string
    }
}
