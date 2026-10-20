# ADR-158: Body snapshots, private photos and coach access
Date: 2026-10-20
Status: Accepted

## Context
Plan §5 P2-M10 and vision §7.7 add Ημερολόγιο › Σώμα: measurement snapshots
(weight, body fat, circumferences, optional front/side/back photos), a chart
per metric, a compare view and a ghost outline of the previous photo. The
plan's ADR-147 sketch set the direction (account-scoped data, personal-session
RLS, coach reads only when shared and audited, consent before photos, weight
as trend). Vision §4.5 and §8.6 make body data private by default and require
that weight can be shown as a trend only and that sections can be switched
off. Board 13 picked every recommended option (weight display
number|trend|hidden, consent per snapshot plus an access log, a coach «Σώμα»
tab) and added an opt-in measure reminder, weight from a connected device,
photos blurred until tapped, slider or side-by-side compare, and sharing a
before/after as a post. ADR-156 (member referrals) and ADR-157 (post media)
are taken, so this is ADR-158.

## Decision
1. **A Body context owns the data, account-scoped.** Tables keyed on
   `user_id`, owner RLS on every one, deleted with the account:
   `body_snapshots` (`taken_at`, `metrics` jsonb in SI units, `notes`,
   `visibility private|coach_numbers|coach_full`, `source manual|garmin`),
   `body_snapshot_photos`, `user_health_consents` (one row per grant;
   withdrawal closes it), `body_settings`. A snapshot holds at least one
   metric or one photo.
2. **Metric catalog in the domain.** weight, body_fat, waist, hips, chest,
   arm, thigh, neck, calf, arm_left/right, thigh_left/right with SI ranges;
   values come in the person's units (metric or imperial, or `units` per
   request) and are stored in SI with three decimals so they show back as
   typed. Edits merge (`null` removes a metric).
3. **Display rules are enforced on the server.** `weight_display`
   `number|trend|hidden` governs weight and body fat everywhere they leave
   the server (list, snapshot, series, compare, journal feed, coach view):
   under `trend` no number, only a word (`steady`, `slightly_down`, `down`,
   `slightly_up`, `up`, from an exponentially smoothed series) and
   `withheld_metrics`; under `hidden` not even that. Values are still stored.
   A coach sees the member's choice too.
4. **Photos reuse the ADR-157 pipeline, privately.** Purpose `body_photo`
   moves from browser re-encoding to server processing (any phone format,
   EXIF/GPS stripped, thumb/feed/full WebP renditions), stays in the private
   bucket under `users/<id>/media/body/`, is attached to its snapshot
   (`attached_type = body_snapshot`) and never counts as a post purpose. The
   photo row copies the renditions' keys so a coach session, which cannot
   read the member's media rows, can be given short-lived presigned URLs.
   Uploads need an active `body_photos` consent. Delete-all removes every body
   upload, leftover objects under the body folder and snapshots left empty.
5. **Coach access.** `GET /api/org/:slug/staff/clients/:user_id/body` (and
   `/body/snapshots/:id`): coach role, `view_health` on that client (own
   clients, all for a head coach), client active in the gym. Only shared
   snapshots; photos only on `coach_full` while consent is active; notes
   never. Row security repeats it (`milos_body_visible_to_acting_coach`,
   `milos_body_photos_consented`, definer functions answering one boolean).
   Every read writes `body_access_log` (gym, coach, subject list|snapshot,
   snapshot ids, whether photos were shown), which the member reads at
   `GET /api/me/body/access-log`; no notification.
6. **Journal.** Feed kind `body`, only in the member's own Ροή (never in a
   coach's journal read or a social feed), shown as `private` or
   `coach_can_view`, not movable on the ladder; switching the Σώμα section off
   hides it.
7. **Settings** (`/api/me/body/settings`): units, weight_display,
   journal_sections (body, wellness, cravings), measure_reminder_weeks (1–12
   or off), default_visibility (the last one used), blur_photos (default
   on), compare_mode (slider default, side_by_side).
8. **Measure reminder.** `BodyRemindersJob` (daily 09:30) finds due people
   through `milos_body_reminders_due` (ids only), checks again in each
   person's session, marks, and sends `body_measure_reminder` (deduped per
   day, neutral copy, no numbers).
9. **Sharing a before/after.** `POST /api/me/body/share` with two of the
   person's snapshots, a pose, optional text, a post audience and
   `confirm: true` (the separate confirmation), plus the consent. The two
   photos are copied into new `post_photo` uploads (already stripped) and
   posted through the community facades; the post never references body
   storage and survives deleting body photos. No metric is ever added.

## Rationale
Keeping numbers out of responses (rather than hiding them in the client) is
the only way "trend only" holds for every client and for coaches. Copying
rendition keys onto the photo row mirrors ADR-157's post snapshot and keeps
row security per table instead of joining media rows across people. A
consent row per grant keeps the history GDPR needs.

## Alternatives Considered
- Keeping body photos browser re-encoded (ADR-148): no HEIC, no thumbnails.
- Using the journal ladder for snapshot visibility: it has no "numbers but
  not photos" rung.
- Logging coach reads in `journal_coach_reads`: body reads are not journal
  entries and the member must read their own log.
- Referencing body photos from a shared post: deleting body photos would
  break the post, and the post would point into private storage.

## Consequences
- Gym purge deletes that gym's access-log rows (like `journal_coach_reads`).
- A personal data export (JSON + photos zip, plan D11) is not built yet.
- Device-sourced weights (`source = garmin`) arrive with P2-M13.
- Blur and compare mode are display hints for the web.

## Implementation Notes
Migration `20261028100000_body_snapshots` (tables, policies, functions,
`media_account_objects_attached_check` and `milos_dangling_post_media` learn
`body_snapshot`, notification type added by reading the current list).
Member routes under `/api/me/body/...`; photo uploads under
`/api/me/body/photos/uploads` (media upload rate limit).
