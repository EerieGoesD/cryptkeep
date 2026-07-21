// The link between a store's subscription and a CryptKeep account.
//
// Record it when someone buys. Look it up when the store later tells us the
// subscription renewed or ended, because all the store sends is its own id.

import { type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type PremiumSource } from "./premium.ts";

const TABLE = "store_subscriptions";

/// Called at purchase time. Safe to call again on every verification: the same
/// subscription updates its row rather than adding another.
export async function rememberSubscription(
  admin: SupabaseClient,
  options: {
    userId: string;
    source: PremiumSource;
    storeSubscriptionId: string;
    productId?: string | null;
    expiresAt?: Date | null;
  },
): Promise<void> {
  const { error } = await admin
    .from(TABLE)
    .upsert(
      {
        user_id: options.userId,
        source: options.source,
        store_subscription_id: options.storeSubscriptionId,
        product_id: options.productId ?? null,
        expires_at: options.expiresAt?.toISOString() ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "source,store_subscription_id" },
    );

  if (error) {
    // Not fatal for the purchase itself - the buyer has already been granted
    // Pro. It does mean renewals will not be picked up, so it is worth shouting
    // about in the logs.
    console.error(`Could not record the subscription link: ${error.message}`);
  }
}

/// Called when a store sends us a renewal or cancellation. Returns null if we
/// have never seen this subscription, which is normal for purchases made before
/// this table existed.
export async function findAccountForSubscription(
  admin: SupabaseClient,
  source: PremiumSource,
  storeSubscriptionId: string,
): Promise<string | null> {
  const { data, error } = await admin
    .from(TABLE)
    .select("user_id")
    .eq("source", source)
    .eq("store_subscription_id", storeSubscriptionId)
    .maybeSingle();

  if (error) {
    throw new Error(`Could not look up the subscription: ${error.message}`);
  }
  return data?.user_id ?? null;
}
