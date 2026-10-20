# ADR-156: Member referrals («Φέρε φίλο»)
Date: 2026-10-20
Status: Accepted

## Context
Plan §5a board 11 (P2-M8, mockup 34) gives every member a way to bring friends:
a personal link and QR under «Εγώ › Φέρε φίλο» and «Box › Συνδρομή», invites to
upcoming events, and a view of how each friend is doing and what the member
earns. The plan sketched this as ADR-146. Finance already had
`referral_programs`, `referral_events` and `referral_rewards`, but only staff
could record a referral by hand, a box could run several programmes at once, and
nothing moved a referral on its own. Trials (ADR-144) and events (ADR-153) now
give the funnel its steps.

## Decision
1. **A Referrals context owns invites.** `referral_codes` holds one personal
   code per member per box: eight Crockford base32 characters, unique across
   Milos, revocable («Νέος σύνδεσμος»). `referral_attributions` holds one row per
   friend per box: who invited them, the channel (link · qr · event · guest_pass
   · staff), the programme at the time, the window, the funnel stamps
   (`event_at`, `trial_at`, `joined_at`, `paid_at`) and the outcome (open ·
   qualified · capped · expired · void). The rules are pure
   (`Referrals.Domain.Code`, `Referrals.Domain.Attribution`), and storage goes
   through the `ReferralStore` port and its Ecto adapter.
2. **Finance stays the money side and doesn't know about invites.** When an
   invite reaches the programme's step, Referrals opens the Finance
   `referral_event` (`Finance.open_attributed_referral`), and staff approve it as
   before. Rewards follow the programme the invite was made under, even after
   that programme is retired. A credit reward is applied when it is approved,
   provided the member has a Finance record. Otherwise it stays approved, and
   «Δόθηκε» applies it later. A discount reward (a percentage), once given,
   comes off the member's next renewal invoice: the reward keeps
   `renewal_invoice_id`, so it is used once, and voiding that invoice frees it
   for the next renewal (board 11 Q6 extra).
3. **Programmes carry their own rules.** Each programme defines:
   - the friend's gift (none · free_days · credit · custom);
   - when an invite counts (`trial` or `paid`, default paid);
   - the window (7 to 365 days, default 30) and an optional yearly cap per
     member;
   - manual or automatic approval.

   One programme is active per box, enforced by a partial unique index.
   Activating a programme retires the previous one.
4. **First invite wins (board 11 Q4).** The first member whose link a friend
   uses to sign up or open the box's page owns the invite for the window
   (30 days by default, ANR's note), after which another link can take it. An expired or void invite leaves room
   for a new one. Members and former members of the box are never counted, and
   nobody can invite themselves. Staff can give an invite to another member
   before it counts, with a note, and the previous inviter is kept. Claims for
   the same friend and box are serialised with an advisory transaction lock.
5. **Stages come from domain events.** `ReferralReactions` listens to:
   - `event_attendance_recorded` (new, published by event check-in) for the
     event step;
   - `attendance_recorded` with status attended for the trial step;
   - `membership_activated` for the joined step;
   - `membership_payment_recorded` (new, published for package payments and
     receipts with an amount) for the paid step.

   A step after the window expires the invite.
6. **Who earns.** Members and athletes earn. Staff and coaches share the same
   link without a reward, and their invites are void with
   `referrer_not_eligible`. At the cap an invite is `capped`.
7. **Public invite page.** `GET /api/public/referrals/:code` (rate limited)
   resolves a code through the SECURITY DEFINER function `milos_referral_invite`.
   It returns only the box (when active) and whether the inviter is an active
   member. A revoked code, a former member or a closed box find nothing.
   `POST /api/referrals/claim` records the invite after sign-up or sign-in. The
   web app keeps the code for the window and claims it then.
8. **Notifications.** The member gets `referral_progress` at each step (deduped
   per stage) and `referral_reward` at each reward status. Owners and admins get
   `referral_review` when an invite waits for approval. The messages are
   translated into every locale.
9. **Staff queue.** «Οικονομικά › Συστάσεις» (`/api/org/:slug/admin/referrals`)
   lists invites and 90-day stats and offers approve, reject, given, reassign
   and «Δώρο φίλου». The friend's gift is applied once: free days extend the
   current dated package, and a credit lands in the friend's credit ledger. The
   list needs `view_promotions` and the actions need `manage_promotions`.
10. **Events for friends (board 11 Q3).** «Φέρε φίλο» lists the open events
    and the guest-pass events the member is going to. Staff can tag an event
    «Καλό για φίλους» (`community_events.good_for_friends`, only on events
    friends can come to), and tagged events come first.
11. **Tenancy.** Both tables have tenant RLS policies (FORCE). Inviters and
    friends read their own rows from their personal scope. The tenant data
    policy purges them at order 89, before Finance.

## Consequences
- The flow from link to reward runs without staff, and staff keep the final say
  through approval. Boxes can switch to automatic approval.
- Finance learns nothing about invites. A new reward or gift type changes the
  programme and Referrals, not the rest of Finance.
- Two new domain events (`event_attendance_recorded`,
  `membership_payment_recorded`) are available to other contexts.
- The free-days gift needs a package with an end date. Open-ended packages get
  a credit or a custom gift instead (`no_active_subscription`).
