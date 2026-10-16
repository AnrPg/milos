# ADR-140: Journal text ontology (notes, comments, instructions, messages)
Date: 2026-10-16
Status: Accepted

## Context
Before the redesign, "note" meant at least eleven different things: execution
exercise notes, FinishWizard modification text, training-log and log-row notes,
PR notes, injury `note_added` events (never produced), coach notes, coaching
messages sent with `role: :admin` only, workout DSL markers (`!note`,
`!coach-note`, `!athlete-note`, `!scaling-note`, `!safety-note`,
`!equipment-note`), assignment `admin_notes`, `memberships.notes`, and the
new Σημείωση of ADR-139. The owner reviewed every one of them in the report
"Σημειώσεις πριν και μετά το redesign" (Claude Doc
https://claude.ai/code/artifact/88699929-e31e-4004-997a-ed35ca0bdd41,
2026-10-16) and settled the meaning, the name and the screen of each. This ADR
records the result; the report is the long form.

## Decision
Every piece of text is classified by **who writes it, about what, and for
whom**, and by the screen it lives on. Each class has one name, one store and
one UI component.

| Class | Who → for whom | About | Store | Visibility |
|---|---|---|---|---|
| **Σημείωση** | member → self | a standalone thought (may *reference* a workout) | `journal_notes` (ADR-139) | own rung |
| **Σχόλιο** | member → self (and the coach the entry reaches) | one of the member's own entries | `journal_comments` (new) | inherits the entry's rung |
| **Πεδίο** | the entry's author | defines the entry (injury description, review body, form-review question, Rx/Scaled) | the entry's own column | the entry's |
| **Coach note** | staff → staff | a member, optionally one subject entry | `coach_notes` (+ subject) | staff only, audited |
| **Οδηγίες** | workout author → performers | what to do and why, at workout, section, exercise or assignment level; kinds general, scaling, safety, equipment | workout content | performers + staff |
| **Cue** | workout author → performers | how to move, one short pointer on one exercise | workout content | performers + staff |
| **Οδηγός coach** | workout author → coaches | how to run or adapt the workout | workout content | staff only |
| **Μήνυμα** | person ↔ person | a conversation | messaging | participants |
| **Ενημέρωση τραυματισμού** | member or staff | progress of one injury | `injury_status_events` | the injury's |

The word "σημείωση" stays only on the member's Σημείωση and on coach notes.

1. **Σχόλιο is one thing wherever it is written.** The execution NoteModal,
   the FinishWizard step, Καταγραφή and the entry card later all open the same
   form (body + optional structured change) and write to `journal_comments`:
   `id, user_id, organization_id, entry_kind (execution | training_log | pr),
   entry_id, anchor (whole | section | exercise | selection, with its path or
   text range), body, change (the `ModificationPatchValidator` patch shape,
   nullable), written_at, deleted_at`. No origin field: nothing shows "during"
   versus "at the end"; every surface lists one list per exercise ordered by
   `written_at`. A migration moves `exercise_notes`, `exercise_modifications`,
   training-log `notes` and `performed_exercises[].note`, and PR notes into
   comments and drops those columns. Perseverance reads changes from comments.
   Comments have no rung; reads go through the entry's rung (ADR-139).
2. **Πώς νιώθω is a timestamped series, not a daily record.** Five fixed
   questions (sleep, energy, mood, stress, body), each answered on a 4-emoji
   scale (no neutral middle) with optional free text per question; at least
   one answer per submission. Every submission is a new immutable row
   (`wellbeing_check_ins`: `recorded_at`, zone, rung) with one row per answer
   in `wellbeing_check_in_answers (check_in_id, question_key, value 1–4,
   note)`; `question_key` is a catalog in code, so a new question needs no
   migration. A member may submit any number of times a day; the latest is
   the current state, a correction is a new submission, and nothing is edited.
   Ημερολόγιο › Ευεξία shows a per-question timeline (a line with a point at
   each submission). This replaces the 1–5 scales and `sleep_hours` of the
   unreleased migration `20261017111000`, which is rewritten in place; sleep
   hours will come from wearable sync.
3. **Injury updates are events, not comments.** Reporting is a visible
   action (Ευεξία and the Box injury card). An update is an `updated` event in
   `injury_status_events` carrying optional text and the field changes it made
   (`[{field, from, to}]`, e.g. severity); every event is timestamped and
   shown on a per-injury timeline, collapsed by default, to the member and the
   coaches the injury reaches. `note_added` is removed (it had no producer);
   text-only updates are `updated` events with no field changes.
4. **Workout content is Οδηγίες, Cue or Οδηγός coach.** DSL markers become
   `!instructions` (from `!note` / `!athlete-note` at workout or section
   level), `!scaling`, `!safety`, `!equipment` (kinds of Οδηγίες), `!cue`
   (exercise level only; `!athlete-note` / `!note` on an exercise map here)
   and `!coach-brief` (from `!coach-note`). A migration rewrites stored
   workouts; the parser also accepts the old markers and normalises them, so
   pasted legacy text keeps working. `visible_notes` becomes
   `visible_content` and strips `coach-brief` for non-staff. Assignment
   `admin_notes` become the assignment's Οδηγίες.
5. **Coach notes get a subject and a home.** Optional `subject_kind /
   subject_id` (execution, training_log, pr, injury, form_review, assignment).
   They show in the matching tab of the staff member profile and in its
   Coaching › Coach notes subtab. Admins read them only when
   `notes_visible_to_admins`; every read is audited (ADR-101).
6. **Three kinds of message to a member.**
   - **Chat**: anyone the member can message.
   - **Coaching message**: only staff with an *active coaching relationship*
     to the member, whatever their role; always metered as a touchpoint; the
     coach's answer to Ζητάω απάντηση is one. Admin and owner by role never
     send coaching messages (replaces the `role: :admin` match in
     `send_message.ex`).
   - **Message from the box**: front desk, finance, admin or owner about an
     operational matter; not metered; the thread belongs to the gym (any
     permitted staff member can continue it); optional subject (booking,
     payment, membership, facility).
7. **Dead coaching paths are revived, not retired.** Landing `coach_notes` →
   "Τελευταία από τον coach" card in Box › Ο coach σου; `admin_note`
   notification → `coaching_message`; `coach_notes_this_week` and
   `recent_workout_note_count` → Πελάτες μου stats ("coaching messages this
   week", "περιμένουν απάντηση"); `writeAthleteNote` → "+ Coach note" on the
   existing `/clients/:id/coach-notes` endpoint.
8. **One staff member profile with six tabs.** Επισκόπηση, Προπόνηση,
   Ευεξία, Coaching, Οικονομικά, Λογαριασμός; a few sections per tab; tabs
   gated by capability; the active tab is in the URL; the same profile opens
   from Box › Πελάτες μου and from the console. `memberships.notes` stays a
   staff field in Οικονομικά and is removed from the member's own payload
   (`get_landing_page.ex`).
9. **Ladder defaults** (amends ADR-139 §3): workouts and PRs done in a gym
   default to `coach_can_view`; notes, check-ins, body data and personal
   workouts outside a gym default to `private`.

## Rationale
- Classifying by author, subject and reader removes the overloading that made
  "note" ambiguous in code and UI; each class now has one store and one form.
- Comments inheriting the entry's rung means one visibility decision per
  entry, which is what the member actually makes.
- Immutable, timestamped check-ins and injury events give progress over time
  for free and never lose history.
- Gating coaching messages on the relationship rather than the role matches
  who actually coaches, and keeps touchpoint metering meaningful.

## Alternatives Considered
- **Keeping `exercise_notes` and `exercise_modifications` apart.** They
  describe the same thing (what happened in an exercise) and the owner asked
  for no distinction.
- **One editable check-in per day.** Loses the intra-day progression the
  owner wants on the timeline.
- **Renaming every workout marker to "cue".** Erases the difference between
  what/why, how-to-move and coach-only text.
- **Letting admins send coaching messages.** Admin contact is managerial, and
  metering it as coaching misstates the coaching delivered.

## Consequences
- Rewrite of migration `20261017111000` (unreleased) for check-ins; new
  migrations for comments, coach-note subjects, message kinds, DSL rewrite.
- OpenAPI, generated client and web forms change for executions, logs, PRs,
  check-ins, injuries, coach notes and messaging.
- The admin user profile (`AdminUserProfile.tsx`) is replaced by the tabbed
  staff member profile.
- ADR-139 §8 (check-ins on 1–5) is superseded by §2 here.
