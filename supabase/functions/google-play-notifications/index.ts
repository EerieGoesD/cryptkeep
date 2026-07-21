// Google tells us the moment an Android subscription renews, lapses or is
// refunded, with no app running. This is what stops Pro quietly expiring while
// Google is still charging someone.
//
// Google sends these through Cloud Pub/Sub, which posts them here.
//
// The notification is treated as a nudge and nothing more. It says which
// subscription changed; it does not get to say what changed. We then ask Google
// directly, authenticated with our own service account, and act on that answer.
// A forged notification therefore gains an attacker nothing - the worst it can
// do is make us ask Google a question we already know the answer to.
//
// Deploy with JWT verification off, because Google is not a signed-in user:
//   supabase functions deploy google-play-notifications --no-verify-jwt

import "@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, grantPremium, revokePremium } from "../_shared/premium.ts";
import { findAccountForSubscription, rememberSubscription } from "../_shared/store_links.ts";
import { packageName, verifySubscription } from "../_shared/google_play.ts";

const admin = adminClient();

// Optional. If set, Pub/Sub must be configured to call this function with
// ?token=<the same value>, which keeps strangers from hammering the endpoint.
const sharedToken = Deno.env.get("GOOGLE_PLAY_NOTIFICATIONS_TOKEN");

type DeveloperNotification = {
  packageName?: string;
  subscriptionNotification?: {
    notificationType?: number;
    purchaseToken?: string;
    subscriptionId?: string;
  };
  testNotification?: Record<string, unknown>;
};

function decodeBase64Utf8(value: string): string {
  const binary = atob(value.replaceAll("-", "+").replaceAll("_", "/"));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (sharedToken) {
    const provided = new URL(req.url).searchParams.get("token");
    if (provided !== sharedToken) {
      return new Response("Forbidden", { status: 403 });
    }
  }

  let notification: DeveloperNotification;
  try {
    const envelope = await req.json() as { message?: { data?: string } };
    if (!envelope.message?.data) {
      // Pub/Sub sends an empty check when you first hook it up.
      return new Response("OK", { status: 200 });
    }
    notification = JSON.parse(decodeBase64Utf8(envelope.message.data));
  } catch (err) {
    console.error("Unreadable notification:", err);
    // Malformed and retrying will not help, so accept it and move on.
    return new Response("OK", { status: 200 });
  }

  if (notification.testNotification) {
    console.log("Google Play test notification received");
    return new Response("OK", { status: 200 });
  }

  if (notification.packageName && notification.packageName !== packageName) {
    console.warn(`Notification for another app: ${notification.packageName}`);
    return new Response("OK", { status: 200 });
  }

  const purchaseToken = notification.subscriptionNotification?.purchaseToken;
  if (!purchaseToken) {
    // Not a subscription event, for example a one-off product or a voided
    // purchase notification. Nothing for us to do.
    return new Response("OK", { status: 200 });
  }

  try {
    const userId = await findAccountForSubscription(
      admin,
      "google_play",
      purchaseToken,
    );

    if (!userId) {
      // Bought before the link table existed. Nothing to update until that
      // person next opens the Pro screen, which records the link.
      console.warn("No account on file for this Google Play subscription");
      return new Response("OK", { status: 200 });
    }

    // Google is the authority, not the message we just received.
    const verification = await verifySubscription(purchaseToken);

    if (verification.active && verification.premiumUntil) {
      const until = new Date(verification.premiumUntil);
      await grantPremium(admin, userId, {
        until,
        source: "google_play",
        productId: verification.matchedLineItem?.productId ?? null,
        extra: {
          google_play_subscription_state: verification.purchase.subscriptionState,
        },
      });
      await rememberSubscription(admin, {
        userId,
        source: "google_play",
        storeSubscriptionId: purchaseToken,
        productId: verification.matchedLineItem?.productId ?? null,
        expiresAt: until,
      });
      console.log(`Pro for ${userId} now runs to ${verification.premiumUntil}`);
    } else {
      await revokePremium(admin, userId, "google_play");
      console.log(`Pro ended for ${userId}`);
    }

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("Could not process the notification:", err);
    // A non-2xx makes Pub/Sub deliver it again later, which is what we want
    // when Google or the database was briefly unreachable.
    return new Response("Retry", { status: 500 });
  }
});
