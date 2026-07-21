// Stripe tells us when a website subscription is paid, renewed or cancelled.
//
// Two things were wrong here before, and both are fixed below:
//
//   1. Every payment recorded exactly one month of Pro, whatever was bought.
//      A yearly plan would lose eleven months. The real end of the paid period
//      now comes from the subscription itself.
//   2. The buyer was matched to an account by the email typed on Stripe's own
//      page, which the buyer can change. Paying with a different address than
//      the CryptKeep account meant the money arrived and Pro never did. The
//      account id now travels with the checkout, and email is only a fallback.

import "@supabase/functions-js/edge-runtime.d.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";
import { adminClient, grantPremium, revokePremium } from "../_shared/premium.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const admin = adminClient();

/// The end of the period the customer has actually paid for. Asking the
/// subscription is the only answer that is right for both monthly and yearly.
async function paidUntil(subscriptionId: string): Promise<Date> {
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  return new Date(subscription.current_period_end * 1000);
}

function subscriptionIdOf(
  value: string | { id: string } | null | undefined,
): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

/// Finds the CryptKeep account behind a payment.
///
/// The id is carried through checkout as client_reference_id, set by the app in
/// lib/screens/vault/premium_screen.dart. Returns null when there is no id to
/// go on, and the caller falls back to matching on email.
async function resolveUserId(
  accountId: string | null | undefined,
): Promise<string | null> {
  if (!accountId) return null;
  const { data } = await admin.auth.admin.getUserById(accountId);
  if (data?.user) return data.user.id;
  console.warn(`Account id ${accountId} from Stripe matched no account`);
  return null;
}

/// The pre-existing email path, kept for checkouts that carry no account id.
async function grantByEmail(email: string, until: Date): Promise<void> {
  const { error } = await admin.rpc("set_premium_by_email", {
    user_email: email,
    until_date: until.toISOString(),
  });
  if (error) throw new Error(`set_premium_by_email failed: ${error.message}`);
  console.log(`Recorded Pro for ${email} until ${until.toISOString()} (by email)`);
}

async function record(
  accountId: string | null | undefined,
  email: string | null | undefined,
  subscriptionId: string | null,
): Promise<void> {
  if (!subscriptionId) {
    console.log("Payment carried no subscription, nothing to record");
    return;
  }

  const until = await paidUntil(subscriptionId);
  const userId = await resolveUserId(accountId);

  if (userId) {
    await grantPremium(admin, userId, {
      until,
      source: "stripe",
      productId: subscriptionId,
    });
    console.log(`Recorded Pro for ${userId} until ${until.toISOString()}`);
    return;
  }

  if (email) {
    await grantByEmail(email, until);
    return;
  }

  console.error("Could not tell which account this payment belongs to");
}

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  if (!signature) return new Response("Missing signature", { status: 400 });

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
  } catch (err) {
    console.error("Webhook signature verification failed:", err);
    return new Response("Invalid signature", { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        await record(
          session.client_reference_id,
          session.customer_details?.email,
          subscriptionIdOf(session.subscription),
        );
        break;
      }

      // Every renewal lands here, which is what keeps Pro from lapsing while
      // the customer is still being charged.
      case "invoice.paid": {
        const invoice = event.data.object as Stripe.Invoice;
        await record(
          invoice.metadata?.supabase_user_id,
          invoice.customer_email,
          subscriptionIdOf(invoice.subscription),
        );
        break;
      }

      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription;
        const customer = await stripe.customers.retrieve(
          subscription.customer as string,
        ) as Stripe.Customer;

        const userId = await resolveUserId(
          subscription.metadata?.supabase_user_id,
        );

        if (userId) {
          await revokePremium(admin, userId, "stripe");
          console.log(`Ended Pro for ${userId}`);
        } else if (customer.email) {
          await grantByEmail(customer.email, new Date());
          console.log(`Ended Pro for ${customer.email} (by email)`);
        }
        break;
      }
    }
  } catch (err) {
    console.error("Error processing webhook:", err);
    // A non-2xx makes Stripe retry, which is what we want for a transient
    // failure. Without it a dropped renewal would silently expire someone.
    return new Response("Webhook handler failed", { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
