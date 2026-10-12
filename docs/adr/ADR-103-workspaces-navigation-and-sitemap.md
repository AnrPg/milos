# ADR-103: Role-Aware Navigation on Today's UI
Date: 2026-10-12
Status: Proposed — awaiting product approval

## Context
ADR-099 adds role sets and three new staff roles (front desk, accountant,
janitor), so the top bar can no longer be "member links or admin links".
Staff today get two rows (a Dashboard menu with 14 entries plus seven links)
and members six links plus a "More" menu. A first proposal (workspaces with
new Today screens) was rejected: the product wants today's screens, look and
feel kept, with only light decluttering, regrouping and progressive
disclosure. The bar must also fit a narrow Android phone in every supported
language (Greek and German labels are long).

## Decision
1. **Same shell, links by role.** The header keeps its look (brand, links,
   notifications, Chat, account menu). Each role sees only its links, in
   priority order:

   | Role | Links (priority order) | "More" menu |
   |---|---|---|
   | Owner, admin | Home · Users · Classes · Personal Coaching · Finance | Appointments · Check-in desk · Workouts · Content · Analytics & Marketing · Challenges · Reviews · Wellbeing · Settings |
   | Coach | Home · My clients · Classes · Personal Coaching · Workouts | Appointments · Content · Challenges |
   | Front desk | Home · Check-in desk · Classes · Clients · Sales | Appointments · Cleaning log |
   | Accountant | Home · Finance · Clients · Reports | — |
   | Janitor | Cleaning log | — |
   | Member | Home · Schedule · History · Pantheon | Videos · Progress · Coaching · Appointments (when included) |
   | Athlete | Home · My Workouts · History · Pantheon | same as member |

2. **Priority+ bar.** Links render in priority order; whatever does not fit
   the bar's measured width (screen, language) moves into the last menu
   ("More" / "Περισσότερα"). The bar never wraps or scrolls, from a 360 px
   phone to desktop, in all twelve languages.
3. **Decluttering.** The staff "Dashboard" row is removed (it repeated the
   bar); Billing moves into the account menu for members and athletes; each
   Home shows what needs action first and hides empty sections.
4. **Several roles.** The account menu gains "View as" (e.g. Coach /
   Member) and the name shows the current view as a badge; the bar shows that
   role's links only. Owners switch gym and create gyms from the same menu.
5. **New pages only where needed.** Front desk Home and Sales (selling
   packages and taking payments from Finance), the Cleaning log, the coach's
   My clients (the Users directory filtered to their clients), Reports for
   accountants (the finance part of Analytics), roles and head-coach controls
   in the user profile, and private coach notes on the client profile.

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
To be completed after approval.
