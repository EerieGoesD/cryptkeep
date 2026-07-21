// Talking to Apple about subscriptions, using the App Store Server API.
//
// This is the current way to ask Apple whether someone is still subscribed.
// The older verifyReceipt endpoint that verify-app-store-purchase still uses
// has been deprecated by Apple; moving that one over is worth doing, but it
// works today and is left alone for now.
//
// Needs four values in the function secrets, all from App Store Connect:
//
//   APP_STORE_KEY_ID       the id of an In-App Purchase key
//   APP_STORE_ISSUER_ID    the issuer id shown on the Keys page
//   APP_STORE_PRIVATE_KEY  the contents of the .p8 file that key downloads
//   APP_STORE_BUNDLE_ID    the app's bundle id
//
// The .p8 downloads once and cannot be downloaded again, so keep a copy.

const PRODUCTION = "https://api.storekit.itunes.apple.com";
const SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

let cachedToken: { token: string; expiresAtMs: number } | null = null;

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function base64UrlEncode(input: string | Uint8Array): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/// Reads the claims out of one of Apple's signed blobs without checking the
/// signature.
///
/// That is safe here only because of how it is used: every value we act on
/// comes back from an authenticated HTTPS call we made to Apple ourselves. When
/// this is used on an incoming notification, it is purely to find out which
/// subscription to go and ask Apple about, never to decide the answer.
export function decodeSignedPayload<T>(jws: string): T {
  const payload = jws.split(".")[1];
  const padded = payload.replaceAll("-", "+").replaceAll("_", "/");
  const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return JSON.parse(new TextDecoder().decode(bytes)) as T;
}

/// Apple wants a short-lived signed token on every request, proving the call is
/// from us.
async function appleToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAtMs > Date.now() + 60_000) {
    return cachedToken.token;
  }

  const keyId = required("APP_STORE_KEY_ID");
  const issuerId = required("APP_STORE_ISSUER_ID");
  const bundleId = required("APP_STORE_BUNDLE_ID");
  const privateKey = required("APP_STORE_PRIVATE_KEY").replaceAll("\\n", "\n");

  const now = Math.floor(Date.now() / 1000);
  // Apple rejects anything longer than an hour.
  const expiresAt = now + 45 * 60;

  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = {
    iss: issuerId,
    iat: now,
    exp: expiresAt,
    aud: "appstoreconnect-v1",
    bid: bundleId,
  };

  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${
    base64UrlEncode(JSON.stringify(payload))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  // WebCrypto returns the raw r||s pair, which is exactly the shape ES256
  // wants in a JWT.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  const token = `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
  cachedToken = { token, expiresAtMs: expiresAt * 1000 };
  return token;
}

type TransactionInfo = {
  originalTransactionId?: string;
  productId?: string;
  expiresDate?: number;
};

type LastTransaction = {
  originalTransactionId?: string;
  status?: number;
  signedTransactionInfo?: string;
};

type StatusResponse = {
  data?: Array<{ lastTransactions?: LastTransaction[] }>;
};

export type AppleSubscription = {
  active: boolean;
  expiresAt: Date | null;
  productId: string | null;
};

// Apple's subscription status codes.
const STATUS_ACTIVE = 1;
const STATUS_BILLING_RETRY = 3;
const STATUS_GRACE_PERIOD = 4;
const STATUS_REVOKED = 5;

async function fetchStatus(
  host: string,
  originalTransactionId: string,
  token: string,
): Promise<Response> {
  return fetch(
    `${host}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
}

/// Asks Apple the current state of a subscription. This is the authority.
///
/// Tries production first and falls back to sandbox, because a test purchase
/// looks identical from the outside and only one of the two hosts knows about
/// any given transaction.
export async function getSubscription(
  originalTransactionId: string,
): Promise<AppleSubscription> {
  const token = await appleToken();

  let response = await fetchStatus(PRODUCTION, originalTransactionId, token);
  if (response.status === 404) {
    response = await fetchStatus(SANDBOX, originalTransactionId, token);
  }

  if (!response.ok) {
    const body = await response.text();
    console.error("Apple subscription status failed:", response.status, body);
    throw new Error(`Apple subscription status HTTP ${response.status}`);
  }

  const result = await response.json() as StatusResponse;

  // Find the entry for this exact subscription. An account can hold several.
  let best: { expiresAt: Date; productId: string | null; active: boolean } | null =
    null;

  for (const group of result.data ?? []) {
    for (const transaction of group.lastTransactions ?? []) {
      if (
        transaction.originalTransactionId &&
        transaction.originalTransactionId !== originalTransactionId
      ) {
        continue;
      }
      if (!transaction.signedTransactionInfo) continue;

      const info = decodeSignedPayload<TransactionInfo>(
        transaction.signedTransactionInfo,
      );
      if (!info.expiresDate) continue;

      const expiresAt = new Date(info.expiresDate);

      // A refund cuts access off immediately, whatever the expiry says.
      const revoked = transaction.status === STATUS_REVOKED;
      const stillPaidFor = [
        STATUS_ACTIVE,
        STATUS_BILLING_RETRY,
        STATUS_GRACE_PERIOD,
      ].includes(transaction.status ?? -1);

      const active = !revoked && stillPaidFor && expiresAt.getTime() > Date.now();

      if (!best || expiresAt.getTime() > best.expiresAt.getTime()) {
        best = { expiresAt, productId: info.productId ?? null, active };
      }
    }
  }

  if (!best) return { active: false, expiresAt: null, productId: null };
  return {
    active: best.active,
    expiresAt: best.expiresAt,
    productId: best.productId,
  };
}
