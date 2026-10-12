# ADR-103: Workspaces, Navigation and Sitemap per Role
Date: 2026-10-12
Status: Proposed — awaiting product approval

## Context
The app grew one surface at a time: members have six bar links plus a "More"
menu, staff have a two-row bar (Dashboard menu with 14 entries plus 7 links),
and every Phase C service added another page. ADR-099 adds role sets and
three new roles, so a person can be, say, a coach and a member in the same
gym, or an owner of three gyms. Piling every role's surfaces into one bar
would make the app unusable. The product goal is a minimal, decluttered UI
with progressive disclosure: show what the person needs where and when they
need it.

## Decision

### 1. Workspaces
A **workspace** is one job a person does in one gym. Each role maps to one
workspace; a person sees only the workspaces their roles allow:

| Workspace | Roles | Purpose |
|---|---|---|
| **Train** | member, athlete | My training: book, log, progress, my coach |
| **Coach** | coach | My clients, my classes, my queue |
| **Desk** | front desk | Today's arrivals, check-in, sales at the desk |
| **Manage** | owner, admin | Run the gym |
| **Books** | accountant | Money |
| **Cleaning** | janitor | Record and review cleaning |

A multi-role person never gets a merged bar. They switch workspace from one
control (gym · workspace), which also switches gym. The app opens in the last
used workspace, or the first staff workspace for staff. A dot on the switcher
tells them another workspace needs attention (e.g. a coach with a waiting
form review while in Train).

### 2. Navigation shape (every workspace)
- **Top bar**: gym · workspace switcher (left) — **at most four
  destinations** — inbox (one icon for notifications and messages) — avatar
  menu (profile, membership, settings, language, sign out).
- **Mobile**: the same destinations as a bottom tab bar; the switcher and
  inbox stay in the header.
- Secondary sections live **inside** a destination as tabs or filters, never
  in the bar.
- Settings and rare actions (gym settings, roles, organizations, subscription)
  live in the avatar menu or in the switcher, not in the bar.

### 3. Home = Today
Every workspace opens on **Today**: a short, prioritized feed of what needs
action now, each card with one primary action. Empty sections are hidden; when
nothing needs attention the page says so and offers the one most likely
action. Dashboards with numbers move to the destination they belong to.

### 4. Sitemap

**Train** — Today · Book · Journal · Coach¹
- Today: next class or appointment, today's assigned workout (start), quick
  log, package status only when it needs attention (expiring, out of visits).
- Book: classes and appointments in one calendar, filters by type.
- Journal: history (do it again, that day's performance) · vault · PRs
  (Pantheon) · progress² · videos² (tabs).
- Coach¹: my coach(es), messages, form reviews², nutrition plan², programming.
- Avatar: profile, membership & billing (company plan only when invited),
  wellbeing, settings.

**Coach** — Today · Clients · Schedule · Library
- Today: classes now and next (roster, attendance), waiting form reviews,
  overdue replies, appointments, athletes needing attention.
- Clients: my clients (all for head coaches) → client page with tabs:
  overview (status, health flags), programming, notes, nutrition, progress,
  messages. "Take an athlete" and "Invite a client" live here.
- Schedule: my classes and my PT slots in one calendar.
- Library: workouts · videos · challenges (tabs).

**Desk** — Today · Clients · Schedule
- Today: check-in, arrivals by class, waitlists, quick actions (new client,
  sell package, take payment), today's cleaning status.
- Clients: directory with membership status and contact.
- Schedule: every class and appointment; book for a client.

**Manage** — Today · People · Schedule · Business
- Today: approvals (bookings, coach self-assignments), overdue money,
  capacity and attendance alerts, expiring memberships.
- People: clients · staff & roles (multi-role editor, head coach, coach
  assignments) · invitations.
- Schedule: classes & series (with coach), appointments, check-in, locations.
- Business: finance (packages, members, invoices, corporate, promotions,
  referrals) · analytics & marketing · reviews.
- Coaching and library: an owner or admin who coaches uses the Coach
  workspace; otherwise they reach programming from a client's page in People
  and the library from Schedule/Business links where it is used.
- Switcher / avatar: gym settings; owners also get **My gyms** (create,
  transfer, delete, platform subscription).

**Books** — Today · Invoices · Packages · Reports
**Cleaning** — Log (one screen: areas → start/finish with task checklist;
my recent entries). Owners, admins and Desk read it from their Today and from
Manage › Schedule › Locations.

¹ Only when the client has a coach or a coaching service.
² Only when the package includes it (ADR-098).

### 5. URLs
Workspace routes are `/org/:slug/<workspace>/<destination>` (e.g.
`/org/acme/coach/clients/:id`). Train keeps short client URLs (`/`, `/book`,
`/journal`, `/coach`). Existing URLs redirect.

## Rationale
One job per screen keeps cognitive load low for single-role users (most
accounts) and stops multi-role users' bars from growing with each role. Four
destinations fit a mobile tab bar. A Today feed puts the next action first and
hides empty areas, which is the progressive disclosure the product asks for.

## Alternatives Considered
- One merged bar filtered by capabilities: rejected; grows with roles and
  mixes "my training" with "my clients".
- Role-specific separate apps: rejected; one account and one session per
  person, switching should be instant.
- A sidebar with every section: rejected; dense, poor on mobile.

## Consequences
The web shell gains a workspace model driven by roles and capabilities
(ADR-099); pages move under workspace routes with redirects; the admin
Dashboard dropdown and the member "More" menu disappear. Today feeds need
small read models per workspace. Implementation follows approval of this
proposal and its mockup.

## Implementation Notes
To be completed after approval.
