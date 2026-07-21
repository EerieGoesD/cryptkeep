import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { grantPremium } from "../_shared/premium.ts";
import { rememberSubscription } from "../_shared/store_links.ts";
import {
  packageName,
  productIds,
  verifySubscription,
} from "../_shared/google_play.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-client-info, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

    if (requestPackageName !== packageName || !productIds.includes(requestProductId)) {
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
      const purchase = verification.purchase;
      const lineItem = verification.matchedLineItem;
      const expiresAt = new Date(verification.premiumUntil);

      await grantPremium(supabaseAdmin, user.id, {
        until: expiresAt,
        source: "google_play",
        productId: lineItem.productId ?? requestProductId,
        extra: {
          google_play_subscription_state: purchase.subscriptionState,
          google_play_acknowledgement_state: purchase.acknowledgementState,
          google_play_latest_order_id: lineItem.latestSuccessfulOrderId ??
            purchase.latestOrderId ?? null,
          google_play_base_plan_id: lineItem.offerDetails?.basePlanId ?? null,
          google_play_offer_id: lineItem.offerDetails?.offerId ?? null,
          google_play_test_purchase: Boolean(purchase.testPurchase),
        },
      });

      // The purchase token is what Google sends with a renewal notification, so
      // without this the renewal cannot be matched to an account and Pro lapses
      // while Google keeps charging.
      await rememberSubscription(supabaseAdmin, {
        userId: user.id,
        source: "google_play",
        storeSubscriptionId: purchaseToken,
        productId: lineItem.productId ?? requestProductId,
        expiresAt,
      });
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
