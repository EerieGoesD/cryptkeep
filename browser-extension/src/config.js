// Mirrors lib/config.dart. If either side changes, change both.

export const SUPABASE_URL = 'https://jhuxxolbcrjerztwqyap.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_4dqOnKntw7Z3EPfksXWHWg_ohDxQLcf';

// Where a signed-out or free user is sent to create an account or buy Pro.
// The extension never takes payment itself: Pro is read off the account, so
// whichever app the user subscribes in unlocks it everywhere.
export const WEB_APP_URL = 'https://eeriegoesd.com/cryptkeep/';

// Minutes of inactivity before the vault key is thrown away and the master
// password is needed again.
export const DEFAULT_AUTO_LOCK_MINUTES = 15;
