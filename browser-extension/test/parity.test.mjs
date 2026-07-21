// Proves the JavaScript crypto is byte-for-byte identical to the Dart original
// in lib/services/crypto_service.dart and lib/services/totp_service.dart.
//
// Run it with:   node browser-extension/test/parity.test.mjs
//
// If this fails, the extension will derive a different key and refuse to open a
// vault that is perfectly fine. Run it after touching either side.
//
// The expected values below were produced by the Dart code itself. To
// regenerate them, call the Dart functions with the same inputs and print the
// results, rather than copying anything from here.

import * as c from '../src/crypto.js';
import * as t from '../src/totp.js';

const MASTER = 'Correct Horse Battery Staple 42!';
// Deliberately padded and mixed case: deriveAuthPassword trims and lowercases
// the address, and deriveKey does not trim the password. Both quirks are load
// bearing.
const EMAIL = '  Test.User@Example.COM  ';
const SALT_B64 = 'AAECAwQFBgcICQoLDA0ODw==';

const EXPECTED = {
  authV2: '8SRIY3oqqmtU/GAOc3C0HIqCJnnS3T5jw0hUtbSulI8=',
  authV1: '6iufTgWcMJakI2dsiJIInfetxbJAI70X0dGhgXJEKVg=',
  key600k: 'qU8vP37bMEySIrrA63gOBEFqCL1VMi3cOB4BnXl5esg=',
  key100k: 'vQFkH10T9rpgirLHV6Rvqoe1S5VrC9aYTdGMOdG9Xvs=',
  totp6: '324550',
  totp8: '71205722',
};

// Ciphertext produced by the Dart side with key600k.
const DART_BLOB =
  'v2:ck1pU+uKYcO297+u:jHcuDomyeJaBdS2RpNZeew5ajEg0rDKxpi5ViTopL54h';
const DART_KEY_CHECK =
  'v2:IZIbZGCEBVqWxwhr:C0Pwjzk1/ewEgqYNiAxEpFeJcoFdYTNLDxFVZGZGYyxq8D0zWUs=';

let failures = 0;

function check(name, got, want) {
  const ok = got === want;
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
  if (!ok) console.log(`        got  ${got}\n        want ${want}`);
}

const salt = c.base64ToBytes(SALT_B64);

check('deriveAuthPassword', await c.deriveAuthPassword(MASTER, EMAIL), EXPECTED.authV2);
check('deriveAuthPasswordLegacy', await c.deriveAuthPasswordLegacy(MASTER, EMAIL), EXPECTED.authV1);

const key = await c.deriveKey(MASTER, salt, 600000);
check('deriveKey at 600k iterations', c.bytesToBase64(key), EXPECTED.key600k);
check(
  'deriveKey at 100k iterations',
  c.bytesToBase64(await c.deriveKey(MASTER, salt, 100000)),
  EXPECTED.key100k,
);

check('decrypts ciphertext written by the app', await c.decrypt(DART_BLOB, key), '{"hello":"world"}');
check(
  'accepts the key check written by the app',
  String(await c.verifyKeyCheck(DART_KEY_CHECK, key)),
  'true',
);
check(
  'rejects the key check under a wrong password',
  String(await c.verifyKeyCheck(DART_KEY_CHECK, await c.deriveKey('wrong', salt, 600000))),
  'false',
);

const mine = await c.encrypt('round trip', key);
check(
  'our ciphertext has the v2 layout the app expects',
  String(/^v2:[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$/.test(mine)),
  'true',
);
check('our own round trip', await c.decrypt(mine, key), 'round trip');

const at = new Date(1700000000000);
check('totp, 6 digits, sha1, 30s', await t.generate({ secret: 'JBSWY3DPEHPK3PXP' }, at), EXPECTED.totp6);
check(
  'totp, 8 digits, sha256, 60s',
  await t.generate(
    { secret: 'JBSWY3DPEHPK3PXP', digits: 8, algorithm: 'SHA256', period: 60 },
    at,
  ),
  EXPECTED.totp8,
);

console.log(failures === 0 ? '\nAll match.' : `\n${failures} mismatch.`);
process.exit(failures === 0 ? 0 : 1);
