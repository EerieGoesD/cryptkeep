-- Remembers which CryptKeep account a store subscription belongs to.
--
-- When Apple or Google tells us "this subscription just renewed", all they send
-- is their own id for it. Without this table there is no way to know whose
-- account that is, which is why renewals were never being recorded and people
-- were quietly losing Pro while still being charged.
--
-- Written only by the server. Row level security is on and there are
-- deliberately no policies, so nothing but the service role can see or change
-- it. Nobody's payment history is exposed to the app.

create table if not exists public.store_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- Which till took the money.
  source text not null check (
    source in ('app_store', 'google_play', 'microsoft_store', 'stripe')
  ),

  -- The store's own lasting id for the subscription. For Apple this is the
  -- original transaction id, for Google the purchase token, for Stripe the
  -- subscription id. It survives renewals, which is the whole point.
  store_subscription_id text not null,

  product_id text,
  expires_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One subscription belongs to one account. Re-recording it updates the row
  -- rather than creating a second one.
  unique (source, store_subscription_id)
);

create index if not exists store_subscriptions_user_id_idx
  on public.store_subscriptions (user_id);

alter table public.store_subscriptions enable row level security;
