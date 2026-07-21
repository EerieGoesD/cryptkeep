// Talks to the same Supabase project the apps use, over plain REST.
//
// Nothing here ever sees a plaintext password: the account password sent to
// Supabase is the derived auth password, and vault rows come back as ciphertext
// that only crypto.js can open.

import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const AUTH = `${SUPABASE_URL}/auth/v1`;
const REST = `${SUPABASE_URL}/rest/v1`;

function baseHeaders() {
  return {
    apikey: SUPABASE_ANON_KEY,
    'Content-Type': 'application/json',
  };
}

async function readError(response) {
  try {
    const body = await response.json();
    return body.error_description || body.msg || body.message || body.error || null;
  } catch {
    return null;
  }
}

/// Reads the claims out of a JWT without verifying it. We only use this to read
/// the `aal` claim, which decides whether a second factor is still outstanding.
/// The server is the thing actually enforcing it - this is just so we know to
/// ask.
export function decodeJwt(token) {
  try {
    const payload = token.split('.')[1];
    const padded = payload.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(padded + '='.repeat((4 - (padded.length % 4)) % 4)));
  } catch {
    return {};
  }
}

// ─── Sessions ───────────────────────────────────────────────────────────────

export async function signIn(email, password) {
  const response = await fetch(`${AUTH}/token?grant_type=password`, {
    method: 'POST',
    headers: baseHeaders(),
    body: JSON.stringify({ email: email.trim().toLowerCase(), password }),
  });
  if (!response.ok) {
    const message = await readError(response);
    const error = new Error(message || 'Sign in failed');
    error.status = response.status;
    throw error;
  }
  return response.json();
}

export async function refreshSession(refreshToken) {
  const response = await fetch(`${AUTH}/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: baseHeaders(),
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!response.ok) throw new Error('Session expired');
  return response.json();
}

export async function getUser(accessToken) {
  const response = await fetch(`${AUTH}/user`, {
    headers: { ...baseHeaders(), Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new Error('Could not read account');
  return response.json();
}

// ─── Second factor ──────────────────────────────────────────────────────────
// Signing in with a password only reaches aal1. If the account has a verified
// factor, the session has to be raised to aal2 before we treat it as unlocked.
// We fail closed: if any of this errors, the caller refuses to unlock rather
// than quietly working around the user's own second factor.

export function verifiedFactors(user) {
  return (user?.factors || []).filter((factor) => factor.status === 'verified');
}

export function needsSecondFactor(accessToken, user) {
  const claims = decodeJwt(accessToken);
  return verifiedFactors(user).length > 0 && claims.aal !== 'aal2';
}

export async function challengeFactor(accessToken, factorId) {
  const response = await fetch(`${AUTH}/factors/${factorId}/challenge`, {
    method: 'POST',
    headers: { ...baseHeaders(), Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({}),
  });
  if (!response.ok) {
    throw new Error((await readError(response)) || 'Could not start the second factor check');
  }
  return response.json();
}

export async function verifyFactor(accessToken, factorId, challengeId, code) {
  const response = await fetch(`${AUTH}/factors/${factorId}/verify`, {
    method: 'POST',
    headers: { ...baseHeaders(), Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({
      factor_id: factorId,
      challenge_id: challengeId,
      code: code.trim(),
    }),
  });
  if (!response.ok) {
    throw new Error((await readError(response)) || 'That code was not accepted');
  }
  return response.json();
}

// ─── Vault ──────────────────────────────────────────────────────────────────

export async function fetchVaultRows(accessToken, userId) {
  const url =
    `${REST}/vault_entries?select=encrypted_data&user_id=eq.${encodeURIComponent(userId)}` +
    '&order=created_at.desc';
  const response = await fetch(url, {
    headers: { ...baseHeaders(), Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new Error('Could not load the vault');
  return response.json();
}

// ─── Pro ────────────────────────────────────────────────────────────────────
// Mirrors PremiumService.isPremium: Pro lives on the account as a date, so
// whichever app the user subscribed in, it is already on here. The extension
// never sells anything itself.

export function isPremium(user) {
  const until =
    user?.app_metadata?.premium_until ?? user?.user_metadata?.premium_until;
  if (!until) return false;
  const parsed = Date.parse(until);
  return Number.isFinite(parsed) && parsed > Date.now();
}
