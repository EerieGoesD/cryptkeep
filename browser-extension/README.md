# CryptKeep browser extension

The browser half of CryptKeep. Sign in with the same account, unlock with the
same master password, fill logins into the page you are on.

Plain JavaScript, no build step and no dependencies. What is in this folder is
exactly what gets loaded.

## Loading it while you work on it

1. Open `chrome://extensions`
2. Turn on Developer mode
3. Choose "Load unpacked" and pick this `browser-extension` folder

After editing a file, press the reload arrow on the extension card. Edge is the
same, at `edge://extensions`.

## How it fits the rest of the app

It talks to the same Supabase project as the apps, over plain REST. The vault
key is derived in the browser and rows arrive as ciphertext, so the zero
knowledge promise holds here exactly as it does elsewhere.

`src/crypto.js` and `src/totp.js` are ports of `lib/services/crypto_service.dart`
and `lib/services/totp_service.dart`. They have to agree byte for byte, so there
is a test that proves they do:

```
node browser-extension/test/parity.test.mjs
```

Run it after changing either side. If it fails, the extension will derive a
different key and refuse to open a vault that is perfectly fine.

## Pro

The extension sells nothing. Pro is read off the account, the same way
`PremiumService.isPremium` reads it in the app, so a subscription bought
anywhere unlocks two-factor codes here too.

**One gap to close before this ships.** Microsoft Store subscriptions do not
write `premium_until` to the account. `MsStoreService` checks the Windows
licence and sets a flag that only exists on that machine, so a Windows Store
subscriber will sign in here and see no Pro. Apple, Google Play and Stripe all
write to the account already; Windows needs to do the same.

## Where things live

| File | What it does |
| --- | --- |
| `manifest.json` | Permissions and entry points |
| `src/config.js` | Supabase details, mirrors `lib/config.dart` |
| `src/crypto.js` | Key derivation and encryption, ported from Dart |
| `src/totp.js` | Two-factor codes, ported from Dart |
| `src/api.js` | Supabase REST calls |
| `src/vault.js` | Sign in, unlock, decrypt, match entries to the page |
| `src/background.js` | Holds the key and the entries, answers the popup |
| `src/filler.js` | The function injected into the page to type the login |
| `src/popup.*` | The window that opens when you click the icon |

## How the key is kept

The vault key and the decrypted entries live only in the service worker, in
`chrome.storage.session`. That is held in memory, never written to disk, cleared
when the browser closes, and not reachable from web pages.

The popup never receives passwords in bulk. It gets a list of titles and
usernames, and asks for a single secret at the moment you press copy. Filling
happens in the service worker, so the password goes straight to the page without
passing through the popup.

The vault relocks after 15 minutes of no use, changeable through the
`setAutoLock` message.

## Permissions, and why each one is there

| Permission | Why |
| --- | --- |
| `storage` | Remembers your email address and the auto-lock setting; holds the unlocked vault in session memory |
| `activeTab` + `scripting` | Fills the login, only in the tab you are on, only when you press Fill |
| `alarms` | The auto-lock timer |
| Supabase host | Sign in and fetch the vault |

There is deliberately no `<all_urls>` and no always-on content script. Nothing is
injected into any page until you press Fill. That keeps the review easy and
means the extension is doing nothing at all while you browse.

## What it does not do yet

- **Passkeys.** Entries show up and are labelled, but signing in with one needs
  the WebAuthn provider work the Android app has. Use the app for those.
- **Saving new logins.** It reads the vault; it does not offer to save a login
  after you sign in, and there is no add or edit screen. Both are the obvious
  next things.
- **Inline dropdowns in the page.** Filling is driven from the popup. An inline
  suggestion on the field itself would need broad host permissions, which is a
  bigger review conversation and worth doing separately.
- **Sites that put the login in an iframe.** The filler only looks at the top
  document.

## Two things to test on a real account before shipping

1. **Two-factor sign in.** If the account has an authenticator factor, the
   extension raises the session before it treats the vault as unlocked, using
   the challenge and verify endpoints. It fails closed, so the worst case is
   that an account with two-factor cannot unlock here rather than bypassing it.
   Confirm it works against a real MFA account.
2. **A pre-v2 account.** An account with no `crypto_salt` is told to open the
   app once, because migration rewrites every entry and that is the full app's
   job.

## For the Chrome Web Store listing

The store wants a 128x128 PNG uploaded in the dashboard; the icons in this
folder are 48, 192 and 512. The listing also needs a justification for each
permission, and the answers are in the permissions table above.
