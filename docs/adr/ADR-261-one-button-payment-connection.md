# ADR-261: Connecting the business's payment account with one button
Date: 2026-10-29
Status: Accepted

## Context
The approved online-payments mockup (option B) has one button, «Σύνδεση με
Viva ή Stripe»: the owner goes to the provider's page, signs in or opens a
merchant account, and comes back connected, without copying API keys.
ADR-246 only took pasted keys. Card data and the business's secrets must
still never pass through Palee, and the money must still go straight to the
business's own account.

## Decision
1. **Port `Payments.Ports.Connect`** (`available?/1`, `authorize_url/2`,
   `complete/2`, `disconnect/2`), adapters by provider in
   `config :palee, :payment_connect`. Palee registers once with the
   provider as a platform; its credentials per environment come from the
   environment (`STRIPE_CONNECT_CLIENT_ID_TEST|LIVE`,
   `STRIPE_PLATFORM_SECRET_KEY_TEST|LIVE`). Without them the button is not
   offered (`connect_providers` in the account answer) and pasted keys
   under «Προχωρημένα» remain the way in.
2. **Stripe**: Connect OAuth for Standard accounts (`connect.stripe.com/
   oauth/authorize`, scope `read_write`, then `/oauth/token`). Palee keeps
   only `connected_account` (`acct_…`) and calls Stripe with its platform
   key and the `Stripe-Account` header; the token's `livemode` must match
   the chosen environment. Stripe recommends hosted onboarding for new
   platforms, but OAuth is the only flow that connects a business's
   *existing* Stripe account, which is what gyms already have.
3. **State and callback.** `POST /admin/payments/connect` answers the
   provider URL with a `state` signed by Palee (business, person, provider,
   environment; 30 minutes). `GET /api/payments/connect/callback` needs no
   session: it verifies the state, checks that the person still holds
   `manage_billing` in that business, finishes the connection, checks it
   with a harmless call, and redirects to
   `/admin/settings?tab=payments&connect=ok|<code>`.
4. **Disconnect** (`DELETE /admin/payments/account`): the account becomes
   `disabled` (saved cards are not charged) and Palee's access at the
   provider is removed. Reconnecting the same account brings the saved
   cards back.
5. **Viva**: the same port through Viva's ISV programme (create connected
   account, onboarding link). Built once Palee is accepted as a Viva ISV
   partner and the ISV API reference can be checked; until then Viva uses
   pasted keys.

## Consequences
- Webhooks of connected Stripe accounts go to one platform endpoint;
  until that endpoint is set up, payments of connected accounts settle
  through the return page and polling (every 3 minutes), which ADR-246
  already relies on when a webhook is lost.
- Operations: the product owner registers Palee as a Stripe Connect
  platform (dashboard › Connect › OAuth, redirect URI
  `https://<host>/api/payments/connect/callback`) and applies to Viva's ISV
  programme; the secrets go to the gitops secret.
