import "@supabase/functions-js/edge-runtime.d.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return new Response("Missing signature", { status: 400 });
  }

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      webhookSecret
    );
  } catch (err) {
    console.error("Webhook signature verification failed:", err);
    return new Response("Invalid signature", { status: 400 });
  }

  try {
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const email = session.customer_details?.email;

      if (email) {
        const premiumUntil = new Date();
        premiumUntil.setMonth(premiumUntil.getMonth() + 1);

        await supabase.rpc("set_premium_by_email", {
          user_email: email,
          until_date: premiumUntil.toISOString(),
        });
        console.log(`Activated premium for ${email} until ${premiumUntil.toISOString()}`);
      }
    }

    if (event.type === "invoice.paid") {
      const invoice = event.data.object as Stripe.Invoice;
      const email = invoice.customer_email;

      if (email) {
        const premiumUntil = new Date();
        premiumUntil.setMonth(premiumUntil.getMonth() + 1);

        await supabase.rpc("set_premium_by_email", {
          user_email: email,
          until_date: premiumUntil.toISOString(),
        });
        console.log(`Renewed premium for ${email} until ${premiumUntil.toISOString()}`);
      }
    }

    if (event.type === "customer.subscription.deleted") {
      const subscription = event.data.object as Stripe.Subscription;
      const customer = (await stripe.customers.retrieve(
        subscription.customer as string
      )) as Stripe.Customer;

      if (customer.email) {
        await supabase.rpc("set_premium_by_email", {
          user_email: customer.email,
          until_date: new Date().toISOString(),
        });
        console.log(`Expired premium for ${customer.email}`);
      }
    }
  } catch (err) {
    console.error("Error processing webhook:", err);
    return new Response("Webhook handler failed", { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
