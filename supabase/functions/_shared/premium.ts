// The one place Pro is written down.
//
// Money is taken in four different tills - the App Store, Google Play, the
// Microsoft Store and Stripe - but all four record the result here, on the
// user's account, in the same shape. Every app and the browser extension then
// reads only that, which is what stops someone paying twice on a second
// device.
//
// If you are adding a fifth till, call grantPremium from it. Do not write
// app_metadata by hand.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type PremiumSource =
  | "app_store"
  | "google_play"
  | "stripe"
  | "microsoft_store";

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

/// Records Pro as running until [until].
///
/// [until] is the real end of the paid period as the store reports it, not a
/// guess. A yearly plan must record a year, or the person loses access eleven
/// months early.
export async function grantPremium(
  admin: SupabaseClient,
  userId: string,
  options: {
    until: Date;
    source: PremiumSource;
    productId?: string | null;
    extra?: Record<string, unknown>;
  },
): Promise<void> {
  const { data, error: readError } = await admin.auth.admin.getUserById(userId);
  if (readError || !data.user) {
    throw new Error(`No such user: ${readError?.message ?? userId}`);
  }

  const current = data.user.app_metadata ?? {};

  // A person can hold subscriptions in two stores at once - they moved from
  // Android to iPhone and forgot to cancel, say. Whichever runs longest is the
  // one that decides when Pro ends, so a shorter one arriving later cannot cut
  // them off early.
  const existingEnd = Date.parse(String(current.premium_until ?? ""));
  const newEnd = options.until.getTime();
  const existingWins = Number.isFinite(existingEnd) &&
    existingEnd > newEnd &&
    existingEnd > Date.now();

  const { error } = await admin.auth.admin.updateUserById(userId, {
    app_metadata: {
      ...current,
      premium_until: existingWins
        ? current.premium_until
        : options.until.toISOString(),
      premium_source: existingWins ? current.premium_source : options.source,
      premium_product_id: existingWins
        ? current.premium_product_id
        : (options.productId ?? null),
      premium_updated_at: new Date().toISOString(),
      ...(options.extra ?? {}),
    },
  });

  if (error) {
    throw new Error(`Could not record Pro: ${error.message}`);
  }
}

/// Ends Pro now. Used when a store tells us a subscription was cancelled,
/// refunded or has lapsed.
///
/// Only the till that granted it may revoke it, otherwise a cancelled Android
/// subscription would switch off Pro for someone who has since resubscribed on
/// iPhone.
export async function revokePremium(
  admin: SupabaseClient,
  userId: string,
  source: PremiumSource,
): Promise<void> {
  const { data, error: readError } = await admin.auth.admin.getUserById(userId);
  if (readError || !data.user) {
    throw new Error(`No such user: ${readError?.message ?? userId}`);
  }

  const current = data.user.app_metadata ?? {};
  if (current.premium_source && current.premium_source !== source) {
    console.log(
      `Ignoring ${source} cancellation for ${userId}: Pro currently comes from ${current.premium_source}`,
    );
    return;
  }

  const { error } = await admin.auth.admin.updateUserById(userId, {
    app_metadata: {
      ...current,
      premium_until: new Date().toISOString(),
      premium_updated_at: new Date().toISOString(),
    },
  });

  if (error) {
    throw new Error(`Could not end Pro: ${error.message}`);
  }
}
