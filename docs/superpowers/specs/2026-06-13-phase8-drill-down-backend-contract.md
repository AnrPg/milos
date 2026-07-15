# Phase 8 Admin Drill-Down Backend Contract

**Date:** 2026-06-13  
**Status:** Ready for frontend integration  
**Scope:** Cross-surface product contract for the Phase 8 admin drill-down
backend surfaces.

This document records the aligned backend meaning of the two decided Phase 8
drill-down surfaces:

- Financial Member Drill-Down
- Coaching Athlete Drill-Down

It is intentionally product-facing. It defines what the frontend can rely on
without needing to infer business meaning from raw records.

---

## 1. Shared Contract Principles

Both drill-downs represent one admin workspace pattern:

1. identify the person
2. summarize their current state
3. explain why that state exists
4. show relevant history
5. surface urgent or follow-up items
6. expose available and blocked actions

The two surfaces may use domain-specific section names, but overlapping product
meaning uses the same vocabulary and response conventions.

---

## 2. Shared Vocabulary

### Identity

Each drill-down identifies the subject with:

- `user_id`
- `nickname`
- `role`

Finance may also include `user_type` when membership records preserve a
finance-specific user type snapshot.

### Current State

Each drill-down has a current-state section with:

- `state`: the current lifecycle or participation state
- `reason`: the primary reason the backend selected that state
- `urgency`: `normal`, `attention`, or `urgent`

Finance names this section `current_status`.

Coaching names this section `recent_activity`.

### Attention Items

Actionable concerns are list items with:

- `type`
- `severity`: `low`, `medium`, or `high`
- `reason`
- `title`

Finance names this list `outstanding_items`.

Coaching names this list `attention_cues`.

### Actions

Each action is exposed as:

- `key`
- `available`
- `reason`

Available actions return `reason: null`. Blocked actions return a stable reason
string that the frontend can display or map.

---

## 3. Financial Member Drill-Down

### Purpose

Support membership lifecycle and finance decisions for a single member.

### Required Sections

- `identity`
- `current_status`
- `package_relationship`
- `financial_timeline`
- `outstanding_items`
- `operational_context`
- `actions`

### State Meanings

- `unmanaged`: the user exists but does not yet have a finance membership
  profile.
- `active`: the member currently has an active finance relationship.
- `expiring`: the member is active but close enough to expiry to need attention.
- `expired`: the finance relationship has passed its effective end.
- `paused`: the relationship is intentionally paused.
- `cancelled`: the relationship has been ended.

Finance urgency is driven by overdue invoices, open invoices, and expiry
pressure.

### History Meaning

The financial timeline is chronological and may include invoices, payments,
credits, promotion redemptions, and reversal records. Corrections remain visible
instead of being hidden.

### Actions

The current finance action contract includes:

- `update_membership`
- `assign_package`
- `renew_membership`
- `cancel_membership`
- `record_payment`
- `create_invoice`
- `create_manual_credit`

Blocked actions explain the missing prerequisite or lifecycle constraint.

---

## 4. Coaching Athlete Drill-Down

### Purpose

Support coaching review, adherence monitoring, performance interpretation, and
follow-up for a single athlete.

### Required Sections

- `identity`
- `recent_activity`
- `assigned_workouts`
- `execution_history`
- `score_trends`
- `notes_context`
- `attention_cues`
- `actions`

### State Meanings

- `active`: the athlete has a recent completed workout inside the active
  participation window.
- `drifting`: the athlete has some recent signal, such as an upcoming
  assignment or an older completion, but is not clearly active.
- `inactive`: the athlete has no recent completion or meaningful current
  participation signal.

Coaching urgency is driven by overdue assignments, inactive participation, and
other follow-up cues.

### History Meaning

Execution history is ordered for admin review. Score trends are grouped by
workout type where measurable scores exist. Notes context combines admin notes
and athlete-submitted execution notes so recent coaching context is not buried.

### Actions

The current coaching action contract includes:

- `write_note`
- `review_history`
- `assign_workout`

The note write action persists an admin coaching note and should be reflected in
subsequent drill-down reads.

---

## 5. Error and Empty-State Behavior

Both admin drill-down reads require admin authorization.

Unknown subjects return a not-found response.

Subjects with sparse or incomplete source data still return a coherent
drill-down when the user exists and the surface can manage that empty state.

Blocked actions remain visible with `available: false` and a stable `reason`.

---

## 6. Acceptance Review

The backend is ready for frontend integration when:

- both drill-downs expose identity, current state, history, attention, and
  actions in operator order
- both current-state sections include `state`, `reason`, and `urgency`
- action and attention item shapes match across the two surfaces
- OpenAPI publishes the required drill-down sections and failure responses
- sparse finance and coaching histories still produce meaningful profiles
- note creation is reflected in later coaching drill-down reads

---

## 7. Deferred Work

No new backend follow-up work is deferred by this alignment slice.

Existing Phase 8 deferred work remains tracked in `docs/technical_debt.md`.
