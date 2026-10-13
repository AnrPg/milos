# ADR-135: One Staff Dashboard for Every Role
Date: 2026-10-13
Status: Accepted
Amends: ADR-103 (staff homes)

## Context

ADR-103 kept the owner/admin dashboard (`AdminDashboard`) but gave coaches,
front desk and accountants a new "Today" page made of collapsible link lists
(`StaffHome` sections). The owner had rejected that list style during the
ADR-103 design ("keep the current UI … only hide/unhide/rename") and asked
for the coach's Home to be "the dashboard, nicely organized and decluttered".
After the merge to main the owner asked for a more stylish, user-friendly
dashboard with a variety of UI elements that still stays minimal, uncluttered
and follows current dashboard UX practice.

## Decision

1. **Every staff role gets the dashboard.** `StaffHome` renders
   `AdminDashboard` for owners, admins, coaches, front desk and accountants.
   A janitor whose capabilities are only cleaning (and inventory reports)
   keeps the cleaning log as Home (ADR-104).
2. **Capabilities trim the dashboard (ADR-099).** `AdminDashboard` takes the
   membership and hides any tile, alert group, header action, card or link it
   cannot open; queries for hidden widgets never run, so no role triggers a
   403. Without a membership prop everything shows.
3. **Role cards sit under the metrics** in a two-column grid: front desk
   action tiles and cleaning status, accountant tiles, and for coaches My
   clients, My appointments, the reply and form-review queues and Members'
   PRs. The separate "Coaching tools" list moved into the link hub.
4. **Varied, calm elements** (`DashboardWidgets.tsx`), following common
   dashboard guidance (few headline KPIs above the fold, hierarchy, progressive
   disclosure, empty states that point to the next step, state never shown by
   color alone):
   - at most four headline KPI rings, then compact stat pills;
   - today's classes as a timeline with a capacity bar and "n booked of m"
     text (a coach who does not run the schedule sees the classes they coach);
   - clients and PR search results as avatar chips; Members' PRs lists nobody
     until the coach searches;
   - front desk and accountant jobs as large icon tiles;
   - cleaning areas as status dots with the status in words;
   - the link hub as grouped icon tiles instead of arrow lists;
   - the Seasonal challenges card for settings managers always, for other
     roles only while a challenge runs.
   Icons are inline SVG; no new dependency.

## Consequences

- One component and one visual language for all staff homes; the role
  differences are data (capabilities), not separate pages.
- The top bar is unchanged (ADR-103): its links still come from capabilities.
- New UI string: `Ui.dashNoClassesToday` in all 12 locales.
- The e2e accessibility spec expects the "Dashboard" heading on `/admin`.
