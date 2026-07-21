# Billing, and how Pro is kept in one place

Money is taken in four different tills, because each store insists on its own:

| Where they buy | Who takes the money |
| --- | --- |
| Android | Google Play |
| iPhone, iPad, Mac | Apple |
| Windows | Microsoft Store |
| Website | Stripe |

All four write the same thing to the same place: a Pro expiry date on the
person's CryptKeep account. Every app and the browser extension reads only that.
That is what stops someone paying a second time on a second device.

**Everything that grants Pro must go through `grantPremium` in
[`_shared/premium.ts`](_shared/premium.ts).** Do not write `app_metadata`
by hand. Two places writing Pro in two different shapes is exactly how the
Microsoft gap happened.

## What each function does

| Function | Runs when |
| --- | --- |
| `verify-app-store-purchase` | Someone buys or restores on Apple |
| `verify-google-play-purchase` | Someone buys or restores on Android |
| `app-store-notifications` | Apple reports a renewal, lapse or refund |
| `google-play-notifications` | Google reports a renewal, lapse or refund |
| `stripe-webhook` | Stripe reports a payment, renewal or cancellation |
| `manage-subscription` | Someone opens the Stripe billing portal |
| `breach-check` | Pro feature, checks passwords against breaches |

The two notification functions are new. Without them, Pro was recorded once at
purchase and never updated, so it expired while the store kept charging.

### How the notification functions are kept safe

Neither one believes what it is told. The message says *which* subscription
changed; it does not get to say *what* changed. The function then asks Apple or
Google directly, authenticated with our own credentials, and acts on that
answer. Which account it belongs to comes from our own `store_subscriptions`
table, never from the message.

So a forged notification achieves nothing. The worst it can do is make us ask
Apple a question we already know the answer to.

## Before any of this works: run the migration

[`migrations/20260721000000_store_subscriptions.sql`](../migrations/20260721000000_store_subscriptions.sql)
creates the table that remembers which account a store subscription belongs to.
Without it the notification functions have nothing to look up.

```
supabase db push
```

Or paste the file into the SQL editor in the Supabase dashboard.

## Deploying

The three webhook functions are called by Apple, Google and Stripe, none of whom
are signed-in users, so they must be deployed with JWT verification off:

```
supabase functions deploy app-store-notifications --no-verify-jwt
supabase functions deploy google-play-notifications --no-verify-jwt
supabase functions deploy stripe-webhook --no-verify-jwt

supabase functions deploy verify-app-store-purchase
supabase functions deploy verify-google-play-purchase
```

## Secrets to set

Already in place:

```
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
APP_STORE_SHARED_SECRET
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON   (or the _B64 / EMAIL + PRIVATE_KEY variants)
```

New, needed for Apple renewals. All four come from App Store Connect, under
Users and Access, then Integrations, then In-App Purchase keys:

```
APP_STORE_KEY_ID        the key's id
APP_STORE_ISSUER_ID     the issuer id shown on that same page
APP_STORE_PRIVATE_KEY   the whole contents of the .p8 file that key downloads
APP_STORE_BUNDLE_ID     the app's bundle id
```

The `.p8` file downloads exactly once and can never be downloaded again. Keep a
copy somewhere safe before you close the page.

Optional, for Google renewals:

```
GOOGLE_PLAY_NOTIFICATIONS_TOKEN
```

If you set it, add `?token=<the same value>` to the address you give Google.
It stops strangers hammering the endpoint. It is not what makes the function
safe - asking Google directly is.

## Then, in each portal

**App Store Connect.** Open the app, then General Information. Set the App Store
Server Notifications URL (version 2) to the `app-store-notifications` function
address. There are separate boxes for production and sandbox; the same address
works for both. There is a Send Test Notification button - use it, then check
the function logs for "App Store test notification received".

**Google Play Console.** Monetisation setup, then Real-time developer
notifications. You need a Google Cloud Pub/Sub topic, and a push subscription on
that topic pointing at the `google-play-notifications` function address. There
is a Send Test Notification button - use it, then check the logs for
"Google Play test notification received".

**Stripe.** Already configured. Confirm the webhook is subscribed to
`checkout.session.completed`, `invoice.paid` and `customer.subscription.deleted`.

## Worth knowing

**Existing subscribers are not linked yet.** The `store_subscriptions` table
starts empty, so renewals for people who bought before today will be ignored
with "No account on file" in the logs. They get linked automatically the next
time that person opens the Pro screen, which re-verifies and records the link.
Nobody loses anything in the meantime, because their existing expiry date is
untouched.

**Stripe's period end.** `stripe-webhook` reads `current_period_end` off the
subscription, which is correct for the pinned API version `2024-04-10`. If you
ever raise that version, check that field still lives there.

**verify-app-store-purchase still uses `verifyReceipt`,** which Apple has
deprecated. It works, and it is left alone deliberately to keep this change
small. [`_shared/app_store.ts`](_shared/app_store.ts) is the modern
replacement and already does everything needed to move it over when you want to.

**Microsoft is not done yet.** Windows subscriptions still only exist on the PC
they were bought on and are not written to the account, so a Windows subscriber
gets no Pro in the browser extension or on any other device. That is the next
piece of work.
