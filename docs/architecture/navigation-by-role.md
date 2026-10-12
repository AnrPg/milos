# Navigation by Role (proposal for ADR-103)

Status: Proposed — awaiting product approval.

Rule of this proposal: **today's UI stays as it is.** Changes are only
showing/hiding pages, tabs and buttons, renaming a few labels, and adding
sections or pages where something new is needed. The bar fits a narrow phone
in every language with priority+ overflow (links in priority order; what does
not fit goes into the last menu).

## 1. One role

| Role | Bar (priority order) | Home (dashboard) sections | Hidden / renamed |
|---|---|---|---|
| **Owner** | as today's admin bar | as today's admin dashboard | + Settings › *Organization* card (create gym, transfer ownership, delete gym, platform subscription), + Settings › *Role access* (front desk finance access, §3) |
| **Admin** | as today | as today | Settings › *Organization* hidden |
| **Coach** | Home · Classes · Personals · WOD vault | My classes today (roster, approvals) · My clients (today's Users page as a tab, only their clients; *Take an athlete*, *Invite*) · Form reviews · Replies due · Nutrition plans · Appointments (their slots) · Reports (coaching analytics of their clients) · Content & challenges (links) | *Personal Coaching* → **Personals**, *Workouts* → **WOD vault**; Users, Finance, Analytics & Marketing, Settings hidden; Classes without *Add class* |
| **Front desk** | Home · Check-in · Classes · Clients · Finance | Arrivals now · Today's classes and waitlists · Quick actions (new client, sell package, take payment) · Cleaning status | *Users* → **Clients** (contact and membership status; training and health tabs hidden); Finance shows only the tabs and buttons the gym unlocked (§3); Classes without *Add class* |
| **Accountant** | Home · Finance · Clients · Reports | Overdue · Corporate balances · Desk payments to reconcile | *Users* → **Clients** (billing tab only); *Analytics* → **Reports** (finance tab only) |
| **Janitor** | Cleaning log | — (the log is the home) | everything else hidden |
| **Member** | as today | as today | — |
| **Athlete** | as today | as today | — |

## 2. Several roles in one gym

Principles: owner ⊇ admin ⊇ every staff role; staff pages merge by **union**
(deduplicated, in priority order); a client role adds **My training** (the
client's own pages) instead of merging client links into a staff bar, because
names clash (Classes vs Schedule) and the bar would overflow. Home shows the
sections of every role, staff sections first.

| Combination | Bar | Home | My training (account menu) |
|---|---|---|---|
| Owner + admin | owner | owner | — |
| Owner/admin + coach | admin bar; *Personal Coaching* keeps its name | admin dashboard + **My clients** section | — |
| Owner/admin + front desk / accountant / janitor | admin bar (already includes them) + Cleaning log under More for janitor | admin dashboard | — |
| Owner/admin + member/athlete | admin bar | admin dashboard | ✔ |
| Coach + front desk | Home · Classes · Personals · Check-in · Clients · WOD vault · Finance* | coach sections + arrivals + quick actions | — |
| Coach + accountant | coach bar + Finance · Reports | coach sections + money sections | — |
| Coach + janitor | coach bar + Cleaning log | coach sections | — |
| Coach + member/athlete | coach bar | coach sections | ✔ |
| Front desk + accountant | Home · Check-in · Classes · Clients · Finance (all tabs) · Reports | desk sections + money sections | — |
| Front desk + janitor | desk bar + Cleaning log | desk sections + cleaning | — |
| Front desk + member/athlete | desk bar | desk sections | ✔ |
| Accountant + janitor | accountant bar + Cleaning log | money sections | — |
| Accountant + member/athlete | accountant bar | money sections | ✔ |
| Janitor + member/athlete | client bar + Cleaning log | client home | — (client bar already) |
| Member + athlete | Home · Schedule · My Workouts · History · Pantheon | client home with both | — |
| Three or more roles | union of the staff bars (priority+ overflow into More) | all staff sections | ✔ if a client role is held |

\* only the unlocked tabs (§3).

**My training** is one entry in the account menu that switches the bar to the
client bar (and back with *Staff view*), like switching gym today.

## 3. Front desk finance access (set per gym)

Owners and admins choose, in Settings › *Role access*, what front desk may do
in Finance. Always on: membership status, selling packages, taking payments.
Optional (off by default):

| Toggle | Unlocks |
|---|---|
| Invoices and memberships | invoices, credits, reversals, freezes, allowance grants (`manage_billing`) |
| Campaigns and referrals | promotions, codes, referral programs and rewards (`manage_promotions`) |
| Packages | create and edit packages (`manage_packages`) |
| Finance reports | summary, queues, finance analytics (`view_finance_reports`) |

The toggles add capabilities to the front desk role in that gym only
(ADR-099 extension).
