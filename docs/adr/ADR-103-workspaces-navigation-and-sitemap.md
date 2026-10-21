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

- Owners and admins: Home · Coaching · Finance · Users. Coaching is one
  page with three tabs: Gym classes · Personal training · WODs vault (no
  dropdown, no separate vault link); the other staff pages are dashboard
  tiles; Settings is in the account menu; owners
  also get Settings › Organization and Settings › Role access.
- Coaches: Home · Coaching (the same three tabs, their own classes and
  clients); everything else (their
  clients, form reviews, replies, nutrition plans, appointments, reports) is
  a section of their dashboard.
- Front desk: Home · Check-in · Classes · Finance (only the tabs the gym
  unlocks) · Clients. Accountants: Home · Finance · Clients · Reports.
  Janitors: the Cleaning log.
- Members and athletes: Home (gamification and a Journal call to action) ·
  Training (classes, their workouts, appointments, videos) · Journal (tabs:
  Workouts in folder and tree views, History, PRs, Progress, Coaching,
  Wellbeing).
- Several roles: staff pages merge by union; a client role adds *My
  training* in the account menu.
- Small screens (below the `sm` breakpoint): the header holds only a ☰
  button (opens every link of the bar as a vertical list), the gym name,
  Messages and the avatar. Notifications move into the avatar menu, and
  the avatar shows a red dot while any are unread. Larger screens keep the
  bar with priority+ overflow ("More").

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
"Palee workspaces navigation" artifact (revised version).

## Implementation Notes
Implemented in `aa4ec6d`, `a37ab33` and `4a44f1e`.

- `src/lib/role-navigation.ts` builds the bar from the membership's
  capabilities in one global priority order: Home · Coaching (or Check-in ·
  Classes) · Finance · Users (or Clients) · Reports · Cleaning log.
  So the front desk bar is **Home · Check-in · Classes · Finance · Clients**
  (Finance before Clients), and coach + front desk gives
  **Home · Coaching · Finance**: Check-in and Classes are reached from the
  Coaching tabs, and the coach's clients from the dashboard.
- `src/components/nav/PriorityNav.tsx` measures the links and moves what
  does not fit into "More"; `TopNav` uses it for staff and client bars.
- `SectionTabs.tsx` puts a tab strip over existing pages: Coaching (Gym
  classes · Personal training · WODs vault), Training and Journal.
- The account menu holds Settings and a *My training* / *Staff view* switch
  (`src/lib/view-mode.ts`) for staff who also hold a client role.
- Journal › Workouts (`JournalWorkouts.tsx`) lists finished workouts by type
  in folder and tree views.
- Role-aware staff home (`src/components/admin/StaffHome.tsx`,
  `staff-home.ts`): admins get the dashboard (plus *My clients* when they
  coach); coaches, front desk and accountants get their sections; janitors
  the cleaning log.
- Inventory (ADR-104): an overflow item in the front desk bar, a tile on the
  admin dashboard, and a link from the coach and janitor homes.
- Only English strings were added; other locales follow.
