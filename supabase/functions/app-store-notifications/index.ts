// Apple tells us the moment an iPhone or Mac subscription renews, lapses or is
// refunded, with no app running. This is what stops Pro quietly expiring while
// Apple is still charging someone.
//
// Set the address of this function in App Store Connect, under your app's
// General Information, as the App Store Server Notifications URL (version 2).
// There are separate boxes for production and sandbox; the same address works
// for both.
//
// The notification is treated as a nudge and nothing more. We read which
// subscription changed out of it, then ask Apple directly, authenticated with
// our own key, and act on that answer. A forged notification therefore gains an
// attacker nothing: it can only make us ask Apple about a subscription, and
// Apple tells us the truth regardless of what the message claimed. The account
// it maps to comes from our own records, not from anything Apple sends.
//
// Deploy with JWT verification off, because Apple is not a signed-in user:
//   supabase functions deploy app-store-notifications --no-verify-jwt

import "@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, grantPremium, revokePremium } from "../_shared/premium.ts";
import { findAccountForSubscription, rememberSubscription } from "../_shared/store_links.ts";
import { decodeSignedPayload, getSubscription } from "../_shared/app_store.ts";

const admin = adminClient();

type NotificationPayload = {
  notificationType?: string;
  subtype?: string;
  data?: {
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
};

type TransactionInfo = {
  originalTransactionId?: string;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let originalTransactionId: string | undefined;
  let notificationType: string | undefined;

  try {
    const body = await req.json() as { signedPayload?: string };
    if (!body.signedPayload) {
      return new Response("OK", { status: 200 });
    }

    const payload = decodeSignedPayload<NotificationPayload>(body.signedPayload);
    notificationType = payload.notificationType;

    if (payload.data?.signedTransactionInfo) {
      const info = decodeSignedPayload<TransactionInfo>(
        payload.data.signedTransactionInfo,
      );
      originalTransactionId = info.originalTransactionId;
    }
  } catch (err) {
    console.error("Unreadable notification:", err);
    // Malformed, and retrying will not help.
    return new Response("OK", { status: 200 });
  }

  if (notificationType === "TEST") {
    console.log("App Store test notification received");
    return new Response("OK", { status: 200 });
  }

  if (!originalTransactionId) {
    console.log(`Nothing to act on for notification type ${notificationType}`);
    return new Response("OK", { status: 200 });
  }

  try {
    const userId = await findAccountForSubscription(
      admin,
      "app_store",
      originalTransactionId,
    );

    if (!userId) {
      // Bought before the link table existed. Nothing to update until that
      // person next opens the Pro screen, which records the link.
      console.warn("No account on file for this App Store subscription");
      return new Response("OK", { status: 200 });
    }

    // Apple is the authority, not the message we just received.
    const subscription = await getSubscription(originalTransactionId);

    if (subscription.active && subscription.expiresAt) {
      await grantPremium(admin, userId, {
        until: subscription.expiresAt,
        source: "app_store",
        productId: subscription.productId,
      });
      await rememberSubscription(admin, {
        userId,
        source: "app_store",
        storeSubscriptionId: originalTransactionId,
        productId: subscription.productId,
        expiresAt: subscription.expiresAt,
      });
      console.log(
        `Pro for ${userId} now runs to ${subscription.expiresAt.toISOString()}`,
      );
    } else {
      await revokePremium(admin, userId, "app_store");
      console.log(`Pro ended for ${userId}`);
    }

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("Could not process the notification:", err);
    // A non-2xx makes Apple deliver it again later, which is what we want when
    // Apple or the database was briefly unreachable.
    return new Response("Retry", { status: 500 });
  }
});
