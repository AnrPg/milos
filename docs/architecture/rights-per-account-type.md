# Rights per Account Type

Status: Accepted (2026-10-12) — source of truth for ADR-099 to ADR-104.
Owner of changes: product. Code reads this through
`Organizations.Domain.AccessPolicy` (capabilities) and
`Organizations.Domain.CoachScope` (data scope).

## 1. Account types

| Type | Where it lives | Scope | Who grants it |
|---|---|---|---|
| **Vendor** | `vendors` | The whole platform (us, the SaaS provider) | Mix task only |
| **Owner** | membership role | Every gym the person owns; may own many | Created with the gym, or granted by another owner of that gym |
| **Admin** | membership role | One gym — the gym's boss, not a platform admin | An owner of that gym |
| **Coach** | membership role | One gym; own clients and classes unless *head coach* | Owner or admin |
| **Front desk** | membership role | One gym; reception work | Owner or admin |
| **Accountant** | membership role | One gym; money only | Owner or admin |
| **Janitor** | membership role | One gym; cleaning log, reports inventory problems | Owner or admin |
| **Member** | membership role | One gym; trains in classes, buys packages | Self sign-up, invitation |
| **Athlete** | membership role | One gym; individually programmed (remote) | Owner, admin, or a coach |

A person has one account and, in each gym, **one membership that holds a set
of roles** (ADR-099). Roles in different gyms are independent. Examples: a
coach who also trains as a member; an owner who coaches; a front-desk employee
who is also an athlete.

Rights are the **union** of the membership's roles. A right granted without a
scope (all data) beats the same right granted with a scope (own data).

## 2. Data scopes

| Scope | Meaning |
|---|---|
| **all** | Every client, class and record of the gym |
| **own** | Coach: clients they have a coaching relationship with, classes they coach, their appointment slots, their notes. Client: their own records |
| **status** | Only a client's membership status (active / frozen / expired, package name, sessions left) — no amounts, invoices or payments |

A coach has scope **own** by default. An owner or admin can switch a coach to
**head coach** (`coach_scope = all`), which gives the coaching rights with scope
**all**. It changes nothing outside coaching.

## 3. Capability matrix

Legend: ✔ full · 👁 read · **own** / **status** = scoped (see §2) · — none.
Owner has every right of an admin.

### Organization and people

| Capability | Owner | Admin | Coach | Front desk | Accountant | Janitor | Member / Athlete |
|---|---|---|---|---|---|---|---|
| Create another gym | ✔ | — | — | — | — | — | — |
| Archive gym (typing its slug), transfer ownership (stays admin) | ✔ | — | — | — | — | — | — |
| Platform subscription (pay us) | ✔ | — | — | — | — | — | — |
| Grant or remove owner / admin | ✔ | — | — | — | — | — | — |
| Grant or remove staff roles (coach, front desk, accountant, janitor) | ✔ | ✔ | — | — | — | — | — |
| Set a coach as head coach | ✔ | ✔ | — | — | — | — | — |
| Suspend or remove a person | ✔ | ✔ | — | — | — | — | — |
| Invite clients (member / athlete) | ✔ | ✔ | ✔ (become their coach) | ✔ | — | — | — |
| Gym settings, modules, branding, locations, class types | ✔ | ✔ | — | — | — | — | — |
| People directory | ✔ | ✔ | own | ✔ contact + status | billing contacts | — | — |
| Client profile: training, PRs, history | ✔ | ✔ | own | — | — | — | own |
| Health and injuries | ✔ | ✔ | own (safety) | — | — | — | own |
| Reviews and feedback from clients | ✔ | ✔ | about them | — | — | — | own |

### Money

| Capability | Owner | Admin | Coach | Front desk | Accountant | Janitor | Member / Athlete |
|---|---|---|---|---|---|---|---|
| Packages: create, edit, retire | ✔ | ✔ | — | — | ✔ | — | — |
| Package catalog (what is for sale) | ✔ | ✔ | 👁 | 👁 | ✔ | — | 👁 offered |
| Membership status of a client | ✔ | ✔ | status (own) | status | ✔ | — | own |
| Sell a package, record a payment at the desk | ✔ | ✔ | — | ✔ | ✔ | — | — |
| Invoices, credits, reversals, refunds | ✔ | ✔ | — | — | ✔ | — | own invoices |
| Corporate clients and invoices | ✔ | ✔ | — | — | ✔ | — | — |
| Promotions and referrals | ✔ | ✔ | — | — | 👁 | — | redeem |
| Finance reports and exports | ✔ | ✔ | — | — | ✔ | — | — |
| Finance settings | ✔ | ✔ | — | — | ✔ | — | — |

### Training and coaching

| Capability | Owner | Admin | Coach | Front desk | Accountant | Janitor | Member / Athlete |
|---|---|---|---|---|---|---|---|
| Class schedule: create and edit any class | ✔ | ✔ | — | — | — | — | — |
| Run a class: roster, approve bookings, attendance | ✔ | ✔ | own classes | ✔ | — | — | book own |
| Check-in desk | ✔ | ✔ | own classes | ✔ | — | — | self check-in |
| Workout library: create, edit, **publish directly** | ✔ | ✔ | ✔ | — | — | — | — (own vault) |
| Assign a coach to a class or a client | ✔ | ✔ | self-assign athletes ¹ | — | — | — | — |
| Programming (assigned workouts) | ✔ | ✔ | own | — | — | — | own |
| Form reviews, reply queue, nutrition plans | ✔ | ✔ | own | — | — | — | own |
| PT appointments: slots, rosters | ✔ | ✔ | own slots | book for a client | — | — | book own |
| Private coach notes | ✔ read all ² | read if allowed ² | own | — | — | — | — |
| On-demand videos | ✔ | ✔ | ✔ | — | — | — | watch (package) |
| Challenges | ✔ | ✔ | ✔ | — | — | — | join |
| Messaging | ✔ | ✔ | own clients | ✔ | — | — | ✔ |
| Broadcast to all clients | ✔ | ✔ | own clients | — | — | — | — |

¹ A coach may take an **athlete** (never a member) as their own client; owners
and admins are notified (`coach_client_assigned`) for transparency.

² Owners always read coaches' private notes. Admins read them only while the
coach's setting *Let admins read my notes* is on (default on). Every read by an
admin is logged and the coach is notified with who read which note and when
(ADR-101).

### Analytics and operations

| Capability | Owner | Admin | Coach | Front desk | Accountant | Janitor | Member / Athlete |
|---|---|---|---|---|---|---|---|
| Business analytics and marketing | ✔ | ✔ | — | — | finance only | — | — |
| Coaching analytics | ✔ | ✔ | own | — | — | — | own progress |
| Cleaning log: record cleaning | ✔ | ✔ | — | — | — | ✔ | — |
| Cleaning log: review, set areas and tasks | ✔ | ✔ | — | 👁 | — | own entries | — |
| Inventory: add and edit items, prices, shops; restock, use, recount; service, repair, retire; inventory report (`manage_inventory`) | ✔ | ✔ | — | ✔ | — | — | — |
| Inventory: see machines and consumables without prices or shops; log notes, issues, outages; report running low (`report_inventory`) ³ | ✔ | ✔ | ✔ | ✔ | — | ✔ | — |
| Community: answer group proposals, handle reports, let people into open clubs (`moderate_community`) ⁴ | ✔ | ✔ | ✔ | — | — | — | — |
| Community: the group rule; create, edit and archive open clubs (`manage_community`) | ✔ | ✔ | — | — | — | — | — |
| Events: create, edit and cancel club events; attendees, «Πλήρωσε», free a place, message everyone going, the trial offer (`manage_events`) ⁵ | ✔ | ✔ | ✔ | — | — | — | — |

³ Reporters do not see purchase or unit prices, shops, links, service
contacts or serial numbers, and cannot log repair calls, services, repairs
or retirements. Inventory alerts and the daily digest go to everyone with
`manage_inventory` (ADR-104).

⁴ Staff of the club (owner, admin, coach) also hide, delete and pin posts
in it; a member group's admins do the same inside their group (ADR-143).

⁵ The door of an event is open to the desk too: «Ήρθε» needs `manage_events`
or `check_in`, «Πλήρωσε» `manage_events` or `take_payments`, and reading
the attendee list any of the three (ADR-153).

## 4. Rules that are easy to get wrong

1. **Admins are bosses of one gym**, not platform admins. Only owners act
   across gyms (create, delete, transfer, pay the platform) and only owners
   grant owner or admin.
2. Nobody grants a role above their own; a coach never grants roles. A coach
   inviting a client chooses only *member* or *athlete*, and becomes that
   client's coach when the invitation is redeemed.
3. Coaches never see money beyond **status**; front desk sees status and can
   take payments, but not invoices, reports or settings.
4. Accountants see money and billing contacts, never training or health data.
5. Janitors see only the cleaning log and the inventory lists they report
   on (without prices).
6. Data scope applies on the server: lists, details and actions of a scoped
   coach are filtered by `CoachScope`, not only hidden in the UI.
7. Multi-role accounts get the **union** of rights; the UI groups them by
   *workspace* instead of showing every surface at once (ADR-103).

## 5. Changing this document

Edit this file and the matrix in `AccessPolicy` together, with an ADR when a
role gains or loses a right. `AccessPolicyTest` asserts this matrix.
