# ADR-139: Journal visibility ladder, notes and check-ins
Date: 2026-10-16
Status: Accepted

## Context
The product vision (§7.7, §8.2) gives every journal entry one visibility
badge on a five-rung ladder: Μόνο εγώ, Ο coach μου μπορεί να το δει, Ζητάω
απάντηση, Αξιολόγηση, Ανάρτηση. Today the same idea is spread over unrelated
mechanisms: a per-user PR switch (`user_pr_sharing_preferences.coach_visibility`,
ADR-129), the `admin_only`/`user_visible` audience of reviews, injuries that
coaches always see, and executions that the coach drill-down shows without
asking anyone. Training-log entries have no visibility at all, and the two
private entry types the vision starts with, Σημείωση and Πώς νιώθω, do not
exist. Decision D4 (2026-10-15) chose one stored visibility on every entry
type; the owner then chose to build notes and check-ins in Phase 1
(2026-10-16).

## Decision
1. **One ladder.** `MilosTraining.Journal.Domain.Visibility` defines the
   ordered enum `private < coach_can_view < coach_reply_requested < rated <
   posted`. A rung *reaches the coach* when it is `coach_can_view` or above.
   The same text values are stored everywhere, guarded by a check constraint
   and by the SQL function `milos_journal_visibility_reaches_coach(text)`.
2. **Stored per entry, as `journal_visibility`.** Reviews and injuries
   already own an unrelated `visibility` column (the audience of a rating or
   report), so the ladder column has its own name on every table:

   | Kind | Table | Rungs a member can choose | Default |
   |---|---|---|---|
   | `execution` | `workout_executions` | private, coach_can_view, coach_reply_requested | member's `workout` default |
   | `training_log` | `training_log_entries` | private, coach_can_view, coach_reply_requested | member's `workout` default |
   | `pr` | `user_pr_records` | private, coach_can_view, coach_reply_requested | member's `pr` default |
   | `injury` | `injury_reports` | coach_can_view, coach_reply_requested | coach_can_view |
   | `note` | `journal_notes` (new) | private, coach_can_view, coach_reply_requested | member's `note` default |
   | `check_in` | `wellbeing_check_ins` (new) | private, coach_can_view, coach_reply_requested | member's `check_in` default |
   | `review` | `reviews` | none: a review *is* the `rated` rung | rated |

   `posted` is never chosen directly: it is set when a post attaches the
   entry (ADR-138, M7). Reviews store no ladder column, because a review can
   only ever be `rated`; the feed reports `rated` for them.
3. **Per-member defaults** live in `journal_visibility_defaults(user_id,
   kind, visibility)` for the kinds `workout`, `pr`, `note` and `check_in`,
   owner-only under RLS. Without a row the built-in default applies:
   workouts and PRs `coach_can_view` (what coaches see today), notes and
   check-ins `private` (vision §4.5). Εγώ › Κοινοποίηση & ορατότητα edits
   them; changing a default can also move every existing entry of that kind
   that sits on the private / coach_can_view rungs.
4. **The PR switch becomes the PR default.** The backfill writes each PR's
   rung from its owner's `coach_visibility`, copies an opt-out into
   `journal_visibility_defaults`, and drops `user_pr_sharing_preferences`.
   The coach read policy of ADR-129 keeps its shape (provenance gym, active
   membership, `milos_acting_user_coaches`) but now asks the record's own
   rung instead of the owner's switch.
5. **Backfill.** Executions and training-log entries done in a gym get
   `coach_can_view` (coaches already see them), personal ones `private`;
   injuries `coach_can_view`; PRs as in 4. All additive; `down` restores the
   PR switch from the defaults and drops the new columns.
6. **Coach reads honour the ladder.** The coach drill-down and the new
   `GET /api/org/:slug/staff/clients/:user_id/journal` (`GetClientJournal`)
   return only entries recorded in that gym whose rung reaches the coach,
   plus every injury (vision §4.5), for staff who pass the ADR-129 coach
   seam. Each entry returned is written to `journal_coach_reads`, the same
   audit as coach-note reads (ADR-101). Executions and training-log entries
   stay readable by the tenant at the database level, because KPIs and
   leaderboards aggregate them; the ladder governs the coach's view of a
   member's individual entries, not anonymous aggregates, which keep their
   own opt-ins.
7. **Ζητάω απάντηση is a message.** Choosing `coach_reply_requested` needs a
   question and an entry recorded in a gym where the member has an active
   coaching relationship. `RequestCoachReply` sends the question as a direct
   message from the member to that coach, with `subject_kind`/`subject_id`
   on the message pointing at the entry. It therefore enters the existing
   reply queue (ADR-098) and the answer arrives in messages, as the vision
   says. Without a coach the request is refused (`no_active_coach`).
8. **Notes** (`Journal` context, `journal_notes`): topic `technique |
   thought | mood | goal`, body, optional link to an execution, training-log
   entry or workout, written in a gym (provenance) and soft-deleted.
   **Check-ins** (`Wellbeing` context, `wellbeing_check_ins`): mood, energy
   and stress on 1–5, an optional note, recorded time and zone. Both are
   owner-only under RLS with an ADR-129-style coach read policy gated by the
   rung; both are written in the member's gym context and read personally.
9. **One feed.** `GET /api/me/journal` (`GetJournalFeed`) merges every kind
   for the member across gyms, newest first, with an opaque cursor over
   `(occurred_at, kind, id)` and an optional `kinds` filter. Each source
   context answers `list_journal_items(user_id, before, limit)`; the
   application layer merges them. Every item carries its rung and the rungs
   the member may choose, so the web renders the badge and picker from the
   server. `PUT /api/me/journal/entries/:kind/:id/visibility` moves an entry
   on the ladder.

## Rationale
- One enum and one column name make the badge, the feed, coach reads and
  later posting (M7) a single code path instead of a mapping per type.
- Storing the rung per entry is what lets a member hide one PR or share one
  note; a per-user switch cannot.
- Reusing the ADR-129 seam and the coach-note audit keeps one definition of
  "my coach" and one audit trail for sensitive reads.
- Routing reply requests through messages reuses the reply queue, its SLA
  and its notifications rather than building a second inbox.

## Alternatives Considered
- **Renaming the existing `visibility` columns to `audience`.** Clean names,
  but touches every review and injury read and filter for no behavioural
  gain; a distinct column name is unambiguous.
- **A ladder column on reviews.** It could only ever hold `rated`; storing a
  constant adds a write path and a constraint for nothing.
- **Enforcing the ladder for executions with RLS.** Would break KPIs,
  leaderboards and gym analytics, which legitimately aggregate the tenant's
  executions. The ladder protects individual entries at the read model.
- **A separate "reply request" queue.** Duplicates ADR-098's queue, SLA and
  overdue alerts.

## Consequences
- The PR coach switch on the sharing page becomes the PR default with
  "apply to existing PRs".
- Every journal item in the web shows a server-provided badge and picker; the
  client-side merge of M4 (`journal-flow.ts`) is replaced by the feed.
- Coaches see less than before for members who choose `private`, which is the
  point. Nothing tells the coach that hidden entries exist.

## Implementation Notes
- 2026-10-16: §8's check-in shape (1–5 scales, one editable record) is
  superseded by ADR-140 §2 (four-point answers per question, immutable
  timestamped submissions). §3 defaults are refined by ADR-140 §9.
