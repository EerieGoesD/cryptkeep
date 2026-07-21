// A faithful port of lib/services/crypto_service.dart.
//
// Every byte here has to match the Dart side exactly, or the extension will
// derive a different key and silently fail to open a vault that is perfectly
// fine. The details that matter and are easy to get wrong:
//
//   - deriveAuthPassword TRIMS the master password. deriveKey does NOT.
//     That asymmetry is in the Dart original and is deliberate here.
//   - v2 ciphertext is "v2:<base64 nonce>:<base64 ciphertext+tag>", AES-256-GCM
//     with a 12-byte nonce and a 128-bit tag appended to the ciphertext, which
//     is exactly the layout WebCrypto expects.
//   - Legacy ciphertext is "<base64 iv>:<base64 ciphertext>", AES-256-CBC with
//     PKCS#7 padding. Old entries still decrypt this way.

const KEY_CHECK_PLAINTEXT = 'cryptkeep-key-check-v2';

const te = new TextEncoder();
const td = new TextDecoder();

export function bytesToBase64(bytes) {
  let binary = '';
  const view = new Uint8Array(bytes);
  for (let i = 0; i < view.length; i++) binary += String.fromCharCode(view[i]);
  return btoa(binary);
}

export function base64ToBytes(value) {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

async function pbkdf2(password, salt, iterations) {
  const baseKey = await crypto.subtle.importKey(
    'raw',
    te.encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    baseKey,
    256,
  );
  return new Uint8Array(bits);
}

// ─── Auth password ──────────────────────────────────────────────────────────
// The master password itself never leaves the device. What Supabase receives
// as the account password is this separate derivation of it.

export async function deriveAuthPassword(masterPassword, email) {
  const salt = te.encode(`${email.trim().toLowerCase()}:auth-v2`);
  const bits = await pbkdf2(masterPassword.trim(), salt, 100000);
  return bytesToBase64(bits);
}

// Pre-v2 accounts that have not signed in since the change. Single SHA-256.
export async function deriveAuthPasswordLegacy(masterPassword, email) {
  const input = te.encode(
    `${masterPassword.trim()}:${email.trim().toLowerCase()}:auth`,
  );
  const digest = await crypto.subtle.digest('SHA-256', input);
  return bytesToBase64(digest);
}

// ─── Vault key ──────────────────────────────────────────────────────────────
// Note: no trim. Matches CryptoService.deriveKey.

export async function deriveKey(masterPassword, salt, iterations) {
  return pbkdf2(masterPassword, salt, iterations);
}

// ─── Encrypt / decrypt ──────────────────────────────────────────────────────

async function importAesKey(keyBytes, algorithm, usages) {
  return crypto.subtle.importKey('raw', keyBytes, algorithm, false, usages);
}

export async function encrypt(plaintext, keyBytes) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const key = await importAesKey(keyBytes, 'AES-GCM', ['encrypt']);
  const output = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    te.encode(plaintext),
  );
  return `v2:${bytesToBase64(nonce)}:${bytesToBase64(output)}`;
}

export async function decrypt(encryptedText, keyBytes) {
  if (encryptedText.startsWith('v2:')) {
    return decryptGcm(encryptedText, keyBytes);
  }
  return decryptCbcLegacy(encryptedText, keyBytes);
}

async function decryptGcm(encryptedText, keyBytes) {
  const parts = encryptedText.split(':');
  if (parts.length !== 3) throw new Error('Invalid v2 format');
  const nonce = base64ToBytes(parts[1]);
  const data = base64ToBytes(parts[2]);
  const key = await importAesKey(keyBytes, 'AES-GCM', ['decrypt']);
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    data,
  );
  return td.decode(plain);
}

async function decryptCbcLegacy(encryptedText, keyBytes) {
  const parts = encryptedText.split(':');
  if (parts.length !== 2) throw new Error('Invalid format');
  const iv = base64ToBytes(parts[0]);
  const data = base64ToBytes(parts[1]);
  const key = await importAesKey(keyBytes, 'AES-CBC', ['decrypt']);
  const plain = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, data);
  return td.decode(plain);
}

// ─── Key check ──────────────────────────────────────────────────────────────
// A known string encrypted with the vault key, stored on the account. If it
// decrypts back to itself, the master password was right. This is what tells a
// wrong password apart from a corrupted vault.

export async function verifyKeyCheck(encryptedCheck, keyBytes) {
  try {
    return (await decrypt(encryptedCheck, keyBytes)) === KEY_CHECK_PLAINTEXT;
  } catch {
    return false;
  }
}
