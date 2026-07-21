// The service worker. It is the only place the vault key and the decrypted
// entries exist, and it answers questions from the popup.
//
// Everything lives in chrome.storage.session, which is held in memory, never
// written to disk, cleared when the browser closes, and not reachable from web
// pages. A service worker can be shut down at any moment, so keeping state
// there rather than in a variable is what stops the vault relocking itself at
// random.

import { DEFAULT_AUTO_LOCK_MINUTES, WEB_APP_URL } from './config.js';
import * as api from './api.js';
import * as vault from './vault.js';
import { bytesToBase64, base64ToBytes } from './crypto.js';
import { fillCredentials } from './filler.js';
import { generate as generateTotp, secondsRemaining } from './totp.js';

const ALARM_AUTO_LOCK = 'cryptkeep-auto-lock';

async function readState() {
  const { state } = await chrome.storage.session.get('state');
  return state || null;
}

async function writeState(state) {
  await chrome.storage.session.set({ state });
}

async function lock() {
  await chrome.storage.session.remove('state');
  await chrome.alarms.clear(ALARM_AUTO_LOCK);
}

async function touch() {
  const state = await readState();
  if (!state) return;
  state.lastActivity = Date.now();
  await writeState(state);
  await scheduleAutoLock(state.autoLockMinutes);
}

async function scheduleAutoLock(minutes) {
  // Chrome clamps anything under a minute, so ask for at least that and let
  // the handler check the real idle time when it fires.
  await chrome.alarms.create(ALARM_AUTO_LOCK, {
    delayInMinutes: Math.max(1, minutes),
  });
}

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== ALARM_AUTO_LOCK) return;
  const state = await readState();
  if (!state) return;
  const idleMs = Date.now() - state.lastActivity;
  if (idleMs >= state.autoLockMinutes * 60 * 1000) {
    await lock();
  } else {
    // Activity happened after the alarm was set. Wait out the remainder.
    await scheduleAutoLock(state.autoLockMinutes - idleMs / 60000);
  }
});

/// Returns the live state, or null if the vault is locked or has gone stale.
async function requireUnlocked() {
  const state = await readState();
  if (!state || !state.key) return null;
  if (Date.now() - state.lastActivity >= state.autoLockMinutes * 60 * 1000) {
    await lock();
    return null;
  }
  return state;
}

/// Keeps the Supabase session alive so a long-lived unlock does not start
/// failing its requests part way through.
async function validAccessToken(state) {
  if (Date.now() < state.expiresAt - 60_000) return state.accessToken;
  const refreshed = await api.refreshSession(state.refreshToken);
  state.accessToken = refreshed.access_token;
  state.refreshToken = refreshed.refresh_token;
  state.expiresAt = Date.now() + refreshed.expires_in * 1000;
  await writeState(state);
  return state.accessToken;
}

async function storeUnlocked(result, autoLockMinutes) {
  const state = {
    key: bytesToBase64(result.key),
    accessToken: result.session.access_token,
    refreshToken: result.session.refresh_token,
    expiresAt: Date.now() + result.session.expires_in * 1000,
    userId: result.user.id,
    email: result.user.email,
    premium: api.isPremium(result.user),
    autoLockMinutes,
    lastActivity: Date.now(),
    entries: [],
  };

  state.entries = await vault.loadEntries(
    state.accessToken,
    state.userId,
    base64ToBytes(state.key),
  );

  await writeState(state);
  await scheduleAutoLock(autoLockMinutes);
  return state;
}

// Entries the popup is allowed to see. Passwords, notes and two-factor seeds
// stay in the service worker and are handed over one at a time, on request.
function publicEntry(entry) {
  return {
    id: entry.id,
    title: entry.title,
    username: entry.username,
    url: entry.url || '',
    category: entry.category || '',
    hasTotp: !!entry.totp,
    isPasskey: !!entry.passkey,
  };
}

const handlers = {
  async getState() {
    const state = await requireUnlocked();
    const { autoLockMinutes } = await chrome.storage.local.get('autoLockMinutes');
    if (!state) {
      return {
        locked: true,
        autoLockMinutes: autoLockMinutes ?? DEFAULT_AUTO_LOCK_MINUTES,
        webAppUrl: WEB_APP_URL,
      };
    }
    return {
      locked: false,
      email: state.email,
      premium: state.premium,
      count: state.entries.length,
      autoLockMinutes: state.autoLockMinutes,
      webAppUrl: WEB_APP_URL,
    };
  },

  async unlock({ email, masterPassword }) {
    const { autoLockMinutes } = await chrome.storage.local.get('autoLockMinutes');
    const minutes = autoLockMinutes ?? DEFAULT_AUTO_LOCK_MINUTES;
    const result = await vault.beginUnlock(email, masterPassword);

    if (result.status === 'needs-second-factor') {
      await chrome.storage.session.set({
        pendingMfa: {
          session: result.session,
          key: bytesToBase64(result.key),
          factorId: result.factorId,
          challengeId: result.challengeId,
          autoLockMinutes: minutes,
        },
      });
      return { needsSecondFactor: true };
    }

    await storeUnlocked(result, minutes);
    return { ok: true };
  },

  async submitSecondFactor({ code }) {
    const { pendingMfa } = await chrome.storage.session.get('pendingMfa');
    if (!pendingMfa) return { error: 'Start again - that sign in has expired.' };

    const result = await vault.completeSecondFactor(
      pendingMfa.session,
      base64ToBytes(pendingMfa.key),
      pendingMfa.factorId,
      pendingMfa.challengeId,
      code,
    );
    await chrome.storage.session.remove('pendingMfa');
    await storeUnlocked(result, pendingMfa.autoLockMinutes);
    return { ok: true };
  },

  async lock() {
    await chrome.storage.session.remove('pendingMfa');
    await lock();
    return { ok: true };
  },

  async list({ pageUrl }) {
    const state = await requireUnlocked();
    if (!state) return { locked: true };
    await touch();
    const { matching, rest } = vault.sortForUrl(state.entries, pageUrl);
    return {
      matching: matching.map(publicEntry),
      rest: rest.map(publicEntry),
    };
  },

  async refresh() {
    const state = await requireUnlocked();
    if (!state) return { locked: true };
    const token = await validAccessToken(state);
    state.entries = await vault.loadEntries(
      token,
      state.userId,
      base64ToBytes(state.key),
    );
    state.lastActivity = Date.now();
    await writeState(state);
    return { ok: true, count: state.entries.length };
  },

  async fill({ entryId, tabId }) {
    const state = await requireUnlocked();
    if (!state) return { locked: true };
    const entry = state.entries.find((e) => e.id === entryId);
    if (!entry) return { error: 'That entry is gone. Try refreshing.' };
    if (entry.passkey) {
      return {
        error: 'Passkeys cannot be used from the extension yet. Use the app.',
      };
    }

    const [injection] = await chrome.scripting.executeScript({
      target: { tabId },
      func: fillCredentials,
      args: [entry.username || '', entry.password || ''],
    });

    await touch();

    switch (injection?.result) {
      case 'ok':
        return { ok: true };
      case 'username-only':
        return { ok: true, message: 'Filled the username - no password box on this page yet.' };
      default:
        return { error: 'No login boxes found on this page.' };
    }
  },

  /// Hands over one secret, for one copy. Kept out of the popup until asked.
  async reveal({ entryId, field }) {
    const state = await requireUnlocked();
    if (!state) return { locked: true };
    const entry = state.entries.find((e) => e.id === entryId);
    if (!entry) return { error: 'That entry is gone. Try refreshing.' };
    await touch();
    return { value: entry[field] ?? '' };
  },

  async totp({ entryId }) {
    const state = await requireUnlocked();
    if (!state) return { locked: true };
    if (!state.premium) return { error: 'pro-required' };
    const entry = state.entries.find((e) => e.id === entryId);
    if (!entry?.totp) return { error: 'This entry has no two-factor code.' };
    await touch();

    return {
      code: await generateTotp(entry.totp),
      secondsRemaining: secondsRemaining(entry.totp),
    };
  },

  async setAutoLock({ minutes }) {
    await chrome.storage.local.set({ autoLockMinutes: minutes });
    const state = await readState();
    if (state) {
      state.autoLockMinutes = minutes;
      await writeState(state);
      await scheduleAutoLock(minutes);
    }
    return { ok: true };
  },
};

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const handler = handlers[message?.type];
  if (!handler) {
    sendResponse({ error: 'Unknown request' });
    return false;
  }
  handler(message.payload || {})
    .then(sendResponse)
    .catch((error) => sendResponse({ error: error.message || String(error) }));
  // Keeps the message channel open for the async reply above.
  return true;
});
