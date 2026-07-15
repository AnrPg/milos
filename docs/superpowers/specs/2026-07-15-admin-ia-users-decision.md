# Admin Information Architecture and User Profiles Decision
Date: 2026-07-15
Status: Approved for implementation

## Purpose

This decision captures the final product and information architecture decisions for the admin workspace restructuring, the new Users section, and the placement of Finance, Analytics and Marketing, Challenges, Classes, Personal Coaching, Workouts, Messages, and App configurations.

This is a detailed product decision record, not a terse summary. It is meant to be the reference for implementation, QA, and future discussion. It keeps only the final decisions from the discussion. Earlier alternatives that were superseded are intentionally omitted.

## Product Intent

The admin workspace should feel like a practical operating system for the gym owner. It should make the most common admin jobs easy to find without turning every page into a dashboard.

The final IA is organized around these jobs:

- Find a person and understand everything relevant about them.
- Run finance operations.
- Manage classes.
- Manage personal coaching and assigned programming.
- Manage workout content.
- Review analytics and marketing/gamification performance.
- Communicate with users.
- Triage what needs attention today.

The core principle is separation by job:

- `Users` is person-centered.
- `Finance` is operation-centered.
- `Analytics & Marketing` is interpretation and growth-centered.
- `Dashboard` is triage and navigation.
- Domain workspaces remain the places where their detailed operations happen.

The implementation should preserve the existing visual language and component patterns. This is an IA refinement and additive capability pass, not a redesign mandate.

## Final Primary Admin Navigation

The admin top navigation will expose these primary destinations:

1. Dashboard
2. Users
3. Finance
4. Classes
5. Personal Coaching
6. Workouts
7. Analytics & Marketing
8. Messages

`App configurations` is not a primary top navigation item. It should be a subtle utility inside Dashboard, ideally represented by a small settings icon that reveals the full label on hover or focus.

### Navigation Meaning

Each primary destination has a distinct responsibility:

| Destination | Responsibility |
|---|---|
| Dashboard | Triage, overview, quick actions, compact navigation hub |
| Users | Canonical directory and person dossier for all users |
| Finance | Operational finance actions and urgent finance attention |
| Classes | Existing class/schedule operations, renamed only |
| Personal Coaching | Existing athlete programming/coaching operations, renamed only |
| Workouts | Workout content library, creation, editing, and publishing |
| Analytics & Marketing | Aggregate reporting, marketing/gamification, challenges |
| Messages | Communication center |

Navigation labels should use these names consistently in desktop nav, mobile nav, dashboard shortcuts, and page headers where the page is owned by the destination.

## Responsive Navigation

On small screens, most top navigation buttons should be hidden. The main mobile navigation point is the Dashboard button, which keeps the current dropdown behavior and acts as the compact admin navigation hub.

Preferred visible mobile destinations:

1. Dashboard
2. Classes
3. Personal Coaching
4. Messages

All other admin destinations should remain reachable through the Dashboard dropdown or equivalent compact navigation affordance.

### Mobile Behavior

The mobile navigation should not try to squeeze every primary destination into the top bar. It should keep the most time-sensitive operational destinations visible and make Dashboard the main expansion point.

Mobile-visible items should prioritize workflows likely to happen away from a desk:

- checking the day
- managing class operations
- checking personal coaching work
- responding to messages

Hidden items are still important, but are less likely to require one-tap access on a narrow screen:

- Users
- Finance
- Workouts, if space is limited
- Analytics & Marketing
- App configurations

The Dashboard dropdown should remain predictable and complete. It should not become a dumping ground with inconsistent names. It should mirror the primary IA and include App configurations as a utility.

## Dashboard

Dashboard becomes a command center and navigation hub, not a large tabbed workspace.

Dashboard should focus on:

- Today: upcoming classes, pending bookings, due coaching work.
- Attention: urgent finance items, health incidents, unread messages, stale athletes.
- Quick actions: create class, create workout, assign workout, create invoice, message user.
- Recent activity: PRs, completions, payments, incidents.
- Compact analytics preview with links to Analytics & Marketing.
- App configurations as a subtle settings utility.

Dashboard should not contain full finance, coaching, classes, workouts, or analytics workspaces.

### Dashboard Sections

The Dashboard should be restructured around admin triage:

#### Today

Shows the most immediate operational facts:

- upcoming classes
- pending booking decisions
- due or overdue coaching work
- time-sensitive class or personal coaching items

#### Attention

Shows the highest-value exceptions:

- urgent finance blockers
- overdue invoices
- health incidents that need follow-up
- unread or pending messages
- stale athletes or users requiring attention

This section should avoid low-signal metrics. For example, active membership count is not an urgent attention item and belongs in Analytics & Marketing.

#### Quick Actions

Provides fast entry points into common admin actions:

- create class
- create workout
- assign workout
- create invoice
- message user
- open user directory

Quick actions should route to the owning workspace rather than duplicating complex forms in Dashboard unless a compact existing component already supports it cleanly.

#### Recent Activity

Shows recent events that help the admin understand what changed:

- PRs
- workout completions
- payments
- incidents
- relevant messages

#### Compact Analytics Preview

Dashboard may show small previews that link to Analytics & Marketing, but it should not host full analytics dashboards.

#### App Configurations

App configurations should be available from Dashboard in a subtle way. The preferred presentation is a small settings icon that expands or reveals the full label on hover/focus. It should be discoverable but visually secondary.

## Users

`Users` is the canonical admin directory and person profile area.

The Users section should allow admins to view all users:

- members
- athletes
- admins

Suggested user directory tabs:

- All
- Members
- Athletes
- Admins

Clicking a user opens a profile view. The profile should be role-aware but comprehensive. Finance information is shown for both members and athletes.

Every user profile should expose the relevant available information:

- identity and account information
- role
- finance information for members and athletes
- training history
- detailed PRs
- scores
- health incidents and injury reports
- class participation where applicable
- personal coaching context where applicable
- messages and communication context
- admin actions, including role/account controls where permitted

Role affects emphasis and availability, not the existence of the profile shell.

### Users Directory

`/admin/users` should be the place an admin goes when the question starts with "who".

The directory should support:

- all users in one list
- role filtering
- search by nickname or available indexed identity fields
- quick recognition of role
- compact attention/status signals
- entry into the profile view

Suggested tabs:

- `All`
- `Members`
- `Athletes`
- `Admins`

Suggested row/card content:

- nickname and avatar if available
- role
- high-level status
- attention count or most important attention reason
- last relevant activity
- finance status summary where available
- training/coaching summary where available
- quick action to open profile

The directory should not become the place for large operational tables such as all invoices, all class bookings, or all workouts. Those stay in the owning workspaces.

### User Profile

`/admin/users/:id` should present a role-aware dossier. The profile is the admin's unified view of a person, not a replacement for every domain surface.

Recommended profile sections:

1. Overview
2. Finance
3. Training history
4. PRs
5. Scores
6. Health / incidents
7. Coaching context
8. Class participation
9. Messages
10. Admin actions

#### Overview

Overview should include:

- nickname
- role
- account status
- joined date
- primary attention items
- available profile sections
- high-level recent activity

#### Finance

Finance information should be shown for both members and athletes.

The Finance profile section should include the relevant per-user finance state:

- membership or entitlement status
- active package or subscription
- invoices
- payments
- credits
- outstanding or blocked items
- relevant finance actions

Finance operations that already exist in the Finance workspace should be reused or deep-linked. The user profile should make those operations accessible in the person context without duplicating unrelated aggregate finance analytics.

#### Training History

Training history should show the user's class and workout participation where applicable:

- class participation
- assigned workouts
- workout executions
- completion dates
- source of execution, such as class, assigned, or self-selected
- workout type
- relevant scale level

#### PRs

Admins should be able to see detailed PRs in the user profile.

PR detail should include:

- workout or section name
- score type
- previous score where available
- new score
- improvement context
- date
- workout type

#### Scores

Scores should be visible separately or within training history when useful. The profile should support score inspection by workout, date, type, and scoreable section.

#### Health / Incidents

Health and incident information should include:

- injury reports
- body area
- severity
- current status
- started/healed dates where available
- training limitations
- notes/tags where available

This section should be shown in a way that helps admins coach safely without turning the profile into a medical record system.

#### Coaching Context

For athletes, this section is richer and should include:

- assigned workout state
- adherence cues
- coaching notes
- inactive or stale programming signals
- follow-up actions

For members and admins, the section may be empty, compact, or limited to applicable coaching interactions.

#### Class Participation

For members, class participation should emphasize:

- bookings
- attendance
- no-shows or cancellations
- recent class history

For athletes and admins, show data only if applicable.

#### Messages

Messages should show communication context and thread references:

- direct messages
- class-related threads
- assignment/workout threads
- unread or pending communication state

The Messages workspace remains the full communication center.

#### Admin Actions

Admin actions may include:

- role management where permitted
- account-level actions
- profile-specific finance actions
- message user
- jump to owning operational workspace

Admin actions must respect existing authorization and architecture boundaries.

## Finance

`/admin/finance` should use the existing Finance Operations experience, plus a succinct operational attention strip under the hero.

Finance is the operational money workspace. It should answer: "What finance action do I need to perform now?"

Keep only the most crucial attention items in the Finance overview strip, fitting in one line where practical:

- overdue invoices
- unallocated or blocked finance items
- pending refund or reversal actions
- urgent entitlement or membership blockers
- referral reward actions only when they require operator attention

Do not keep broad analytical metrics in `/admin/finance`, such as active membership counts, revenue trend charts, package distribution, or long-range membership analytics. Those belong under Analytics & Marketing.

### Finance Page Responsibility

Finance answers: "What finance action do I need to perform now?"

It should include operational workflows such as:

- invoices
- payments
- credits
- package assignment
- refunds and reversals
- operational queues
- promotions
- referrals
- packages

The page should not be framed as a reporting dashboard. The hero and first content area should direct attention to current work, not historical interpretation.

### Attention Strip

The attention strip should be succinct. It sits under the hero and should fit in one line on normal desktop widths where practical.

Good attention strip items:

- overdue invoices
- unallocated payments or credits
- blocked entitlements
- pending refund/reversal work
- referral rewards needing manual action

Avoid in the attention strip:

- active memberships
- broad revenue totals
- revenue charts
- package distribution
- long-range trend metrics
- low-urgency counts

If more items exist than fit, prioritize by urgency and provide a link to the relevant queue or Analytics & Marketing view.

### Finance Tab Deep Links

Finance should support bookmarkable tab selection for Marketing links:

- `/admin/finance?tab=promotions`
- `/admin/finance?tab=referrals`
- `/admin/finance?tab=packages`

These links should select the existing Finance operation tabs.

## Classes

The existing classes/schedule page should not be structurally changed as part of this IA pass.

Only rename or relabel the existing page to fit the new IA. Existing design patterns, page behavior, and implementation shape should be preserved.

### Classes Boundary

Classes is the admin's operational surface for in-person classes. It should continue to own:

- class calendar
- scheduled slots
- bookings
- attendance
- booking approval/rejection
- class-level messages where already supported

No redesign of this surface is part of the IA pass. The requirement is naming and navigation alignment only.

## Personal Coaching

The existing personal coaching/athlete programming page should not be structurally changed as part of this IA pass.

Only rename or relabel the existing page to fit the new IA. Existing design patterns, page behavior, and implementation shape should be preserved.

### Personal Coaching Boundary

Personal Coaching is the operational workspace for individualized remote athlete programming. It should continue to own:

- assigned workouts
- athlete programming workflow
- coaching notes
- adherence and follow-up cues where already present
- athlete-specific coaching operations

No redesign of this surface is part of the IA pass. User profiles may link into Personal Coaching, but should not replace it.

## Workouts

Workouts is a primary entity and remains a top-level admin destination.

The Workouts area should cover workout library, workout creation/editing, publishing, and related workout content operations. It should stay separate from Classes and Personal Coaching because workouts are reused by both class programming and personal programming.

### Workouts Boundary

Workouts owns reusable training content:

- workout library
- workout creation
- workout editing
- publishing
- scale variations
- workout previews
- content lifecycle

Workouts should not absorb Challenges in the final IA. Challenges move to Analytics & Marketing.

## Analytics & Marketing

The analytics destination is named `Analytics & Marketing`.

This section owns aggregate reporting and marketing/gamification surfaces.

Suggested subsections:

- Overview
- Finance Analytics
- Training Analytics
- Coaching Analytics
- User Engagement
- Health / Incidents
- Challenges
- Marketing

Finance analytics moves here from the old Finance dashboard. Examples:

- active memberships
- revenue charts
- package distribution
- broad financial trends
- retention or membership trend views

### Analytics & Marketing Responsibility

Analytics & Marketing answers: "What is happening over time, and what engagement or marketing levers are active?"

It should include reporting and interpretation, not day-to-day operational tables.

Suggested subsection meanings:

#### Overview

A high-level snapshot across finance, training, coaching, health, engagement, and marketing.

#### Finance Analytics

Financial reporting and interpretation:

- active memberships
- monthly revenue
- revenue trends
- package distribution
- retention or expiration trends
- high-level finance KPIs

#### Training Analytics

Training participation and performance reporting:

- attendance trends
- workout completion trends
- popular workout types
- score trends
- class participation summaries

#### Coaching Analytics

Personal coaching reporting:

- athlete adherence
- inactive athletes
- assignment completion
- coaching follow-up trends
- programming workload

#### User Engagement

Engagement reporting:

- active users
- message engagement
- review or feedback activity
- notification interaction where available

#### Health / Incidents

Aggregate health and incident reporting:

- incident frequency
- body area patterns
- severity distribution
- unresolved reports

#### Challenges

Challenge management and performance as a gamification/marketing surface.

#### Marketing

Links and summary references for marketing-related operations, including promotions, referrals, and packages.

## Challenges

Challenges are not a primary top navigation item.

Challenges belong under `Analytics & Marketing`, because they are treated as a marketing, engagement, and gamification mechanism rather than a primary operational entity.

Challenges should be reachable from Analytics & Marketing and may be referenced from relevant analytics cards. They should not appear as a standalone primary nav button.

Challenge performance belongs in Analytics & Marketing because it reflects engagement and gamification effectiveness.

## Marketing Links to Finance Operations

The Marketing subsection of Analytics & Marketing should include references that navigate to the relevant Finance operation tabs:

- Promotions -> `/admin/finance?tab=promotions`
- Referrals -> `/admin/finance?tab=referrals`
- Packages -> `/admin/finance?tab=packages`

These should be links into the operational Finance surface, not duplicated management UIs inside Analytics & Marketing.

### Marketing Link Presentation

The Marketing subsection should present these references as clear navigation cards or links, not as embedded duplicate tab content.

Each reference should make the destination explicit:

- Promotions: opens the Finance operations Promotions tab.
- Referrals: opens the Finance operations Referrals tab.
- Packages: opens the Finance operations Packages tab.

This keeps Marketing strategic and Finance operational.

## Route and Compatibility Expectations

Existing routes should be preserved or redirected where practical. The IA change should not break old bookmarks unnecessarily.

Expected route semantics:

| Destination | Expected Route Semantics |
|---|---|
| Dashboard | Existing admin dashboard route remains the hub |
| Users | New admin users route and profile route |
| Finance | `/admin/finance` is operational finance |
| Classes | Existing schedule/classes page is relabelled |
| Personal Coaching | Existing coaching/assigned-workouts admin page is relabelled |
| Workouts | Existing admin workouts route remains primary |
| Analytics & Marketing | Analytics route expands or is relabelled |
| Messages | Existing/admin messages route remains communication center |
| App configurations | Existing settings functionality is relabelled and subtly placed |

Redirects or aliases should be used when route names change but old routes are likely to exist in code, tests, or user bookmarks.

## API and Data Contract Expectations

The new Users area should not rely on frontend-side stitching of unrelated raw responses where product meaning belongs in the backend contract.

Preferred backend shape:

- a paginated admin users directory endpoint
- a common admin user profile shell endpoint
- focused sub-endpoints for heavy profile sections

Recommended endpoints:

- `GET /api/admin/users`
- `GET /api/admin/users/:id`
- `GET /api/admin/users/:id/finance`
- `GET /api/admin/users/:id/training-history`
- `GET /api/admin/users/:id/prs`
- `GET /api/admin/users/:id/incidents`
- `GET /api/admin/users/:id/messages`

The exact endpoint set may be adjusted during implementation if existing endpoints can be reused cleanly, but the architecture principle remains: profile composition belongs in Application Services and public contracts, not ad hoc controller or frontend logic.

## Design Expectations

Use existing design patterns and components where possible.

The admin UI should remain:

- minimal
- colorful but controlled
- uncluttered
- mobile-first
- consistent with current cards, tables, tabs, buttons, and spacing

Avoid introducing a new visual system for this work. Prefer:

- route relabelling
- nav reorganization
- section relocation
- thin profile shells
- component reuse
- deep links to owning operational pages

Avoid:

- redesigning Classes
- redesigning Personal Coaching
- duplicating Finance operation tabs inside Analytics & Marketing
- making Dashboard a large multi-domain workspace
- adding new dependencies unless clearly necessary and approved

## Implementation Principles

Changes should be additive and minimal where possible.

Implementation should preserve existing design patterns, style, spacing, component behavior, and visual tone. Avoid wholesale page redesigns where a rename, redirect, tab relocation, or thin shell can achieve the IA goal.

Backend changes must preserve the project's architecture rules:

- OpenAPI before controller code.
- Controllers call Application Services.
- Cross-context profile/dossier reads are composed in Application Services.
- Contexts remain bounded and communicate through public APIs or events.
- Generated TypeScript clients are regenerated, never manually edited.

## Acceptance Summary

The IA work is successful when:

- The top navigation exposes the final primary destinations.
- Small screens use Dashboard as the main compact navigation hub.
- Dashboard is a triage and quick-action surface, not a multi-domain workspace.
- Users exists as the canonical person directory.
- User profiles show finance for members and athletes.
- User profiles expose training history, detailed PRs, scores, and health incidents.
- Finance is operational and based on the current finance operations surface.
- Finance only keeps a compact urgent attention strip under the hero.
- Finance analytics moves to Analytics & Marketing.
- Challenges moves to Analytics & Marketing.
- Marketing links open Promotions, Referrals, and Packages tabs in Finance.
- Classes and Personal Coaching are renamed/relabelled only, without structural redesign.
- Workouts remains a top-level primary entity.
- App configurations is subtle and reachable from Dashboard.
