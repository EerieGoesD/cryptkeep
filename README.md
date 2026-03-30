# CryptKeep

CryptKeep is a zero-knowledge password manager. Your vault is encrypted on your device before it ever leaves it. The server only ever sees ciphertext.

You log in once with your master password, and everything is decrypted locally. Passwords, usernames, URLs and notes are stored encrypted at rest.

Built with Flutter and Supabase.

- AES-256-GCM encryption with PBKDF2-SHA256 key derivation
- Two-factor authentication (TOTP)
- Import and export KeePass (.kdbx)
- Password health dashboard and breach monitoring (Pro)
- Categories, search, and bulk delete
- Web, Windows, macOS, iOS, Android

Available on the [Microsoft Store](https://apps.microsoft.com/detail/20715EerieGoesD.CryptKeep) and [web](https://eeriegoesd.com/cryptkeep/). Coming soon on the App Store and Google Play.
