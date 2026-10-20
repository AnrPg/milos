# ADR-159: Ευεξία and Λιγούρα (wellness entries and cravings)
Date: 2026-10-20
Status: Accepted (sections marked «board 14» are filled in from ANR's answers)

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
   Πώς νιώθω: owner policy plus `milos_entry_visible_to_acting_coach`, so a
   coach of the provenance gym reads an entry only on a rung that reaches
   them. Everything starts `private`. Preferences are owner-only. Tenant
   purge removes rows with that gym's provenance (ADR-117); «Διαγραφή όλων»
   per section (`wellness`, `cravings`) removes the member's rows for good.
8. **API.** `/api/me/wellness` (days `from..to`, at most 92), `entries`,
   `cravings`, `preferences`, and `DELETE /api/me/wellness?sections=`.

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
- Meal photos need a `meal_photo` media purpose (account scope, client
  re-encoded, like body photos); it lands after M10's media changes so the
  two milestones don't fight over the same constraint.
- Journal feed and visibility kinds for wellness and cravings, the coach
  summary and per-item switches follow board 14.

## Implementation Notes
- `WellnessInput.usec/1` normalises every timestamp to microseconds, since
  all wellness columns are `utc_datetime_usec`.
