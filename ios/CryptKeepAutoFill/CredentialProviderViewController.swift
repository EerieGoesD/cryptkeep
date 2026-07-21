import AuthenticationServices
import LocalAuthentication
import SwiftUI
import UIKit

/// What iOS launches when another app or Safari asks CryptKeep to fill a login.
///
/// This is a separate process from the app, with its own tight memory budget,
/// so there is no Flutter engine here and no network. Everything comes from the
/// offline vault copy in the shared keychain group, written by the app.
///
/// The whole flow rests on one thing: the user must have turned on biometric
/// unlock in the app, because that is what puts the vault key somewhere this
/// process can reach. Without it there is nothing to decrypt with, and the
/// extension says so rather than failing silently.
final class CredentialProviderViewController: ASCredentialProviderViewController {

    private var entries: [VaultEntry] = []

    // MARK: - Passwords, no interface

    /// iOS asks for a credential outright when it thinks no interaction is
    /// needed. We always ask for Face ID first, so this reports that the user
    /// must be shown something. iOS then calls prepareInterfaceToProvideCredential.
    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    // MARK: - Passwords, with interface

    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        let host = serviceIdentifiers.compactMap { VaultEntry.host(from: $0.identifier) }.first
        showList(matching: host)
    }

    override func prepareInterfaceToProvideCredential(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        let host = VaultEntry.host(from: credentialIdentity.serviceIdentifier.identifier)
        showList(matching: host)
    }

    // MARK: - Passkeys

    /// Signing in with a passkey the vault already holds.
    ///
    /// iOS hands us the client data hash to sign; we never build the client
    /// data ourselves here.
    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: ASCredentialRequest
    ) {
        guard let passkeyRequest = credentialRequest as? ASPasskeyCredentialRequest,
              let identity = passkeyRequest.credentialIdentity as? ASPasskeyCredentialIdentity
        else {
            cancel(.failed)
            return
        }

        // Face ID first, same as a password.
        authenticate { [weak self] key in
            guard let self else { return }
            guard let key else {
                self.cancel(.userInteractionRequired)
                return
            }
            self.completePasskey(
                request: passkeyRequest,
                identity: identity,
                key: key
            )
        }
    }

    @available(iOS 17.0, *)
    private func completePasskey(
        request: ASPasskeyCredentialRequest,
        identity: ASPasskeyCredentialIdentity,
        key: Data
    ) {
        let all = loadEntries(key: key)
        let wanted = identity.credentialID.base64URLEncodedString

        guard let entry = all.first(where: { $0.passkey?.credentialId == wanted }),
              let passkey = entry.passkey,
              let signed = try? PasskeyAuthenticator.sign(
                  passkey: passkey,
                  clientDataHash: request.clientDataHash
              )
        else {
            cancel(.failed)
            return
        }

        let credential = ASPasskeyAssertionCredential(
            userHandle: Data(base64URLEncoded: passkey.userHandle) ?? Data(),
            relyingParty: passkey.rpId,
            signature: signed.signature,
            clientDataHash: request.clientDataHash,
            authenticatorData: signed.authenticatorData,
            credentialID: Data(base64URLEncoded: passkey.credentialId) ?? Data()
        )
        extensionContext.completeAssertionRequest(using: credential)
    }

    /// Creating a NEW passkey is not supported here, and refusing cleanly is
    /// better than half-doing it. A passkey minted in this process could not be
    /// written back into the vault, so the user would never be able to use it
    /// again. Passkey creation stays in the app.
    @available(iOS 17.0, *)
    override func prepareInterface(forPasskeyRegistration
        registrationRequest: ASCredentialRequest) {
        cancel(.failed)
    }

    // MARK: - Unlocking

    /// Face ID or Touch ID, then the vault key out of the shared keychain.
    ///
    /// The key is released by our own check rather than by a keychain access
    /// control flag, because the app writes it with plain "when unlocked"
    /// accessibility. Changing that is an app-side decision, not one to fake
    /// here.
    private func authenticate(completion: @escaping (Data?) -> Void) {
        let context = LAContext()
        context.localizedReason = "Unlock your CryptKeep vault"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics and no passcode set. Nothing safe to do.
            DispatchQueue.main.async { completion(nil) }
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your CryptKeep vault"
        ) { success, _ in
            DispatchQueue.main.async {
                guard success else {
                    completion(nil)
                    return
                }
                completion(SharedStore.vaultKey(context: context))
            }
        }
    }

    private func loadEntries(key: Data) -> [VaultEntry] {
        guard let rows = SharedStore.cachedRows() else { return [] }
        return VaultLoader.entries(rows: rows, key: key)
    }

    // MARK: - UI

    private func showList(matching host: String?) {
        authenticate { [weak self] key in
            guard let self else { return }

            guard let key else {
                self.present(
                    message: "Turn on biometric unlock inside CryptKeep first, then autofill can reach your vault."
                )
                return
            }

            self.entries = self.loadEntries(key: key)

            if self.entries.isEmpty {
                self.present(
                    message: "No vault copy on this device yet. Open CryptKeep once to sync it."
                )
                return
            }

            let view = CredentialListView(
                entries: self.entries,
                host: host,
                accountEmail: SharedStore.accountEmail(),
                onPick: { [weak self] entry in
                    self?.complete(with: entry)
                },
                onCancel: { [weak self] in
                    self?.cancel(.userCanceled)
                }
            )
            self.host(view)
        }
    }

    private func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        addChild(controller)
        controller.view.frame = self.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func present(message: String) {
        host(MessageView(message: message) { [weak self] in
            self?.cancel(.userCanceled)
        })
    }

    private func complete(with entry: VaultEntry) {
        let credential = ASPasswordCredential(
            user: entry.username,
            password: entry.password
        )
        extensionContext.completeRequest(withSelectedCredential: credential)
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue)
        )
    }
}
