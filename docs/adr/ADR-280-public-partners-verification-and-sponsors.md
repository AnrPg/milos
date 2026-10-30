# ADR-280: Public Partners (Συναθλητές) with account verification, sponsors and a Palee review
Date: 2026-10-30
Status: Accepted
Supersedes: the club scope of ADR-169 (and ADR-197's partner distance in open clubs)

## Context
ADR-169 kept Partners inside one club: per-club decks in Club › Μέλη, rows
owned by the club's gym, staff moderating reports. The owner (ANR,
2026-10-30, thread "Open buddy swiping beyond one club") does not want two
places for one feature and wants it open: one public deck for all of Palee.
Mockups and every answer: https://claude.ai/artifact/LGQD2C2Z4BZjU3WcuCRCbh
(file `/mnt/project-files/milos/partners-public/`).

Decisions taken there:
- **Where:** one deck that lives in Feed › Γύρω μου (a «Συναθλητές κοντά σου»
  card opens it). Conversations stay in Μηνύματα › Partners. The per-club
  card in Club › Μέλη goes away, and so does the box's Partners switch.
- **Who may take part (verification, once per account, permanent):**
  1. an active subscribed member of a box (`provider_kind = gym`) or an
     active client (package or subscription) of an independent coach
     (`provider_kind = coach`), in an organization that is live (not demo); or
  2. two sponsors **and** a check by the Palee team.
  Verification is recorded once and never lapses when a subscription ends.
  It is lost only when the Palee team suspends the account after reports.
- **Sponsors:** only people verified through a membership (path 1) may vouch.
  At most 5 vouches per sponsor in any 30 days. When someone a sponsor vouched
  for is suspended, the sponsor is told and cannot vouch for 60 days (their
  own access stays). The main way to ask is a list of one's verified Buddies
  (ADR-193 mutual follows); a collapsed «Αυτός που σε ξέρει δεν είναι εδώ;»
  section opens a QR/link (single use, 10 minutes).
- **Palee check (path 2 only), option A:** SMS code to a mobile number (one
  number per account), then a selfie holding a 4-digit code on paper, which a
  person of the Palee team compares with the avatar. No face recognition, no
  automatic decision. The photo is deleted as soon as the decision is taken,
  at the latest 7 days after upload. Only the outcome is kept.
- **Age:** 18+ only, a required «Είμαι 18 ετών ή μεγαλύτερος/η» checkbox on
  entering (as the 16+ checkbox of ADR-267), and «Ανήλικος» as a report reason.
- **Card:** full screen (Tinder-like), drag to swipe, floating ✕/✓. Avatar,
  nickname, «✓ Μέλος <box>» while a membership is active and the person left
  «Δείξε το box μου» on (default on); «✓ Μέλος box» when off; «✓ Επαληθευμένος»
  for an ex-member; «✓ Με εγγυητές» for path 2. Level, times, goals,
  disciplines, the person's own line (`about`), «Κοινά: …» and distance step.
- **Distance:** from neighbourhood centroids only (never live location), steps
  2/5/10/25 km.
- **Reports:** a Palee-level queue in the platform console; box staff no
  longer moderate Partners. Reporting also blocks (ADR-169 §5 kept).
- **«Κλείστε μαζί» → suggestions (option A):** classes of a box both share;
  otherwise events and trial classes near both, from what Γύρω μου shows;
  plus «Πάμε μαζί;». A deterministic rule engine (below).
- **Old data:** dropped. Production holds no real Partners data.

## Decision

### 1. Bounded context `Palee.Partners`, account-level (personal) data
All rows are personal, not tenant: no `organization_id` tenant policy. Row
security uses `app.user_id` (the acting person) and
`palee_acting_user_is_vendor()` for the Palee team, as `business_requests`
(ADR-184) does. Rows of a person go when the account is deleted
(`on_delete: :delete_all`) and appear in «Κατέβασε τα δεδομένα μου» (ADR-267).

Migration `20270325000000_public_partners.exs` drops `partner_messages`,
`partner_matches`, `partner_swipes`, `partner_profiles`, the
`community_settings.partners_enabled` column and the `partner` target type of
`community_reports` (deleting such reports), then creates:

| table | purpose / key columns |
|---|---|
| `partner_verifications` | one per user (`user_id` unique). `method membership\|sponsors`, `status verified\|suspended`, `verified_at`, `source_organization_id` (nullable, the membership that verified, informational), `suspended_at`, `suspended_by_id`. Insert only through the definer functions below or by vendors. |
| `partner_verification_requests` | path 2, one open per user. `status collecting\|in_review\|approved\|rejected\|expired\|withdrawn`, `consent_at`, `phone_ciphertext` (EncryptedBinary), `phone_hash` (HMAC, unique among non-withdrawn rows of other users), `phone_verified_at`, `selfie_code` (4 digits), `selfie_key` (object key or null once deleted), `selfie_uploaded_at`, `submitted_at`, `decided_at`, `decided_by_id`, `decision_reason`. |
| `partner_phone_codes` | `request_id`, `code_hash`, `expires_at` (10 min), `attempts` (max 5), `sent_at`. At most 3 sends per hour per user, 10 per day. |
| `partner_sponsorships` | `candidate_id`, `sponsor_id`, `channel buddy\|link`, `status requested\|vouched\|declined\|cancelled`, `requested_at`, `decided_at`. Unique `(candidate_id, sponsor_id)`. |
| `partner_sponsor_links` | `candidate_id`, `token_hash`, `expires_at` (10 min), `used_by_id`, `used_at`. |
| `partner_profiles` | one per user. `active`, `adult_confirmed_at` (required), `show_box` (default true), `level`, `times[]`, `goals[]` (≤3), `disciplines[]`, `about` (≤140), `gender`, `gender_preference`, `paused_at`. Same vocabularies as ADR-169/197. |
| `partner_swipes` | `swiper_id`, `target_id`, `direction like\|pass`, unique pair. Pass cooldown 30 days, 200 swipes a day. |
| `partner_matches` | pair `user_a_id < user_b_id`, `status active\|ended`, `ended_by_id`, `end_reason unmatched\|blocked\|reported\|suspended`, read marks. Unique active match per pair (one table now, no per-gym duplicates). |
| `partner_messages` | `match_id`, `author_id`, `kind text\|plan`, `body ≤2000`, `plan` jsonb snapshot (`kind class\|event\|trial`, id, title, starts_at, place). |
| `partner_reports` | `reporter_id`, `target_id`, `reason unsafe\|fake\|minor\|harassment\|other`, `note ≤500`, `status open\|actioned\|dismissed`, `decided_by_id`, `decided_at`, `decision_note`. Reporter reads own; vendors read and decide. |
| `partner_suggestion_feedback` | `match_id`, `user_id`, `suggestion_key`, `reason not_near\|bad_time\|wrong_level\|other`, anonymous counters only are reported. |
| `partner_suggestion_events` | aggregate counters only (`day`, `event shown\|proposed\|booked_together\|feedback`, `count`), no person ids. |

Definer functions (each pins only `search_path`, never an extension GUC):
- `palee_partner_membership_source(person uuid) → uuid`: the first live
  organization (`status = active`, `activation = active`, `provider_kind in
  (gym, coach)`) where the person holds an active membership or package
  (finance memberships). Null if none.
- `palee_partner_verify_by_membership() → partner_verifications`: for the
  session user only; inserts the `membership` verification when the source
  function returns an organization, else returns null. Idempotent.
- `palee_partner_people_within(ids uuid[], meters int) → setof uuid`: ids whose
  main neighbourhood centroid is within `meters` of the session user's.
- `palee_partner_box_badges(ids uuid[]) → (user_id, organization_name)`: the
  active membership's box name for people with `show_box`.
- `palee_partner_shared_organizations(a uuid, b uuid) → setof uuid` for
  suggestions, only callable for a pair with an active match that includes the
  session user.

Notification types added: `partner_vouch_request`, `partner_vouched`,
`partner_verification_decided`, `partner_sponsor_penalty`. Kept:
`partner_match`, `partner_message`.

### 2. Domain (pure, `Palee.Partners.Domain.*`)
- `Eligibility`: `status(verification, request, profile) → :verified |
  :needs_verification | :in_review | :rejected | :suspended` and the next step.
- `SponsorPolicy`: who may vouch (method `membership`, not suspended, not the
  candidate, not blocked either way, quota 5 per rolling 30 days, no penalty
  within 60 days), `required = 2`, link expiry 10 min, single use.
- `PhoneCodePolicy`: E.164 normalisation, 6-digit codes, 10-minute expiry,
  5 attempts, send limits 3/hour and 10/day, masked display.
- `VerificationReviewPolicy`: the request may be submitted when consent,
  2 vouches, phone verified and a selfie are present; decisions approve |
  reject (reason required); expiry 7 days after upload; what is deleted when.
- `ProfilePolicy`, `DeckPolicy`, `MatchPolicy`, `MessagePolicy`: kept from
  ADR-169/197 without the club; `DeckPolicy` adds `within_km` (default 10).
- `BadgePolicy`: which badge a card shows (see Context).
- `SuggestionPolicy` (see §4).
- `ReportPolicy`: reasons, the suspension's effects (profile off, verification
  `suspended`, matches end with `suspended`, every sponsor of that person gets
  a 60-day penalty).

### 3. Ports and adapters
- `Palee.Partners.Ports.PartnerStore` (profiles, swipes, matches, messages,
  reports), `VerificationStore` (verifications, requests, phone codes,
  sponsorships, links), Ecto adapters under
  `Palee.Infrastructure.Partners.*`.
- `Palee.Application.Ports.SmsSender`: `deliver(%{to: e164, body: text,
  tag: String.t()}) :: :ok | {:error, term()}`. Adapters:
  `Palee.Infrastructure.Sms.BrevoSmsSender` (Brevo transactional SMS API
  `POST https://api.brevo.com/v3/transactionalSMS/sms`, `api-key` header from
  `BREVO_API_KEY`, sender `SMS_SENDER` default `Palee`, type
  `transactional`), `Palee.Infrastructure.Sms.LogSmsSender` (dev: logs a
  masked number and the code) and `Palee.TestSupport.MemorySmsSender` (test).
  Config key `:palee, :sms_sender`. A missing key in prod makes the phone step
  answer `sms_unavailable`, never crash.
- Selfies use `TenantObjectStore` bucket `:documents` under
  `users/<user id>/partner-verification/<request id>.<ext>`: presigned PUT
  (jpeg/png/webp/heic, ≤8 MB), probe on submit, a 5-minute presigned GET only
  for vendors, delete on decision, withdrawal, account deletion and by the
  daily job.
- Oban job `Palee.Workers.PartnerVerificationRetention` (daily): requests in
  review with a selfie older than 7 days → delete the object, `expired`,
  notify the person to retake; phone codes older than a day deleted.

### 4. Suggestions engine (`SuggestionPolicy`, deterministic)
Input: both profiles (times, level), both neighbourhood points, the
candidates (shared-box classes in the next 7 days with free places; events
and trial classes from the Γύρω μου sources in the next 7 days with free
places), each person's bookings, now, and the gym time zones.
Hard filters: not full, not cancelled, not started; within each person's
chosen distance (default 10 km) from their own neighbourhood; level fits both;
nobody blocked the organiser. Order: already booked by either → shared time
slots → fairness (smaller maximum of the two distances) → sooner start → id.
At most 3; none means the card is hidden and only «Πάμε μαζί;» stays. Every
suggestion carries its reasons (`both_morning`, `distances [2.1, 3.0]`, …).
It never says who else attends. Tests: unit per rule plus StreamData property
tests for the invariants (never full/past/out of range, stable order,
deterministic). Quality is measured with anonymous daily counters
(`partner_suggestion_events`) and per-suggestion «Δεν ταιριάζει» feedback;
weights live in `SuggestionPolicy.weights/0` so they change in one place.

Implementation notes (suggestions):
- A start falls in one hour slot (`early` <9, `midday` <15, `afternoon` <18,
  `evening`) of the activity's own zone, plus `weekend` on Saturday/Sunday;
  the rank counts slots both chose. A full activity stays only when both are
  already in it. An unknown distance (a box location without a point) passes
  only for a shared box's class. Class levels admit Partners levels:
  `beginner` → beginner/intermediate, `advanced` → intermediate/advanced,
  `all_levels` → any; a person without a level fits any.
- The organiser checked against blocks is a class's coach or a person
  organiser's account (ADR-185); a business has none.
- Migration `20270325200000` adds, besides the two tables and
  `palee_partner_suggestion_count(text)`, the definer reads
  `palee_partner_suggestion_pair(match)` (both people's level, times and main
  neighbourhood centroid) and `palee_partner_suggestion_blocked(match, ids)`,
  and creates `palee_partner_shared_organizations(a, b)` (`CREATE OR
  REPLACE`). All answer only for an active match of the session user.
- Trial classes: the 5 nearest boxes with trials that neither person belongs
  to, classes where `Trials.offer/4` gives both a seat. Events: the 30
  soonest Γύρω μου events within the larger of the two distances.
- `shown` counts a response with at least one suggestion; `booked_together`
  is not written yet (no booking hook ties a booking to a proposed plan).
- `GET /api/platform/partner-suggestion-stats` (vendors): the last 30 days'
  counters and the feedback reasons counted.

### 5. HTTP API (contract-first, `PaleeWeb.Schemas.Partners*`)
Member (`/api/me/partners`, authenticated):
- `GET /` overview: `eligibility {status, method, next_step}`, `profile`,
  `swipes_remaining`, `distance available|needs_area`, `options`.
- `PUT /profile` (requires verified, `adult_confirmed: true` on first save).
- `GET /deck?time&level&goal&discipline&within_km` cards with `badge {kind
  box|member|verified|sponsors, box_name}`.
- `POST /swipes`, `DELETE /swipes/:target_id`.
- `GET /matches`, `DELETE /matches/:id`, `GET|POST /matches/:id/messages`,
  `POST /matches/:id/messages/read`.
- `GET /matches/:id/suggestions`, `POST /matches/:id/plans {kind, id}`,
  `POST /matches/:id/suggestions/feedback {key, reason}`.
- `GET|PUT /settings {visible}`.
- `POST /reports {target_id, reason, note}` (also blocks).
- Verification: `GET /verification`, `POST /verification/consent`,
  `GET /verification/sponsor-candidates`, `POST /verification/sponsors
  {sponsor_id}`, `DELETE /verification/sponsors/:id`, `POST
  /verification/link`, `POST /verification/phone {phone}`, `POST
  /verification/phone/confirm {code}`, `POST /verification/selfie/upload-url`,
  `POST /verification/submit {file_key}`, `DELETE /verification` (withdraw:
  deletes phone, selfie, open sponsorships and links).
- Sponsor side: `GET /vouch-requests`, `POST /vouch-requests/:id {decision
  vouch|decline}`, `POST /vouch-links/inspect {token}`, `POST
  /vouch-links/vouch {token}`, `GET /vouching` (quota left, penalty until).
Platform (`/api/platform`, vendor):
- `GET /partner-verifications?status=in_review`, `GET
  /partner-verifications/:id` (5-minute selfie URL, the code, avatar, sponsors,
  masked phone), `POST /partner-verifications/:id/decision {decision
  approve|reject, reason}`.
- `GET /partner-reports?status=open`, `POST /partner-reports/:id/decision
  {decision suspend|dismiss, note}`.
Error codes (fallback controller): `partner_verification_required`,
`partner_adult_required`, `partner_sponsor_not_eligible`,
`partner_sponsor_quota`, `partner_sponsor_penalty`, `partner_link_expired`,
`partner_phone_invalid`, `partner_phone_taken`, `partner_phone_rate_limited`,
`partner_code_invalid`, `partner_code_expired`, `partner_selfie_missing`,
`partner_verification_incomplete`, `partner_suspended`, `sms_unavailable`,
plus the ADR-169 ones still used.

### 6. Web
- Feed › Γύρω μου: a «Συναθλητές κοντά σου» card (hidden when nothing to show,
  vision §4.2) opening `/partners` (the deck page, full screen, bottom bar
  hidden). `/partners/verify` the verification flow. `/partners/[id]` the
  conversation (kept). Μηνύματα › Partners (kept). Ρυθμίσεις › Κοινοποίηση
  & ορατότητα: the switch and blocked people (kept).
- Platform console: «Επαληθεύσεις Συναθλητών» and «Αναφορές Συναθλητών».
- All copy in the 12 locales, canonical terms («Συναθλητές», «Φιλαράκια»).

## Rationale
- Personal rows match the new scope (the account, not a gym) and the
  permanent, once-per-account verification.
- Membership verification reuses what boxes already check, keeping ADR-169's
  advantage. The sponsor path opens the feature to people without a gym, and
  the human check plus a unique phone number makes fake accounts costly
  without biometric processing (GDPR art. 9 avoided; art. 22 respected).
- An SMS port keeps the provider replaceable; the selfie reuses the private
  documents bucket and the presign/probe pattern of ADR-252.
- Deterministic suggestions can be tested exhaustively and explained to users.

## Alternatives Considered
- Keep per-club decks next to the public one: rejected by the owner.
- Stripe Identity (ID + face match): rejected as excessive (cost, art. 9).
- A 2-minute video call: rejected for team time and delay.
- Expiring verification when a subscription ends: rejected by the owner.

## Consequences
- ADR-169 §2 (club eligibility), the club deck, `partners_enabled`, the
  `partner` community report type and ADR-197's open-club distance are gone.
- New env: `BREVO_API_KEY`, `SMS_SENDER`. Brevo SMS needs prepaid credits.
- The privacy page (ADR-267) and the data export list the new data; a DPIA
  covers matching strangers, approximate location and the selfie check.
- Vision doc §4.7, §7.3 and §8.6 updated.

## Implementation Notes: seams between the parts
- `Palee.Application.PartnerEligibility` (verification side) is what the deck
  side calls: `status(context)`, `require_verified(context)`,
  `verified_user_ids(user_ids)`, `verification_badges(user_ids)` (method and
  the active membership's box name, no `show_box` applied) and
  `suspend(platform_context, user_id, now)` (verification suspended, sponsors
  penalised and notified; returns their ids).
- `Palee.Application.PartnerMatches.own_match(context, match_id)` →
  `{:ok, match, other_user_id} | {:error, :not_found}` and
  `PartnerMatches.post_plan(context, match_id, plan)` (deck side) are what the
  suggestions side calls.
- Migrations: verification `20270325000000`, deck `20270325100000`,
  suggestions `20270325200000`.
- Deck side, as built: `palee_partner_people_within` keeps its ADR-197
  signature `(uuid[], double precision)` (the Places adapter calls it) and
  now counts people with a live Partners profile instead of Γύρω μου
  visibility; `palee_partner_box_badges` is not created, badges come from
  `PartnerEligibility.verification_badges/1` plus the profile's `show_box`.
  The platform queue lives in `PaleeWeb.PlatformPartnerReportController`.

### Verification side (as built)
- Migration file `20270325000000_partner_verification.exs`. Additions to §1:
  `partner_verifications.sponsor_penalty_until` (the 60-day pause lives on
  the sponsor's own verification row), `partner_phone_codes.user_id` (row
  security and the send limits survive a withdrawal) and `consumed_at`.
- "Active membership or package" = a finance `memberships` row (not a guest,
  not past `leaving_on`) with status `active|expiring|comped` and no past
  `expires_on`, or a running `active` package subscription; in an
  organization with `status = active`, `activation = active`,
  `provider_kind in (gym, coach)`. The SQL lives in the internal
  `palee_partner_membership_organization(uuid)` (EXECUTE revoked from
  PUBLIC); `palee_partner_membership_source(uuid)` answers only for the
  session's own person, vendors and system sessions.
- Extra definer functions: `palee_partner_verification_badges(uuid[])`
  (behind `PartnerEligibility.verification_badges/1`),
  `palee_partner_sponsor_standing(uuid[], timestamptz)` (only the session
  person's Buddies), `palee_partner_sponsor_link(bytea)` and
  `palee_partner_redeem_sponsor_link(bytea, timestamptz)` (a sponsor uses a
  link only by its digest). Guard triggers: the person never decides their
  own request; the candidate only cancels/re-asks, the sponsor only answers.
  The phone trigger refuses a number another account verified (not
  withdrawn), under an advisory lock.
- A phone's ciphertext goes with the decision; its keyed hash stays.
- `DELETE /verification/sponsors/:id` takes the sponsor's person id.
- `Eligibility.status/3` takes the vouch count instead of the profile.
- Extra error codes: `partner_already_verified`,
  `partner_verification_in_review`, `partner_verification_request_open`,
  `partner_consent_required`, `partner_sponsor_declined`,
  `partner_sponsor_already_asked`, `partner_vouch_request_closed`,
  `invalid_partner_vouch_decision`, `partner_selfie_invalid`,
  `partner_verification_closed`, `invalid_partner_verification_decision`,
  `invalid_partner_verification_status`, `partner_decision_reason_required`,
  `partner_decision_reason_too_long`.
- `TenantObjectStore` gained `presigned_object_url/3` (expiry in seconds)
  for the 5-minute selfie link.
- Account deletion (`AccountDeletion.remove_profile/1`) calls
  `PartnerVerificationRetention.purge_person/1` before deleting or
  anonymising the profile.
