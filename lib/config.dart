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
// (e.g. Microsoft Store paid version). Skips Stripe checkout entirely.
const bool kProIncluded = bool.fromEnvironment('PRO_INCLUDED', defaultValue: false);

const String kAuthRedirectUrl = 'https://eeriegoesd.com/cryptkeep/';
