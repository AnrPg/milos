# Phase 8 Backend Plan: Admin Drill-Down Surfaces

**Date:** 2026-06-13  
**Status:** Draft  
**Scope:** Backend-only product requirements, specifications, task list, and implementation plan for the two planned Phase 8 admin drill-down surfaces:

- Financial Member Drill-Down
- Coaching Athlete Drill-Down

This document stays at the product and delivery level. It defines required backend outcomes, business expectations, data responsibilities, validation points, and delivery sequencing without prescribing low-level implementation details.

---

## 1. Purpose

Phase 8 defines `/admin` as an operational workspace where the admin can move from high-level signals into focused user-level decision making. The summary cards and high-level analytics are not sufficient on their own; the admin must be able to open a specific person and understand their status, history, and next actions from a single backend-supported drill-down surface.

This plan covers the backend work needed to make those drill-down surfaces complete, trustworthy, and action-ready.

---

## 2. Surfaces Covered

### 2.1 Financial Member Drill-Down

The admin selects a member from the financial area and opens a detailed profile for commercial and lifecycle management.

The backend must support the admin in answering questions such as:

- Who is this member?
- What is their current membership state?
- What package or entitlement relationship do they currently have?
- What payments, invoices, credits, discounts, or adjustments have occurred?
- What is about to expire, renew, or require intervention?
- What finance actions can be taken now?

### 2.2 Coaching Athlete Drill-Down

The admin selects an athlete from the coaching area and opens a detailed profile for programming, adherence, and support decisions.

The backend must support the admin in answering questions such as:

- Who is this athlete?
- How active are they recently?
- What workouts have they been assigned and completed?
- What performance patterns are visible?
- What notes, coaching context, or recent concerns should be visible?
- What coaching action should happen next?

---

## 3. Product Outcomes

The backend implementation is complete when both drill-down surfaces are able to support the admin’s full read-and-act workflow without requiring the admin to piece together separate screens or rely on incomplete summaries.

Successful outcomes:

1. The admin can open a single user drill-down and receive a coherent, decision-ready profile.
2. The payload is organized around operator needs, not raw storage structures.
3. All visible actions are backed by validated backend behavior.
4. The backend distinguishes between historical facts, current status, and recommended next actions.
5. The data shown is scoped, consistent, and safe for admin use.
6. The surface remains useful even when some optional data is absent.

---

## 4. Non-Goals

This plan does not cover:

- frontend layout, styling, or component composition
- search implementation itself
- calendar export
- offline/PWA work
- new product domains beyond the two decided drill-down surfaces
- broad hardening or refactor work outside the drill-down requirements

---

## 5. Common Backend Requirements Across Both Surfaces

These requirements apply to both drill-down surfaces.

### 5.1 Identity and Access

- The backend must ensure that only authorized admin users can access drill-down data and actions.
- Access rules must be consistent across read and write operations.
- Unauthorized access attempts must fail clearly and safely.

### 5.2 Single-Surface Cohesion

- Each drill-down read must return a payload that is complete enough for the intended admin workflow.
- The backend should avoid forcing the frontend to assemble operator-critical state from many disconnected calls unless that separation is part of the product behavior.
- The surface should feel like one profile with sections, not a set of unrelated records.

### 5.3 Fact vs Status vs Action Clarity

- Historical events must be distinguishable from current status.
- Current operational status must be explicit, not inferred only from raw history.
- Available actions must align with the current state and business rules.

### 5.4 Graceful Partial Data Handling

- The backend must define behavior for users with incomplete data.
- Missing optional data must not break the drill-down surface.
- Empty states must remain meaningful and interpretable by the admin.

### 5.5 Auditability

- Admin-triggered actions from the drill-down surfaces must be attributable and reviewable.
- The backend must preserve enough history to explain why the current state exists.

### 5.6 Sorting, Grouping, and Relevance

- The backend must provide data ordered and grouped in a way that matches operator review patterns.
- Recent, actionable, and unresolved items should be easier to inspect than stale history.

### 5.7 Validation and Error Meaning

- Invalid actions must be rejected based on business meaning, not only malformed input.
- The backend must return failure outcomes that help the frontend explain what the admin needs to change or verify next.

### 5.8 Consistency Expectations

- When the admin takes an action from a drill-down surface, subsequent reads should reflect the new state predictably.
- Derived summaries and detailed records should not contradict one another.

---

## 6. Financial Member Drill-Down Requirements

### 6.1 Surface Purpose

The Financial Member Drill-Down exists to support lifecycle management, financial review, and commercial intervention for a single member.

### 6.2 Required Read Sections

The backend must support the following read sections for a member drill-down:

1. **Member identity summary**
   - core identifying information needed for admin recognition
   - membership-relevant role/context
   - current account standing at a glance

2. **Current membership status**
   - whether the member is active, expiring, expired, paused, cancelled, or otherwise limited
   - effective dates relevant to the current state
   - visible explanation for why the member is in that state

3. **Current package / plan relationship**
   - package or plan currently associated with the member
   - practical meaning of that relationship for the admin
   - whether the member is between packages, unmanaged, or awaiting action

4. **Financial timeline**
   - payments
   - invoices
   - credits or adjustments
   - discounts/promotions where relevant
   - reversals or voided events where relevant

5. **Outstanding and upcoming items**
   - unpaid or unresolved finance items
   - upcoming renewal or expiration pressure
   - items that need admin attention soon

6. **Operational notes / context**
   - commercially relevant notes that help the admin act correctly
   - visibility into important constraints or manual decisions

7. **Action readiness**
   - what actions the admin may take next
   - what actions are blocked
   - why a blocked action is unavailable

### 6.3 Required Read Behaviors

- The backend must provide a current-state snapshot that the admin can trust without manually recalculating it from history.
- Financial history must preserve meaningful chronology.
- Corrections and reversals must remain visible as part of the story, not disappear.
- The backend must distinguish between settled, pending, cancelled, adjusted, and invalidated financial states where the product recognizes those differences.
- The member’s profile must remain understandable even when they have a long or irregular finance history.

### 6.4 Required Actions

The backend must support the product-approved actions exposed from the financial drill-down surface, including:

1. updating current membership information where the admin is expected to manage it
2. renewing or extending the member’s finance relationship where applicable
3. cancelling or ending the relevant membership relationship where applicable
4. reviewing or recording the finance outcomes needed to keep the member profile accurate

This plan does not prescribe the final action list verbatim for the UI, but the backend must define:

- action eligibility rules
- required inputs per action
- business outcomes of each action
- side effects on current status, future status, and visible history

### 6.5 Business Rules to Be Explicit

The backend requirements must explicitly define:

- what makes a member financially active
- what makes them expiring soon
- what makes them expired
- what qualifies as unpaid, partially settled, credited, reversed, or voided where those states exist in the product
- when renewal is allowed
- when cancellation is allowed
- when membership edits are allowed
- what happens if the member has no managed finance profile yet

### 6.6 Edge Cases to Cover

- member has no membership profile yet
- member has historical finance records but no active package
- member has active status with upcoming expiration
- member has unpaid items but still appears active
- member has reversal/credit activity that changes how totals should be understood
- member has multiple relevant recent finance events and the admin needs an unambiguous current picture

### 6.7 Acceptance Criteria

The Financial Member Drill-Down backend is complete when:

1. the admin can open a member and receive a coherent financial profile
2. current state and historical events do not contradict each other
3. available finance actions match the member’s actual lifecycle state
4. blocked actions return understandable reasons
5. the profile remains usable for active, expiring, expired, and unmanaged members

---

## 7. Coaching Athlete Drill-Down Requirements

### 7.1 Surface Purpose

The Coaching Athlete Drill-Down exists to support coaching review, adherence monitoring, performance interpretation, and athlete communication for a single athlete.

### 7.2 Required Read Sections

The backend must support the following read sections for an athlete drill-down:

1. **Athlete identity summary**
   - core identifying information needed for admin recognition
   - athlete context relevant to coaching
   - current participation status at a glance

2. **Recent activity summary**
   - recent training behavior
   - last completed or last active moments that matter operationally
   - visible sense of whether the athlete is engaged, drifting, or inactive

3. **Assigned workout view**
   - relevant assigned workouts
   - their current status
   - upcoming vs completed vs missed/overdue distinctions where product meaning exists

4. **Execution and completion history**
   - historical workout record relevant to coaching review
   - enough detail for the admin to understand consistency and follow-through

5. **Performance / score trends**
   - structured view of how scores or outcomes are changing over time
   - visibility into improvement, stagnation, or irregularity where the data supports it

6. **Notes and coaching context**
   - existing admin notes
   - athlete-submitted contextual information relevant to training review
   - recent narrative context that should influence coaching decisions

7. **Attention / follow-up cues**
   - who needs follow-up
   - why they need follow-up
   - what signal triggered that concern

8. **Action readiness**
   - what coaching actions are available now
   - which are blocked
   - why a blocked action is unavailable

### 7.3 Required Read Behaviors

- The backend must support a drill-down that helps the admin understand both volume and quality of engagement.
- The surface must show the relationship between assignments, completions, scores, and notes clearly enough for coaching decisions.
- Recent and actionable coaching context must not be buried behind long history.
- The athlete’s story must remain understandable even if they have sparse, irregular, or mixed training data.

### 7.4 Required Actions

The backend must support the product-approved coaching actions exposed from the athlete drill-down surface, including:

1. writing a coaching/admin note to the athlete
2. recording the contextual information needed to support future coaching review

If additional drill-down actions are approved later, the backend must define them with the same standards:

- eligibility rules
- required inputs
- resulting athlete-visible and admin-visible outcomes
- impact on drill-down state

### 7.5 Business Rules to Be Explicit

The backend requirements must explicitly define:

- what qualifies as active vs inactive in the coaching surface
- which workout history is relevant for drill-down review
- how recent activity should be represented when the athlete has assignments but no completions
- how scores should be represented when workouts use different scoring styles
- what note history is visible in the drill-down
- how admin notes should appear in subsequent athlete-facing or admin-facing reads where applicable

### 7.6 Edge Cases to Cover

- athlete has assigned workouts but has not completed any
- athlete has completions but limited scoring detail
- athlete has old notes but no recent activity
- athlete has recent activity but no notes
- athlete has long history and the admin still needs a concise summary first
- athlete has no drill-down-worthy history yet but should still be coach-manageable

### 7.7 Acceptance Criteria

The Coaching Athlete Drill-Down backend is complete when:

1. the admin can open an athlete and understand recent engagement quickly
2. assignment history, completion history, score patterns, and notes form one coherent profile
3. the admin can add a note and see it reflected correctly in subsequent reads
4. the profile remains useful for active, inconsistent, inactive, and newly assigned athletes

---

## 8. Shared Specification Checklist

Before implementation begins for either surface, the backend product contract should be explicit for each of the following:

1. surface purpose
2. user story
3. entry point from admin workflow
4. required read sections
5. section-level meaning
6. current-state definitions
7. history rules
8. available actions
9. blocked-action behavior
10. empty-state behavior
11. error behavior
12. audit expectations
13. acceptance criteria

---

## 9. Task Inventory

This section lists the backend work in task form without prescribing internal implementation choices.

### 9.1 Discovery and Alignment Tasks

- confirm the exact product scope of the Financial Member Drill-Down
- confirm the exact product scope of the Coaching Athlete Drill-Down
- identify any overlap or ambiguity between finance, coaching, feedback, wellbeing, scheduling, and workout ownership
- identify which admin actions are in-scope now vs deferred
- align the drill-down sections with the existing Phase 8 product intent

### 9.2 Contract Definition Tasks

- define the backend response contract for the Financial Member Drill-Down
- define the backend response contract for the Coaching Athlete Drill-Down
- define the backend contract for each drill-down write action
- define current-state meanings and lifecycle vocabulary
- define empty-state and partial-data behavior
- define error categories and failure meanings

### 9.3 Read Model Tasks

- define what information the financial profile must expose
- define what information the coaching profile must expose
- define how historical records are grouped and ordered
- define which summary indicators are required at the top of each profile
- define how unresolved and urgent items are surfaced

### 9.4 Action Semantics Tasks

- define the allowed finance actions from the member surface
- define the allowed coaching actions from the athlete surface
- define action preconditions
- define action results
- define visible side effects of each action
- define when actions must be rejected

### 9.5 Validation Tasks

- define member-state validation rules
- define finance-action validation rules
- define athlete-state validation rules
- define coaching-note validation rules
- define consistency rules between historical records and current state

### 9.6 Testing and Verification Tasks

- define scenario coverage for active, inactive, expiring, expired, unmanaged, and newly created member states
- define scenario coverage for active, drifting, inactive, sparse-history, and newly assigned athlete states
- define happy-path action scenarios
- define invalid-action scenarios
- define partial-data scenarios
- define history interpretation scenarios

### 9.7 Documentation Tasks

- document the final product contract for both drill-down surfaces
- document the meaning of each status shown in the profiles
- document each admin action and its expected business outcome
- document any deferred follow-up work discovered during delivery

---

## 10. Recommended Delivery Order

This order is intended to reduce ambiguity and surface product gaps early.

### Stage 1: Product Contract Definition

- lock the exact purpose and section list for each drill-down
- lock the admin actions that belong to each surface
- lock lifecycle/status language
- lock acceptance criteria

### Stage 2: Financial Member Drill-Down Read Scope

- complete the financial member read contract first
- verify that it supports real admin decisions before action endpoints are finalized
- confirm unmanaged, expiring, expired, and adjusted-history cases

### Stage 3: Financial Member Drill-Down Actions

- add the finance actions that belong inside the member drill-down
- verify that each action updates the member story coherently

### Stage 4: Coaching Athlete Drill-Down Read Scope

- complete the athlete drill-down read contract
- verify that the admin can understand adherence, history, and context without guessing

### Stage 5: Coaching Athlete Drill-Down Actions

- add the coaching actions that belong inside the athlete drill-down
- verify that note-writing and follow-up behavior are reflected correctly in later reads

### Stage 6: Cross-Surface Consistency Review

- review naming, status language, urgency signals, and action semantics across both surfaces
- ensure the two drill-downs feel like parts of one admin workspace rather than unrelated features

### Stage 7: Final Acceptance Pass

- validate both surfaces against the product outcomes in this document
- record deferred items explicitly
- confirm readiness for frontend integration

---

## 11. Granular Plan by Surface

### 11.1 Financial Member Drill-Down Plan

#### A. Requirements Capture

- define who counts as a member in this surface
- define what the admin must know within the first few seconds of opening the profile
- define what financial history is essential vs secondary
- define what actions the admin must be able to take from this surface

#### B. Surface Contract

- define the top summary section
- define the membership status section
- define the package/plan section
- define the timeline/history section
- define outstanding/upcoming items section
- define notes/context section
- define actions section

#### C. State Definitions

- define membership lifecycle statuses
- define renewal-related meanings
- define unresolved finance item meanings
- define unmanaged member meaning

#### D. Action Definitions

- define update behavior
- define renewal behavior
- define cancellation/end behavior
- define finance-recording or finance-resolution actions that belong here

#### E. Validation Matrix

- identify which states permit which actions
- identify which actions are blocked for which reasons
- identify what the admin must be told when an action fails

#### F. Scenario Review

- active healthy member
- expiring member
- expired member
- unmanaged member
- member with complicated adjustments
- member with incomplete or irregular history

#### G. Acceptance Review

- confirm the surface supports recognition, diagnosis, and action
- confirm the surface remains useful without optional context
- confirm the member’s financial story is coherent

### 11.2 Coaching Athlete Drill-Down Plan

#### A. Requirements Capture

- define who counts as an athlete in this surface
- define what the admin must know within the first few seconds of opening the profile
- define what recent coaching signals are essential
- define what actions the admin must be able to take from this surface

#### B. Surface Contract

- define the top summary section
- define the recent activity section
- define the assigned workout section
- define the execution/completion history section
- define the score trends section
- define the notes/context section
- define the attention/follow-up section
- define the actions section

#### C. State Definitions

- define active vs drifting vs inactive meanings
- define what counts as recent participation
- define how assigned-but-not-completed status should appear
- define what signals should drive attention cues

#### D. Action Definitions

- define note-writing behavior
- define note visibility and persistence expectations
- define what happens after a note is recorded

#### E. Validation Matrix

- identify when note creation is allowed
- identify what note inputs are required or rejected
- identify what the admin must be told when an action fails

#### F. Scenario Review

- newly assigned athlete
- active athlete with strong consistency
- athlete with irregular adherence
- inactive athlete needing follow-up
- athlete with history but sparse recent context
- athlete with recent notes but little measurable data

#### G. Acceptance Review

- confirm the surface supports recognition, diagnosis, and action
- confirm the surface helps the admin make a coaching decision quickly
- confirm the athlete’s training story is coherent

---

## 12. Risks to Watch

These are delivery risks, not implementation prescriptions.

- the drill-down becomes a raw data dump instead of an operator profile
- current status is ambiguous and has to be inferred manually
- actions exist without clear eligibility rules
- historical data and current summaries disagree
- the surface only works well for ideal users and breaks down for sparse or irregular histories
- the frontend has to reconstruct too much meaning because the backend contract is incomplete
- related domains leak into the drill-down without clear ownership or product intent

---

## 13. Definition of Done

This backend plan is fulfilled when:

1. both drill-down surfaces have complete backend product contracts
2. both surfaces support coherent admin read workflows
3. both surfaces support the approved admin actions with explicit validation rules
4. the backend behavior is defined for incomplete, irregular, and edge-case user histories
5. acceptance scenarios have been reviewed for both surfaces
6. the frontend can integrate without inventing business meaning on its own

---

## 14. Three-Phase Implementation Plan

This section turns the backend plan into a delivery sequence with three phases. Each phase ends with a backend outcome that is reviewable on its own and reduces ambiguity for the next phase.

### Phase 1: Financial Member Drill-Down

**Goal:** Complete the backend contract and business behavior for the Financial Member Drill-Down so the admin can open a member profile, understand the current finance state, review relevant history, and take the approved finance actions.

**Primary outcome:** A backend-supported financial member profile that is readable, actionable, and internally coherent.

#### Scope

- define the financial member drill-down product contract
- define the required read sections
- define lifecycle and current-state meanings
- define history and timeline meanings
- define outstanding and upcoming finance indicators
- define the finance actions that belong inside the drill-down
- define action eligibility and rejection rules
- define edge-case handling for unmanaged, expiring, expired, adjusted, and irregular member histories

#### Requirements

- the admin can recognize the member and their current finance state immediately
- the backend distinguishes current state from historical events clearly
- the backend exposes enough finance history to explain the current state
- the backend defines which finance actions are currently available
- blocked or invalid actions return meaningful outcomes
- the member profile remains understandable even when the member has sparse or irregular finance history

#### Deliverables

- financial drill-down backend requirements finalized
- financial drill-down read contract finalized
- finance action contract finalized
- status and lifecycle definitions finalized
- acceptance scenarios for the financial member surface finalized

#### Task List

1. confirm the exact purpose of the financial member surface
2. define the read sections in operator order
3. define current-state vocabulary and meanings
4. define the required financial timeline/history sections
5. define unresolved and upcoming finance indicators
6. define the in-scope admin finance actions
7. define action eligibility rules
8. define invalid-action and blocked-action outcomes
9. define empty-state and partial-data behavior
10. review edge cases across different member lifecycle states
11. validate the surface against the acceptance criteria
12. document any deferred or out-of-scope finance actions explicitly

#### Exit Criteria

- the financial drill-down contract is complete enough for frontend integration
- the financial lifecycle states are unambiguous
- all in-scope finance actions have clear business meaning
- edge cases have defined backend behavior

### Phase 2: Coaching Athlete Drill-Down

**Goal:** Complete the backend contract and business behavior for the Coaching Athlete Drill-Down so the admin can open an athlete profile, understand recent participation and coaching context, review history and performance signals, and take the approved coaching actions.

**Primary outcome:** A backend-supported coaching athlete profile that is readable, actionable, and useful for real coaching decisions.

#### Scope

- define the coaching athlete drill-down product contract
- define the required read sections
- define activity-state meanings
- define assignment, execution, completion, and score review expectations
- define note and context expectations
- define follow-up cues and attention signals
- define the coaching actions that belong inside the drill-down
- define action eligibility and rejection rules
- define edge-case handling for inactive, newly assigned, sparse-history, and irregular athletes

#### Requirements

- the admin can recognize the athlete and their current participation state immediately
- the backend provides a coherent view of assignment, completion, score, and note context
- recent and actionable coaching information is easy to interpret
- the backend defines what coaching actions are available now
- blocked or invalid actions return meaningful outcomes
- the athlete profile remains useful even with sparse history or uneven participation

#### Deliverables

- coaching drill-down backend requirements finalized
- coaching drill-down read contract finalized
- coaching action contract finalized
- activity-state definitions finalized
- acceptance scenarios for the coaching athlete surface finalized

#### Task List

1. confirm the exact purpose of the coaching athlete surface
2. define the read sections in operator order
3. define activity-state vocabulary and meanings
4. define the required assignment and completion review sections
5. define the required performance and score interpretation sections
6. define the note and coaching-context sections
7. define follow-up and attention cues
8. define the in-scope coaching actions
9. define action eligibility rules
10. define invalid-action and blocked-action outcomes
11. define empty-state and partial-data behavior
12. review edge cases across different athlete participation states
13. validate the surface against the acceptance criteria
14. document any deferred or out-of-scope coaching actions explicitly

#### Exit Criteria

- the coaching drill-down contract is complete enough for frontend integration
- athlete activity states are unambiguous
- note-writing and related coaching actions have clear business meaning
- edge cases have defined backend behavior

### Phase 3: Cross-Surface Alignment and Readiness

**Goal:** Align both drill-down surfaces into one coherent backend product contract for `/admin`, confirm they behave consistently, and prepare them for frontend integration and end-to-end validation.

**Primary outcome:** The two drill-down surfaces behave like parts of one admin workspace rather than independent profile experiments.

#### Scope

- align naming, lifecycle vocabulary, and action semantics across both surfaces
- align empty-state and error behavior
- align urgency and follow-up cues
- confirm the backend contracts are complete for frontend use
- confirm acceptance coverage across both surfaces
- record any explicit post-Phase-8 follow-up items

#### Requirements

- both surfaces use consistent operator language where the product meaning overlaps
- both surfaces distinguish summary, current state, history, and actions clearly
- both surfaces define their failure and blocked-action behavior consistently
- both surfaces are complete enough that the frontend does not need to invent business meaning
- remaining gaps are documented as deliberate follow-up work rather than silent omissions

#### Deliverables

- aligned backend product contract across both drill-down surfaces
- final acceptance review for both surfaces
- consolidated deferred-work list for anything intentionally left outside this slice
- backend readiness sign-off for frontend integration

#### Task List

1. review both drill-down contracts side by side
2. align naming and lifecycle vocabulary
3. align action-state and blocked-action patterns
4. align empty-state and partial-data behavior
5. align urgency and attention signaling
6. review acceptance scenarios across both surfaces
7. identify any unresolved product ambiguities
8. record deferred items explicitly
9. confirm backend readiness for frontend integration

#### Exit Criteria

- both surfaces are consistent at the product-contract level
- no critical ambiguity remains in lifecycle, state, action, or error meanings
- the frontend has a complete backend story for both drill-down surfaces
- deferred items are explicit and bounded

---
