# CryptKeep

CryptKeep is a zero-knowledge password manager. Your vault is encrypted on your device before it ever leaves it. The server only ever sees ciphertext.

You log in once with your master password, and everything is decrypted locally. Passwords, usernames, URLs and notes are stored encrypted at rest.

Built with Flutter and Supabase.

- AES-256-CBC encryption with PBKDF2-SHA256 key derivation
- Import from KeePass (.kdbx)
- Categories, search, and bulk delete
- macOS, Windows, iOS, Android

Coming soon on the App Store, Microsoft Store and Google Play.
