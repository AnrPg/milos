# ADR-103: Subscription Expiry Reminders and Grace Slack
Date: 2026-10-12
Status: Accepted

## Context
Clients were not told that their subscription was about to end. Access
stopped the moment a membership expired or an invoice fell overdue. Gyms want
two things:
- warn clients some days ahead;
- leave a few days of slack to pay or renew, after which entitlements (e.g.
  booking classes) are withdrawn.

## Decision
- **Settings.** Two finance settings per organization, editable in Admin
  settings → Finance:
  - `subscription_expiry_reminder_days` (default 5; 0 = off);
  - `subscription_grace_days` (default 3; 0 = cut off immediately).
- **Access rule.** `InvoiceLifecycle.entitlement/1` (pure) derives access from
  the date:
  - **Subscription ended:** for `grace_days` after the subscription ends, the
    member is in `grace` (`subscription_grace`, with `grace_until`).
    Afterwards they are `inactive`.
  - **Membership expired:** within the slack it is `grace`
    (`membership_expiry_grace`); afterwards `inactive`.
  - **Overdue invoice:** within the slack it is `grace` (`overdue_grace`).
    Only after the slack does it become `blocked`.
  - `EntitlementPolicy` already refuses `inactive` and `blocked`, so booking
    and execution are denied after the slack.
- **Allowances during the slack.** The lapsed subscription keeps governing
  allowances (`effective_subscription/2` falls back to it), so the client's
  usual package keeps applying until the slack is over.
- **Daily job.** `SubscriptionExpiryJob` runs at 08:30 UTC for every active
  organization. It notifies **the client** in-app and by push, in their
  language, with each notice sent once per subscription (dedupe key plus
  `*_sent_at` columns):
  - `subscription_expiring`, sent `subscription_expiry_reminder_days` before
    the end of a subscription that was not renewed;
  - `subscription_grace`, sent once it has ended, with the last day of
    access.

  It also refreshes the stored entitlement snapshots, so admin lists follow
  the calendar.
- **All entitlements end with the slack.** Every entitlement check
  (`EntitlementPolicy` through `AuthorizeFinanceEntitlement` and
  `reserve_entitlement`) refuses `inactive` and `blocked` in every enforcement
  mode. That covers:
  - booking classes;
  - starting class, library or assigned workouts, and loading their timers;
  - receiving assigned workouts;
  - coaching messages (touchpoints).
- **What the job revokes.** When a refresh moves a client from active/grace to
  inactive/blocked, the job also:
  - cancels their upcoming class bookings, freeing the places and releasing
    the class-visit allowances;
  - notifies them (`access_ended`, with the reason and the number of cancelled
    bookings).
- **Admin overrides.** Admins acting themselves are not subject to client
  entitlements, so they can still book a client in on purpose.
- **Billing page.** The client's billing page explains the state plainly:
  - access until a date during the slack;
  - paused after the slack because of an overdue payment;
  - ended.

## Consequences
- Existing organizations get the default 3 days of slack. An invoice 1–3 days
  overdue no longer blocks immediately. Admins can set 0 to keep the old
  behaviour.
- Renewal is detected as a later active subscription for the same membership.
  Subscriptions renewed through other means will still get the reminder.
