import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { grantPremium } from "../_shared/premium.ts";
import { rememberSubscription } from "../_shared/store_links.ts";

// Must match the App Store Connect subscription Product IDs and the app code.
const productIds = ["cryptkeep_pro_monthly", "cryptkeep_pro_yearly"];

// Apple's verifyReceipt endpoints. Verify against production first; if Apple
// replies 21007 the receipt is from the sandbox, so retry the sandbox endpoint.
const verifyReceiptProd = "https://buy.itunes.apple.com/verifyReceipt";
const verifyReceiptSandbox = "https://sandbox.itunes.apple.com/verifyReceipt";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, x-client-info, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

type ReceiptEntry = {
  product_id?: string;
  expires_date_ms?: string;
  original_transaction_id?: string;
};

type VerifyResponse = {
  status: number;
  latest_receipt_info?: ReceiptEntry[];
  receipt?: { in_app?: ReceiptEntry[] };
};

async function callApple(
  url: string,
  receiptData: string,
  sharedSecret: string,
): Promise<VerifyResponse> {
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      "receipt-data": receiptData,
      "password": sharedSecret,
      "exclude-old-transactions": true,
    }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    console.error("Apple verifyReceipt HTTP error:", resp.status, text);
    throw new Error(`Apple verifyReceipt HTTP ${resp.status}`);
  }
  return await resp.json() as VerifyResponse;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const sharedSecret = Deno.env.get("APP_STORE_SHARED_SECRET");
    if (!sharedSecret) {
      console.error("Missing APP_STORE_SHARED_SECRET env var");
      return json({ error: "Server not configured" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) {
      return json({ error: "Missing authorization token" }, 401);
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: userData, error: userError } = await supabaseAdmin.auth
      .getUser(jwt);
    if (userError || !userData.user) {
      return json({ error: "Invalid user session" }, 401);
    }

    const body = await req.json();
    const receiptData = String(body.receiptData ?? "");
    const requestProductId = String(body.productId ?? "");
    if (!receiptData) {
      return json({ error: "Missing receipt data" }, 400);
    }
    if (requestProductId && !productIds.includes(requestProductId)) {
      return json({ error: "Invalid product ID" }, 400);
    }

    let result = await callApple(verifyReceiptProd, receiptData, sharedSecret);
    if (result.status === 21007) {
      result = await callApple(verifyReceiptSandbox, receiptData, sharedSecret);
    }
    if (result.status !== 0) {
      console.error("Apple verifyReceipt status:", result.status);
      return json(
        { active: false, error: `Apple verification failed (${result.status})` },
        400,
      );
    }

    // Find the latest expiry across our subscription products.
    const entries = result.latest_receipt_info ?? result.receipt?.in_app ?? [];
    let latestExpiryMs = 0;
    let matchedProductId: string | null = null;
    let originalTransactionId: string | null = null;
    for (const entry of entries) {
      if (!entry.product_id || !productIds.includes(entry.product_id)) continue;
      const ms = entry.expires_date_ms ? Number(entry.expires_date_ms) : 0;
      if (Number.isFinite(ms) && ms > latestExpiryMs) {
        latestExpiryMs = ms;
        matchedProductId = entry.product_id;
        originalTransactionId = entry.original_transaction_id ?? null;
      }
    }

    const active = latestExpiryMs > Date.now();
    const premiumUntil = active ? new Date(latestExpiryMs).toISOString() : null;

    if (active && premiumUntil) {
      const user = userData.user;

      await grantPremium(supabaseAdmin, user.id, {
        until: new Date(latestExpiryMs),
        source: "app_store",
        productId: matchedProductId,
      });

      // The original transaction id is the only thing Apple sends with a
      // renewal notification, so without this the renewal cannot be matched to
      // an account and Pro lapses while Apple keeps charging.
      if (originalTransactionId) {
        await rememberSubscription(supabaseAdmin, {
          userId: user.id,
          source: "app_store",
          storeSubscriptionId: originalTransactionId,
          productId: matchedProductId,
          expiresAt: new Date(latestExpiryMs),
        });
      } else {
        console.warn(
          `No original_transaction_id on the receipt for ${user.id}; renewals will not be picked up`,
        );
      }
    }

    return json({
      active,
      premium_until: premiumUntil,
      product_id: matchedProductId,
    });
  } catch (err) {
    console.error("verify-app-store-purchase failed:", err);
    return json({ error: "App Store verification failed" }, 500);
  }
});
