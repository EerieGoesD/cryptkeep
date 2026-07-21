# iOS autofill and passkey extension

The Swift is written. What is left can only be done in Xcode on a Mac: adding
the target, then building and testing on a real iPhone.

## What this does

Fills usernames and passwords into other apps and Safari, and signs in with
passkeys the vault already holds. It reads the offline vault copy the Flutter
app writes into the shared keychain group, so it works with no network.

**The user must turn on biometric unlock in the app first.** That is what puts
the vault key somewhere this extension can reach. Without it the extension has
nothing to decrypt with and says so on screen.

## Adding the target in Xcode

1. Open `ios/Runner.xcworkspace`.
2. File > New > Target > **Credential Provider Extension**. Name it
   `CryptKeepAutoFill`. When Xcode offers to activate the new scheme, accept.
3. Xcode creates its own folder with template files. **Delete the template
   files it generated** (its `CredentialProviderViewController.swift` and its
   `Info.plist`), then drag in the files from this folder instead, ticking
   "CryptKeepAutoFill" as the target:
   - `CredentialProviderViewController.swift`
   - `CredentialListView.swift`
   - `SharedStore.swift`
   - `VaultCrypto.swift`
   - `VaultModels.swift`
   - `PasskeyAuthenticator.swift`
   - `Info.plist` (set it as the target's Info.plist in Build Settings)
4. Target settings > Signing & Capabilities:
   - Bundle identifier: `com.eerie.cryptkeep.autofill`
   - Add **App Groups**, tick `group.com.eerie.cryptkeep`
   - Add **Keychain Sharing**, add `group.com.eerie.cryptkeep`
   - Confirm the entitlements file is `CryptKeepAutoFill.entitlements` from this
     folder, not a fresh one Xcode made
5. Deployment target: **iOS 17.0** or later for the passkey parts. The password
   parts work lower, but the passkey code is behind `@available(iOS 17.0, *)`.
6. Register `com.eerie.cryptkeep.autofill` as its own App ID at
   https://developer.apple.com/account/resources/identifiers/list with the
   **App Groups** capability, and assign the group to it. An extension is a
   separate bundle and needs its own App ID and its own provisioning profile.

## Turning it on, on the phone

Settings > General > AutoFill & Passwords > turn on CryptKeep.

## Testing, in this order

1. Open CryptKeep, sign in, and **turn on biometric unlock**.
2. Open the vault once so the offline copy gets written.
3. Go to any login screen in another app or Safari. CryptKeep should appear
   above the keyboard. Tap it, pass Face ID, pick an entry.
4. For passkeys, use a site where you already created one on Android. It should
   sync down and sign in.

## What is not supported, on purpose

**Creating new passkeys from the extension.** Registration would have to write
the new credential back into the vault, and the vault copy this extension reads
is written by the app, not by us. A passkey created here would be one the user
could never use again. `prepareInterface(forPasskeyRegistration:)` refuses
cleanly rather than half-doing it.

Consequence today: passkeys can be created on Android and used on iPhone, but
not created on iPhone. Closing that gap means letting the extension write to the
vault, which needs network and auth in the extension, and is its own piece of
work.

**One-time codes.** The vault holds TOTP seeds and the extension could offer
them through `ASOneTimeCodeCredential` on iOS 18. Not wired up yet.

## Things most likely to bite, in order

1. **The keychain access group string.** `SharedStore.accessGroup` must equal
   `kAppleGroupId` in `lib/config.dart`, unprefixed, because that is exactly
   what the Dart side passes to flutter_secure_storage. If reads come back
   empty, this is the first thing to check.
2. **The keychain service name.** `flutter_secure_storage_service` is that
   plugin's default `kSecAttrService`. If the app ever sets `accountName` in
   `IOSOptions`, this must change to match.
3. **Error -34018 on the app side** means the entitlement and the group do not
   line up. Fix the app first; the extension cannot read what was never written.
4. **Nothing in the list** usually means the app has not written the cache yet.
   Open the app and load the vault once.

## Untested

None of this has been compiled. It was written on Windows against the Dart
originals, with the formats verified by reading
`flutter_secure_storage_darwin` 0.3.2 rather than assumed. Expect to fix
compile errors on the first build.
