// Talking to Google Play about subscriptions.
//
// Moved here out of verify-google-play-purchase so the renewal endpoint asks
// Google the exact same question in the exact same way. Two copies of billing
// logic drift, and when they drift someone loses access they paid for.
//
// Nothing here trusts the caller: every answer comes from Google, authenticated
// with our own service account.

export const packageName = "com.eerie.cryptkeep";
export const productIds = ["cryptkeep_pro_monthly", "cryptkeep_pro_yearly"];

const androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
const tokenUrl = "https://oauth2.googleapis.com/token";

let cachedAccessToken: { token: string; expiresAtMs: number } | null = null;

type GoogleServiceAccount = {
  client_email: string;
  private_key: string;
};

export type SubscriptionPurchaseV2 = {
  subscriptionState?: string;
  acknowledgementState?: string;
  latestOrderId?: string;
  testPurchase?: Record<string, unknown>;
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
    latestSuccessfulOrderId?: string;
    offerDetails?: {
      basePlanId?: string;
      offerId?: string;
    };
  }>;
};

export type SubscriptionLineItem = NonNullable<
  SubscriptionPurchaseV2["lineItems"]
>[number];

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
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function decodeBase64Utf8(value: string): string {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

function parseServiceAccountJson(
  rawJson: string,
  source: string,
): GoogleServiceAccount {
  let parsed: Partial<GoogleServiceAccount>;
  try {
    parsed = JSON.parse(rawJson) as Partial<GoogleServiceAccount>;
  } catch {
    throw new Error(`${source} is not valid JSON`);
  }

  if (
    typeof parsed.client_email !== "string" ||
    typeof parsed.private_key !== "string"
  ) {
    throw new Error(`${source} is missing client_email or private_key`);
  }

  return {
    client_email: parsed.client_email,
    private_key: parsed.private_key.replaceAll("\\n", "\n"),
  };
}

function getServiceAccount(): GoogleServiceAccount {
  const rawBase64Json = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64");
  if (rawBase64Json) {
    return parseServiceAccountJson(
      decodeBase64Utf8(rawBase64Json),
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64",
    );
  }

  const rawJson = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  if (rawJson) {
    return parseServiceAccountJson(rawJson, "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  }

  const clientEmail = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL");
  const privateKey = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY");
  if (!clientEmail || !privateKey) {
    throw new Error("Missing Google Play service account credentials");
  }

  return {
    client_email: clientEmail,
    private_key: privateKey.replaceAll("\\n", "\n"),
  };
}

async function signJwt(serviceAccount: GoogleServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: androidPublisherScope,
    aud: tokenUrl,
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function getGoogleAccessToken(): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAtMs > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }

  const assertion = await signJwt(getServiceAccount());
  const response = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    console.error("Google OAuth token request failed:", body);
    throw new Error("Google OAuth token request failed");
  }

  const data = await response.json() as {
    access_token: string;
    expires_in: number;
  };
  cachedAccessToken = {
    token: data.access_token,
    expiresAtMs: Date.now() + data.expires_in * 1000,
  };
  return data.access_token;
}

export type SubscriptionVerification = {
  active: boolean;
  premiumUntil: string | null;
  purchase: SubscriptionPurchaseV2;
  matchedLineItem: SubscriptionLineItem | null;
};

/// Asks Google the current state of a subscription. This is the authority: a
/// renewal notification only tells us which subscription to ask about, never
/// what the answer is.
export async function verifySubscription(
  purchaseToken: string,
): Promise<SubscriptionVerification> {
  const accessToken = await getGoogleAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;

  const response = await fetch(url, {
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Accept": "application/json",
    },
  });

  if (!response.ok) {
    const body = await response.text();
    console.error("Google Play subscription verification failed:", body);
    throw new Error("Google Play subscription verification failed");
  }

  const purchase = await response.json() as SubscriptionPurchaseV2;
  const lineItem =
    purchase.lineItems?.find((item) => productIds.includes(item.productId ?? "")) ??
      null;
  const expiryTime = lineItem?.expiryTime ?? null;
  const expiryMs = expiryTime ? Date.parse(expiryTime) : Number.NaN;
  const hasFutureAccess = Number.isFinite(expiryMs) && expiryMs > Date.now();

  // Cancelled still counts: the person paid to the end of the period and keeps
  // Pro until then. Google only stops reporting a future expiry once it is
  // genuinely over.
  const accessStates = new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
  ]);

  return {
    active: Boolean(
      lineItem && hasFutureAccess &&
        accessStates.has(purchase.subscriptionState ?? ""),
    ),
    premiumUntil: hasFutureAccess ? new Date(expiryMs).toISOString() : null,
    purchase,
    matchedLineItem: lineItem,
  };
}
