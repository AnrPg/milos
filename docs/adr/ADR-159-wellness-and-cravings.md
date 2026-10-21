# ADR-159: Ευεξία and Λιγούρα (wellness entries and cravings)
Date: 2026-10-20
Status: Accepted (board 14 answered: Q1 B, Q2 A, Q3 A, Q4 A, Q5 B, Q6 B, Q7 A, Q8 A, Q9 A, every extra ticked)

## Context
Plan §5 P2-M11 and vision §7.7 add the «Σήμερα» card to Ημερολόγιο › Ευεξία:
water (+1 glass, daily goal), sleep (hours and quality, or from a device),
meals (in or out of plan, optional photo, the coach's macros which can be
hidden), mood and stress, and Λιγούρα (intensity, causes, outcome,
«Χρειάζομαι στήριξη»), with a week strip. §8.6 makes the ethics binding: no
calories, neutral words, nothing compared with anyone, every section can be
switched off. ADR-147 sketched `wellness_entries` and `craving_entries`.
M10 (Σώμα, ADR-158) runs in parallel and owns the journal-section switches,
units and `user_health_consents`; this ADR reuses them. Πώς νιώθω (ADR-140)
already records mood and stress; the coach's plan is Nutrition (ADR-098).

## Decision
1. **A Wellness bounded context, separate from Wellbeing.** Wellbeing keeps
   injuries and Πώς νιώθω; Nutrition keeps the coach's plan; Wellness owns
   water, sleep, meals, cravings and the member's targets. The read model
   for the page (`Application.GetMyWellness`) composes Wellness with
   Wellbeing's check-ins, so no context reaches into another's tables.
2. **Entries of a kind with a validated value.** `wellness_entries(kind,
   value jsonb, occurred_at, occurred_tz, occurred_on, source, external_id,
   corrected_at, journal_visibility, organization_id?)`. Each kind is a
   domain module behind `EntryValue` (`cast/1`, `counts_at/2`): `Water`
   (ml), `Sleep` (bedtime and wake time, or minutes, and/or quality 1–5;
   naps flagged), `Meal` (slot, `in_plan|off_plan`, note, photo, optional
   hand portions, optional hunger/fullness; never calories). A new kind is a
   module, a registry line and a constraint value. One glass is one entry,
   so undo is a delete and the day total is a sum; values are stored in SI
   units so a new glass size never rewrites history.
3. **The member's day.** Every entry stores the zone it was logged in and
   the local date it counts for (`LocalDay`); a night counts on the morning
   you wake. Past days can be filled in or corrected up to 7 days back;
   nothing can be logged in the future.
4. **Devices.** Rows from Garmin (M13) or later Apple Health / Health
   Connect use their `source` and an `external_id`, unique per user and
   source. A newer device reading updates the row unless the member
   corrected it (`corrected_at`) or deleted it.
5. **Cravings.** `craving_entries(intensity 1–10, triggers ⊂ {stress,
   fatigue, boredom, social, hunger, other}, outcome ongoing|resisted|
   ate_off_plan + outcome_at, note, support_requested_at, follow_up_at,
   followed_up_at)`. The outcome may come later; a craving left ongoing
   gets one «Πώς πήγε;» `follow_up_minutes` (20) later, dropped once the
   member settles it. Asking for support is a one-way stamp; who receives
   it is the buddy's job (M12, ADR to follow).
6. **Targets are the member's.** `wellness_preferences(water_goal_ml,
   glass_ml, sleep_goal_minutes, hidden_items)`; defaults 2 L, 250 ml, 7 h.
   The day summary grades each item only against these targets, with the
   neutral statuses `none | partial | full`; meals reflect logging (the
   three main meals logged), never what was eaten; cravings are a count.
7. **Privacy.** Personal rows with optional gym provenance, exactly like
   Πώς νιώθω: owner policy plus `palee_entry_visible_to_acting_coach`, so a
   coach of the provenance gym reads an entry only on a rung that reaches
   them. Everything starts `private`. Preferences are owner-only. Tenant
   purge removes rows with that gym's provenance (ADR-117); «Διαγραφή όλων»
   per section (`wellness`, `cravings`) removes the member's rows for good.
8. **API.** `/api/me/wellness` (days `from..to`, at most 92), `entries`,
   `cravings`, `preferences`, `meal-photos` (upload), `export?sections=`
   and `DELETE /api/me/wellness?sections=`.
9. **Consent (board 14).** Logging anything needs M10's `health_data`
   consent (`health_data_consent_required`, 403); the page asks on the first
   visit, together with which items to show. Coach reads also need it, in
   row security (`palee_health_data_consented`), so withdrawing it hides
   every widened entry at once while the member keeps their data.
10. **Meal photos (Q4).** A `meal_photo` media purpose (account scope,
    `media_private`, server-stripped renditions, ADR-157), attached to the
    entry (`wellness_entry`), released with it, shown with signed URLs, and
    never posted without a separate confirmation.
11. **Tiles and order (Q1 B).** The page is a grid of tiles in the member's
    order (`item_order`; items never placed follow in default order), with
    per-item switches (`hidden_items`: water, sleep, meals, plan, mood) in
    «Προσαρμογή» (Q9 A). A hidden item leaves the card, the week, Νέα
    καταχώρηση and the coach summary; its data stays until deleted.
12. **Nudges (Q2, Q6).** A craving left open hears «Πώς πήγε;» once, 20
    minutes later. The water reminder (`water_reminder`) is on by default
    once the member has a water goal, that is once they start using Ευεξία
    (ANR's board 14 note), and can be switched off; it comes at most once
    a local day between 15:00 and 21:00 while the day is under
    half the goal. Definer lookups name who is due; each person is handled
    in their own session; dedupe keys hold each nudge to one. Lock-screen
    text never names a craving or a number. No streaks and no «you missed»
    messages anywhere (Q7).
13. **Ροή (Q8 A).** One «Ευεξία» item per local day (water, sleep, meals,
    with the member's summary) and each Λιγούρα as its own item. The day
    never moves; single entries do (`wellness_entry`, `craving` on the
    journal ladder, including Ζητάω απάντηση). A coach sees only widened
    entries, never targets or photos. The coach's weekly summary is M12's.
14. **The coach's plan (Q5 B).** Daily hand portions (palm of protein,
    cupped hand of carbs, fist of vegetables, thumb of fat; halves) on `nutrition_plans.portion_targets`, derived from grams
    until the coach writes their own, plus optional `meal_slots` the meal
    sheet offers. Meals take portions; the day sums them against the plan.
    Calories never reach the member (`Nutrition.for_member/1`). The member
    reads their plans across gyms in their personal session through
    `palee_own_nutrition_plans()` (no calories, no text).
15. **Λιγούρα support (Q6).** «Χρειάζομαι στήριξη» stamps the craving once
    and calls the `SupportRequests` port with only the craving id; M12's
    buddy adapter decides who hears. Craving details never go to a buddy.
16. **Export (Q9).** Per section, JSON, with signed links to meal photos.

## Rationale
One table with typed value modules keeps the read model one query, lets
devices write the same rows, and adds kinds without schema churn, while the
domain keeps validation as strict as columns would. An event per glass is
what makes undo, devices and changed glass sizes trivially correct.

## Alternatives Considered
- A table per kind: stricter in SQL, but every new kind and every device
  becomes a migration and the day query a union.
- Daily aggregate rows (water total per day): loses undo, device merge and
  timing; rejected.
- Mood and stress in Wellness: would duplicate ADR-140; the page reads the
  latest Πώς νιώθω instead.

## Consequences
- Migrations that touch shared check constraints (media purposes, attached
  types, notification types, message subjects) read the current definition
  and add to it, so milestones can land in any order.
- The coach's weekly summary, buddies and who receives a support request
  belong to M12; until then the support port is a no-op.
- Devices (M13) write the same rows through `upsert_device_entry`.

## Implementation Notes
- `WellnessInput.usec/1` normalises every timestamp to microseconds, since
  all wellness columns are `utc_datetime_usec`.
