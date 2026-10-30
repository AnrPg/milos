# ADR-286: Injuries reach the box per injury; coach scope and read log
Date: 2026-10-30
Status: Accepted

## Context
A box owner could not see the injuries a member had recorded in the app,
neither on the member's profile (tab «Ευεξία») nor in the box's injury list.
A member's own report is account-scoped (`injury_reports.organization_id`
NULL, the member app has no gym session), while every staff read and the
`injury_reports` RLS policy only reach rows of the session's gym. So no
staff member of any box ever saw a self-reported injury, and the Sharing
page («φαίνονται πάντα στον coach») told members the opposite.

The same review found:
1. A coach with own-client scope (ADR-100) was narrowed only on the
   profile's incidents endpoint. `GET /admin/wellbeing/injuries` and the
   report, update, heal and reopen actions checked only that the actor held
   `view_health`, so a coach read and changed every client's injuries.
2. `admin_only` reports were missing from the staff profile (the query
   reused the member's own, `user_and_admin`-only, read).
3. Injuries are health data (GDPR art. 9). There was no explicit consent
   before staff saw a member's own reports and no record of who read them.

## Decision
ANR picked a switch per injury (decision card, 2026-10-30).
- **«Να το δει το box μου»** (`injury_reports.shared_with_box`), on every
  injury the member records, on by default. While on, the report reaches
  the staff who hold `view_health` (owner, admin, coach) of every box where
  the member is an active member or athlete. The form shows it; each own
  injury in Ευεξία carries it (`PUT /api/wellbeing/injuries/:id/sharing`),
  and turning it off hides the report at once. Reports a box records
  itself have no switch. Existing self-reports become shared: until now the
  app told members their coach always sees injuries.
- **Database**: `palee_injury_reaches_acting_staff(member_id)` (SECURITY
  DEFINER, pins only `search_path`) checks the reader's role and the
  member's active client membership; read-only policies on `injury_reports`
  (`shared_with_box` and `user_and_admin` only) and `injury_status_events`
  use it. A member's own report stays theirs: staff read it, only the member
  changes it (`injury_owned_by_member`, 403).
- **Coach scope**: `StaffInjuryAccess` applies `view_health` to the person
  in every staff use case: the box list is narrowed to the actor's clients
  (`AuthorizeClientAccess.client_ids/2`), and report, update, heal and
  reopen check the person. Owners, admins and head coaches keep `:all`;
  the union of roles still decides (an owner who coaches sees everyone).
- **Staff profile** reads the gym's view of the member
  (`list_box_injuries_for_user/1`): the gym's reports including
  `admin_only`, plus the shared self-reports, each marked `owned_by_member`.
- **Read log** `injury_access_log` (like `body_access_log`): one row per
  member per staff read, with surface `profile`, `box_list` or
  `safety_warning`. The member sees it in Εγώ › Κοινοποίηση under «Ποιος
  είδε τους τραυματισμούς μου» (`GET /api/wellbeing/injuries/access-log`);
  the gym's rows are purged with the gym.
- **Safety warnings** (ADR-124) include shared self-reports for every coach
  running the class, and log each warning shown. The AI scaling advisor
  (ADR-174) keeps reading only the gym's own reports. Realtime refreshes
  reach the staff of every box of the member.

## Rationale
The member decides per report, next to the report, with no account-level
setting to find. On by default keeps the safety intent of the vision
(coaches know about injuries) while every report can be kept private.

## Alternatives Considered
- One explicit consent for all injuries (recommended on the card): the
  cleanest GDPR art. 9 basis, asked once. Not chosen.
- Always share, with a notice only: no control for the member.
- Copying each self-report into every box (one row per gym): duplicates
  health data and its edits; the policy-based read keeps one row.

## Consequences
- Reports a box records itself are unchanged: the box sees them without the
  consent; the member sees the `user_and_admin` ones.
- Journal feed coach reads (ADR-139/162) still show only the gym's own
  injuries; shared self-reports appear on the profile, the box list and the
  warnings.
- A switch that is on by default is a weaker consent under GDPR art. 9 than
  an opt-in; the read log and the per-report switch are the member's
  controls.
