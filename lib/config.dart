// ─────────────────────────────────────────────────────────────────────────────
// CryptKeep — Supabase Configuration
// ─────────────────────────────────────────────────────────────────────────────
// Dashboard → Settings → API
// ─────────────────────────────────────────────────────────────────────────────

class SupabaseConfig {
  static const String url = 'https://jhuxxolbcrjerztwqyap.supabase.co';
  static const String anonKey = 'sb_publishable_4dqOnKntw7Z3EPfksXWHWg_ohDxQLcf';
}

// Set with --dart-define=PRO_INCLUDED=true to ship a Pro-bundled build
// (e.g. a one-time-purchase build). Skips all checkout flows entirely.
const bool kProIncluded = bool.fromEnvironment('PRO_INCLUDED', defaultValue: false);

// Storing passwords is free and unlimited, as it is with Bitwarden and Proton
// Pass. Pro sells the security extras (2FA codes, breach checks, health
// report, icons) rather than permission to keep more than a handful.

// Pro subscription product IDs. These must match the products configured in
// both Google Play (subscriptions) and the Microsoft Store (add-ons).
const String kProductIdMonthly = 'cryptkeep_pro_monthly';
const String kProductIdYearly = 'cryptkeep_pro_yearly';

const String kAuthRedirectUrl = 'https://eeriegoesd.com/cryptkeep/';

// Apple App Group / shared keychain group. On iOS and macOS the autofill and
// passkey extension is a separate process, so anything it must read (the vault
// copy and the unlock key) has to live in a shared keychain group, not the
// app's private one. Both the app target and the extension target must declare
// this exact group in their entitlements in Xcode. Ignored on Android/Windows.
//
// Convention is group.<bundle id>. If you register a different App Group in the
// Apple Developer portal, change this one line to match.
const String kAppleGroupId = 'group.com.eerie.cryptkeep';
