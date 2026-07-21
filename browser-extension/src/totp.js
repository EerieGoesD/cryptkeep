// A port of lib/services/totp_service.dart (TOTP, RFC 6238).
//
// Entirely local: a code is derived from the stored seed and the clock. The
// seed lives inside the vault entry, encrypted like any password.

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

// Accepts lower case, padding, spaces and dashes, because that is how sites
// print them.
export function decodeBase32(input) {
  const clean = input.toUpperCase().replace(/[=\s-]/g, '');
  if (!clean) throw new Error('Empty secret');

  let bits = 0;
  let value = 0;
  const out = [];
  for (const char of clean) {
    const index = BASE32_ALPHABET.indexOf(char);
    if (index < 0) throw new Error(`Not a valid key (bad character "${char}")`);
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

function hashName(algorithm) {
  switch ((algorithm || '').toUpperCase().replace(/-/g, '')) {
    case 'SHA256':
      return 'SHA-256';
    case 'SHA512':
      return 'SHA-512';
    default:
      return 'SHA-1';
  }
}

/// The current code for a totp config, in the shape stored on a vault entry:
/// { secret, digits, period, algorithm }.
export async function generate(config, at = new Date()) {
  const digits = config.digits ?? 6;
  const period = config.period ?? 30;
  const keyBytes = decodeBase32(config.secret);

  const counter = Math.floor(Math.floor(at.getTime() / 1000) / period);

  // 8-byte big-endian counter.
  const message = new Uint8Array(8);
  new DataView(message.buffer).setBigUint64(0, BigInt(counter), false);

  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: hashName(config.algorithm) },
    false,
    ['sign'],
  );
  const hash = new Uint8Array(await crypto.subtle.sign('HMAC', key, message));

  // Dynamic truncation (RFC 4226): the low 4 bits of the last byte pick where
  // to read 4 bytes from, and the top bit is dropped so the result is always
  // positive.
  const offset = hash[hash.length - 1] & 0x0f;
  const binary =
    ((hash[offset] & 0x7f) << 24) |
    ((hash[offset + 1] & 0xff) << 16) |
    ((hash[offset + 2] & 0xff) << 8) |
    (hash[offset + 3] & 0xff);

  const modulus = 10 ** digits;
  return String(binary % modulus).padStart(digits, '0');
}

/// Seconds until the current code is replaced, for the countdown ring.
export function secondsRemaining(config, at = new Date()) {
  const period = config.period ?? 30;
  return period - (Math.floor(at.getTime() / 1000) % period);
}
