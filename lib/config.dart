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
