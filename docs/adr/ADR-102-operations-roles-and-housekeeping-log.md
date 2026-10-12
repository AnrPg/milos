# ADR-102: Front Desk, Accountant and Janitor Roles; Housekeeping Log
Date: 2026-10-12
Status: Accepted

## Context
Gyms employ reception staff, an accountant and cleaning staff. Giving them
admin rights exposes far more than they need. Cleaning also needs a record of
what was cleaned and when.

## Decision
- **Front desk**: check-in desk, class rosters and bookings for all classes,
  inviting clients, selling packages and recording payments at the desk,
  membership status and contact details, messaging, booking appointments for
  clients, reading the cleaning log. No invoices, reports, settings, health or
  training data.
- **Accountant**: everything money (packages, invoices, payments, credits,
  corporate clients, reports, exports, finance settings) and billing contacts.
  No training, health or coaching data.
- **Janitor**: the housekeeping log only.
- **Housekeeping** (new bounded context): owners and admins define cleaning
  **areas** (name, optional location) with a checklist of **tasks**. A janitor
  records a **cleaning entry**: area, tasks done, started and finished times,
  optional note. Owners, admins and front desk review the log (by day, area
  and person); janitors see their own entries.

## Rationale
Narrow roles let gyms give staff accounts safely; a structured log (areas and
tasks) is searchable and reportable, unlike free text.

## Alternatives Considered
- A generic "custom role" builder: rejected for now; the three roles cover
  the requested cases and keep the UI explainable.
- Logging cleaning as chat messages: rejected; not reportable.

## Consequences
New tables `housekeeping_areas` and `housekeeping_entries` with RLS; role
values added to memberships and invitations; capability rows in
`AccessPolicy`.

## Implementation Notes
To be completed with the implementation.
