// Unlocking and reading the vault. The order of operations mirrors the sign-in
// flow in lib/screens/auth/login_screen.dart.

import * as api from './api.js';
import * as crypto2 from './crypto.js';

/// Signs in the way the apps do: try the current derived auth password, then
/// the pre-v2 one, then the raw master password for accounts that have never
/// been migrated.
async function signInAnyVersion(email, masterPassword) {
  const authV2 = await crypto2.deriveAuthPassword(masterPassword, email);
  try {
    return await api.signIn(email, authV2);
  } catch (error) {
    if (error.status && error.status >= 500) throw error;
  }

  const authV1 = await crypto2.deriveAuthPasswordLegacy(masterPassword, email);
  try {
    return await api.signIn(email, authV1);
  } catch (error) {
    if (error.status && error.status >= 500) throw error;
  }

  return api.signIn(email, masterPassword);
}

/// Derives the vault key from the account's stored salt and iteration count,
/// then proves it is right against the stored key check.
async function deriveAndVerifyKey(masterPassword, user) {
  const meta = user?.user_metadata || {};

  // No salt means this account has never been opened by a v2 app. Migration
  // rewrites every entry, which is the full app's job, not the extension's.
  if (!meta.crypto_salt) {
    const error = new Error(
      'This account needs to be opened in the CryptKeep app once before the extension can use it.',
    );
    error.code = 'needs-migration';
    throw error;
  }

  const salt = crypto2.base64ToBytes(meta.crypto_salt);
  const iterations = meta.key_iterations ?? 600000;
  const key = await crypto2.deriveKey(masterPassword, salt, iterations);

  // An account with no key check predates it; the entries themselves then
  // stand as the test, and a wrong password simply decrypts nothing.
  if (meta.key_check && !(await crypto2.verifyKeyCheck(meta.key_check, key))) {
    const error = new Error('Incorrect master password');
    error.code = 'bad-password';
    throw error;
  }

  return key;
}

/// Step one of unlocking. Returns either a finished unlock, or a request for
/// the second factor, which the caller answers with completeSecondFactor.
///
/// The key is derived here even when a second factor is still outstanding, so
/// that the waiting step holds the derived key rather than the master password
/// itself.
export async function beginUnlock(email, masterPassword) {
  const session = await signInAnyVersion(email, masterPassword);
  const user = session.user || (await api.getUser(session.access_token));
  const key = await deriveAndVerifyKey(masterPassword, user);

  if (api.needsSecondFactor(session.access_token, user)) {
    const factor = api.verifiedFactors(user)[0];
    const challenge = await api.challengeFactor(session.access_token, factor.id);
    return {
      status: 'needs-second-factor',
      session,
      user,
      key,
      factorId: factor.id,
      challengeId: challenge.id,
    };
  }

  return { status: 'unlocked', session, user, key };
}

/// Step two, only when the account has a second factor.
export async function completeSecondFactor(
  session,
  key,
  factorId,
  challengeId,
  code,
) {
  const upgraded = await api.verifyFactor(
    session.access_token,
    factorId,
    challengeId,
    code,
  );
  const merged = { ...session, ...upgraded };
  const user = merged.user || (await api.getUser(merged.access_token));
  return { status: 'unlocked', session: merged, user, key };
}

/// Pulls every row and decrypts it. Rows that will not open are skipped rather
/// than failing the whole load, matching VaultService.fetchAll.
export async function loadEntries(accessToken, userId, key) {
  const rows = await api.fetchVaultRows(accessToken, userId);
  const entries = [];
  for (const row of rows) {
    try {
      const plaintext = await crypto2.decrypt(row.encrypted_data, key);
      entries.push(JSON.parse(plaintext));
    } catch {
      // Undecryptable row, most likely from a half-finished migration.
    }
  }
  return entries;
}

// ─── Matching entries to the page you are on ────────────────────────────────

function hostnameOf(value) {
  if (!value) return '';
  const trimmed = String(value).trim();
  if (!trimmed) return '';
  try {
    const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed)
      ? trimmed
      : `https://${trimmed}`;
    return new URL(withScheme).hostname.toLowerCase().replace(/^www\./, '');
  } catch {
    return '';
  }
}

/// Last two labels of a hostname. Good enough for the sites people actually
/// save; a two-part suffix like .co.uk falls back to matching more broadly,
/// which errs towards showing an entry rather than hiding it.
function registrableDomain(hostname) {
  const parts = hostname.split('.');
  return parts.length <= 2 ? hostname : parts.slice(-2).join('.');
}

export function entryMatchesUrl(entry, pageUrl) {
  const pageHost = hostnameOf(pageUrl);
  const entryHost = hostnameOf(entry.url);
  if (!pageHost || !entryHost) return false;
  if (pageHost === entryHost) return true;
  return registrableDomain(pageHost) === registrableDomain(entryHost);
}

/// Entries for the current page first, then everything else, so the popup can
/// show the likely one at the top without hiding the rest.
export function sortForUrl(entries, pageUrl) {
  const matching = [];
  const rest = [];
  for (const entry of entries) {
    (entryMatchesUrl(entry, pageUrl) ? matching : rest).push(entry);
  }
  return { matching, rest };
}
