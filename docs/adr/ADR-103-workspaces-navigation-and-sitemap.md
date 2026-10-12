# ADR-103: Role-Aware Navigation on Today's UI
Date: 2026-10-12
Status: Accepted

## Context
ADR-099 adds role sets and three new staff roles (front desk, accountant,
janitor), so the top bar can no longer be "member links or admin links".
Staff today get two rows (a Dashboard menu with 14 entries plus seven links)
and members six links plus a "More" menu. Two earlier proposals (a workspace shell, then a regrouped bar) were
rejected: the product wants today's screens, look and
feel kept, with only light decluttering, regrouping and progressive
disclosure. The bar must also fit a narrow Android phone in every supported
language (Greek and German labels are long).

## Decision
Today's UI stays as it is. Roles only change which pages, tabs and buttons
show, a few labels, and sections or pages added where something is new. The
full proposal — what each role sees, every multi-role combination, and the
front desk finance access each gym unlocks — is
`docs/architecture/navigation-by-role.md`. In short:

- Owners and admins: Home · Training ▾ (Gym classes · Personal training,
  then Appointments · Check-in desk) · Finance · WODs · Users; the other
  staff pages are dashboard tiles; Settings is in the account menu; owners
  also get Settings › Organization and Settings › Role access.
- Coaches: Home · Classes · Personals · WOD vault; everything else (their
  clients, form reviews, replies, nutrition plans, appointments, reports) is
  a section of their dashboard.
- Front desk: Home · Check-in · Classes · Clients · Finance (only the tabs
  the gym unlocks). Accountants: Home · Finance · Clients · Reports.
  Janitors: the Cleaning log.
- Members and athletes: Home (gamification and a Journal call to action) ·
  Training (classes, their workouts, appointments, videos) · Journal (tabs:
  Workouts in folder and tree views, History, PRs, Progress, Coaching,
  Wellbeing).
- Several roles: staff pages merge by union; a client role adds *My
  training* in the account menu.
- The bar uses priority+ overflow so it fits a narrow phone in every
  language.

## Rationale
Keeping the screens people already know limits relearning; hiding what a
role cannot use and moving rare pages into "More" removes most of the
clutter. Priority+ guarantees the phone fit independently of label length.

## Alternatives Considered
- Workspace shell with new Today screens and a role switcher (first version
  of this ADR): rejected by product; too far from the current UI.
- A fixed number of links per role: fails for long translations on small
  phones; priority+ measures instead.

## Consequences
The web shell reads roles and capabilities (ADR-099) to choose links;
`TopNav` gains priority+ overflow and the account-menu role view. Mockup:
"Milos workspaces navigation" artifact (revised version).

## Implementation Notes
To be completed with the implementation.
