import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const packageName = "com.eerie.cryptkeep";
const productId = "cryptkeep_pro_monthly";
const androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
const tokenUrl = "https://oauth2.googleapis.com/token";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-client-info, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

let cachedAccessToken: { token: string; expiresAtMs: number } | null = null;

type GoogleServiceAccount = {
  client_email: string;
  private_key: string;
};

type SubscriptionPurchaseV2 = {
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

type SubscriptionLineItem = NonNullable<SubscriptionPurchaseV2["lineItems"]>[number];

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function base64UrlEncode(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
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

function parseServiceAccountJson(rawJson: string, source: string): GoogleServiceAccount {
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

  const data = await response.json() as { access_token: string; expires_in: number };
  cachedAccessToken = {
    token: data.access_token,
    expiresAtMs: Date.now() + data.expires_in * 1000,
  };
  return data.access_token;
}

async function verifySubscription(purchaseToken: string): Promise<{
  active: boolean;
  premiumUntil: string | null;
  purchase: SubscriptionPurchaseV2;
  matchedLineItem: SubscriptionLineItem | null;
}> {
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
  const lineItem = purchase.lineItems?.find((item) => item.productId === productId) ?? null;
  const expiryTime = lineItem?.expiryTime ?? null;
  const expiryMs = expiryTime ? Date.parse(expiryTime) : Number.NaN;
  const hasFutureAccess = Number.isFinite(expiryMs) && expiryMs > Date.now();
  const accessStates = new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
  ]);

  return {
    active: Boolean(lineItem && hasFutureAccess && accessStates.has(purchase.subscriptionState ?? "")),
    premiumUntil: hasFutureAccess ? new Date(expiryMs).toISOString() : null,
    purchase,
    matchedLineItem: lineItem,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) {
      return json({ error: "Missing authorization token" }, 401);
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(jwt);
    if (userError || !userData.user) {
      return json({ error: "Invalid user session" }, 401);
    }

    const body = await req.json();
    const requestPackageName = String(body.packageName ?? "");
    const requestProductId = String(body.productId ?? "");
    const purchaseToken = String(body.purchaseToken ?? "");

    if (requestPackageName !== packageName || requestProductId !== productId) {
      return json({ error: "Invalid package name or product ID" }, 400);
    }
    if (!purchaseToken) {
      return json({ error: "Missing purchase token" }, 400);
    }

    const verification = await verifySubscription(purchaseToken);
    if (!verification.matchedLineItem) {
      return json({
        active: false,
        error: "Purchase token is not for the expected subscription product",
      }, 400);
    }

    if (verification.active && verification.premiumUntil) {
      const user = userData.user;
      const currentAppMetadata = user.app_metadata ?? {};
      const purchase = verification.purchase;
      const lineItem = verification.matchedLineItem;

      const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
        app_metadata: {
          ...currentAppMetadata,
          premium_until: verification.premiumUntil,
          premium_source: "google_play",
          premium_product_id: productId,
          google_play_subscription_state: purchase.subscriptionState,
          google_play_acknowledgement_state: purchase.acknowledgementState,
          google_play_latest_order_id: lineItem.latestSuccessfulOrderId ?? purchase.latestOrderId ?? null,
          google_play_base_plan_id: lineItem.offerDetails?.basePlanId ?? null,
          google_play_offer_id: lineItem.offerDetails?.offerId ?? null,
          google_play_test_purchase: Boolean(purchase.testPurchase),
        },
      });

      if (updateError) {
        console.error("Failed to update premium app metadata:", updateError);
        return json({ error: "Failed to update premium entitlement" }, 500);
      }
    }

    return json({
      active: verification.active,
      premium_until: verification.premiumUntil,
      subscription_state: verification.purchase.subscriptionState,
      acknowledgement_state: verification.purchase.acknowledgementState,
      product_id: verification.matchedLineItem.productId,
      expiry_time: verification.matchedLineItem.expiryTime,
      is_test_purchase: Boolean(verification.purchase.testPurchase),
    });
  } catch (err) {
    console.error("verify-google-play-purchase failed:", err);
    return json({ error: "Google Play verification failed" }, 500);
  }
});
