# Admin Members Table & Referral Wizard — Design Spec
**Date:** 2026-06-13  
**Status:** Approved  
**Scope:** Single-phase implementation

---

## Overview

Four interconnected changes to `/admin/finance/operations?tab=members` and the `ReferralEventWizard`:

| ID | Change | Where |
|----|--------|-------|
| A | Members table: 3 new columns + inline Plan assignment | `MembersTab`, `MemberRow`, backend `ListFinanceMembers` |
| B | Members table: sortable & filterable column headers | `MembersTab` + new `useSortFilter` hook |
| C | Referral wizard: two separate Meilisearch-backed user search fields | `ReferralEventWizard` |
| D | Referral wizard: inline membership setup for referee with no membership | `ReferralEventWizard` |

---

## A. New Columns + Inline Plan Assignment

### Backend change — `ListFinanceMembers`

`build_row/3` currently does not include payment data or membership notes. Extend it with:

- `last_payment_on` — `paid_on` of the most recent `MembershipPayment` for this membership
- `last_payment_amount_cents` — `amount_cents` of the same payment
- `notes` — `membership.notes`

**Implementation approach:** Extend `search_member_summaries` in `EctoFinanceStore` with a LEFT JOIN LATERAL (or Ecto subquery) on `membership_payments` grouped by `membership_id` to get the latest payment in one query. No N+1.

`build_row` maps these into the row map:
```elixir
%{
  ...existing fields...,
  last_payment_on: profile[:last_payment_on],
  last_payment_amount_cents: profile[:last_payment_amount_cents],
  notes: field(membership, :notes)
}
```

### Frontend — column order (11 columns)

| # | Column | Edit behaviour |
|---|--------|---------------|
| 1 | Nickname | button → opens `MemberPanel` (unchanged) |
| 2 | Type | read-only badge |
| 3 | Status | `InlineToggle` (unchanged) |
| 4 | Plan | **new `InlineAssignPackage`** |
| 5 | Expires | `InlineCell` date (unchanged) |
| 6 | Last paid | read-only date |
| 7 | Amount | read-only currency |
| 8 | Credits | read-only currency (unchanged) |
| 9 | Notes | `InlineCell` text — saves via `updateFinanceMember({ notes })` |
| 10 | Referred By | `Combobox` (unchanged) |
| 11 | Referrals | count + "+" button (unchanged) |

### `InlineAssignPackage` component

New component in `apps/web/src/components/admin/finance/shared/InlineAssignPackage.tsx`.

Props:
```ts
{
  userId: string
  currentCode: string | null   // package_code_snapshot of active sub, or null
  packages: FinanceRecord[]    // active packages list (passed down from MembersTab)
  pending: boolean
  onAssign: (packageId: string) => void
}
```

Behaviour:
- **No package:** renders a `+ Assign` pill (accent border, muted text)
- **Has package:** renders the code as a badge; on hover shows a small ✎ affordance
- **Open state:** inline popover directly below the cell containing a `<select>` of active packages and an "Assign" button
- `onAssign` calls `assignFinancePackage(token, userId, { membership_package_id })` in `MembersTab`; on success invalidates `["admin", "finance", "members"]`

Packages list is fetched once in `MembersTab` (existing `referralProgramsQuery` pattern — add a `packagesQuery` alongside it).

---

## B. Sortable & Filterable Column Headers

### `useSortFilter` hook

New file: `apps/web/src/components/admin/finance/hooks/useSortFilter.ts`

```ts
type SortState = { column: ColumnKey | null; direction: 'asc' | 'desc' }
type FilterState = Partial<Record<ColumnKey, FilterValue>>

// returns: { sort, setSort, filters, setFilter, clearFilters, result: FinanceRecord[] }
```

All logic is client-side — members array is already fully loaded. The hook:
1. Applies each active filter in sequence (AND logic)
2. Applies the sort last

### `SortableHeader` component

New file: `apps/web/src/components/admin/finance/shared/SortableHeader.tsx`

Props:
```ts
{
  column: ColumnKey
  label: string
  sort: SortState
  hasFilter: boolean      // true if a filter is active for this column
  onSort: () => void
  filterSlot: ReactNode   // the popover content, rendered by parent
}
```

Behaviour:
- Click on label area → cycle sort (asc → desc → null)
- Sort arrow (↑ / ↓) shown when active
- Filter icon (funnel) always visible on hover; filled/accent when filter is active
- Click filter icon → toggles a popover rendered in `filterSlot`

### Filter popover types per column

| Column | Filter UI | Filter logic |
|--------|-----------|-------------|
| Nickname | text input | case-insensitive substring on `nickname` |
| Type | checkbox: `athlete` / `member` | membership OR |
| Status | checkbox: all 7 statuses | membership OR |
| Plan | checkbox: unique `package_code_snapshot` values | membership OR; "None" option for no package |
| Expires | pills: Expired / Next 30d / No expiry + date range | date comparison |
| Last paid | pills: Never / Last 30d / Last 90d | date comparison on `last_payment_on` |
| Amount | pills: Has payment / No payment | presence check |
| Credits | pills: Has credits / Owes credits | sign check on `credit_balance` |
| Notes | pills: Has notes / Empty | presence check on `notes` |
| Referred By | pills: Has referrer / None | presence check |
| Referrals | pills: Made referrals / None | array length check |

Popovers are positioned absolutely below their header cell. One popover open at a time (clicking another closes the previous). Clicking outside closes.

### Sort comparators

| Column | Sort value |
|--------|-----------|
| Nickname | `nickname` (string, locale-aware) |
| Type | `identity_role` |
| Status | membership status string |
| Plan | `package_code_snapshot` |
| Expires | `expires_on` date |
| Last paid | `last_payment_on` date |
| Amount | `last_payment_amount_cents` number |
| Credits | `credit_balance` number |
| Notes | presence first (has notes before empty), then alphabetical |
| Referred By | presence (has referrer sorts first) |
| Referrals | `referrals_made_user_ids.length` number |

---

## C. Referral Wizard — Two Separate Search Fields

### New `UserSearchField` component

New file: `apps/web/src/components/admin/finance/shared/UserSearchField.tsx`

Props:
```ts
{
  label: string
  value: string                     // selected user id
  prefillUser?: FinanceRecord       // if set, pre-selects without search
  token: string
  onChange: (userId: string, user: FinanceRecord | null) => void
  excludeUserId?: string            // prevent selecting same user as the other field
}
```

Behaviour:
- Text input; typing ≥2 chars triggers `fetchAdminSearch` (150ms debounce) filtered to `["member", "athlete"]`
- Dropdown shows up to 20 results: nickname (bold) + role (sublabel)
- On select: input collapses to a chip showing nickname + role badge + "✕ clear" button
- Clear → resets to empty input, calls `onChange("", null)`
- `excludeUserId`: filters out the user already selected in the other field

### Step 1 UI — new layout

Replace the current single shared search with:

```
[Referral program] <select>

[Referrer]                        ← UserSearchField
[Referee]                         ← UserSearchField
  └─ [Membership warning / inline assign]  ← see section D

[Notes] <textarea>

[Record referral → Step 2]
```

Summary box (showing IDs + membership_id) remains below the fields.

`canProceedStep1`:
```ts
Boolean(form.referral_program_id && form.referrer_user_id && form.referred_user_id && form.membership_id)
```
Unchanged — the inline membership setup (D) unblocks `membership_id`.

### Prefill behaviour

When `prefillReferrerId` prop is passed, the parent (`MembersTab`) looks up the user from the already-loaded `members` array and passes it as `prefillUser: FinanceRecord` to the Referrer `UserSearchField`. The field renders it as a pre-selected chip immediately — no extra API call.

---

## D. Inline Membership Setup in Wizard

### Trigger

`form.referred_user_id` is set AND `form.membership_id` is empty (referee has no membership record).

### UI

Below the Referee `UserSearchField`, when trigger is active:

```
┌─────────────────────────────────────────────────┐
│ ⚠ This user has no membership.                  │
│ [Assign a package to continue →]                │
└─────────────────────────────────────────────────┘
```

Clicking "Assign a package to continue →" expands inline:

```
┌─────────────────────────────────────────────────┐
│ ⚠ This user has no membership.                  │
│                                                 │
│ Package  [select dropdown]                      │
│ [Assign & continue]  [Cancel]                   │
│                                                 │
│ Error message (if any)                          │
└─────────────────────────────────────────────────┘
```

### Flow

1. Admin selects a package from `<select>` (same active packages list used in `InlineAssignPackage`)
2. Clicks "Assign & continue"
3. Calls `assignFinancePackage(token, form.referred_user_id, { membership_package_id })`
4. Response: `{ package_subscription: { membership_id, ... } }`
5. `setForm({ ...form, membership_id: response.package_subscription.membership_id })`
6. Warning collapses; `canProceedStep1` unblocks
7. Invalidates `["admin", "finance", "members"]` so the table reflects the new package

Packages list is fetched once at wizard mount level (add a `packagesQuery` alongside existing `programs` prop, or pass packages as a prop from the parent tab).

---

## Data Flow Summary

```
MembersTab
 ├─ packagesQuery (new)   → passes to MemberRow as prop
 ├─ useSortFilter hook    → derives filteredSortedMembers
 └─ MemberRow
      └─ InlineAssignPackage  (Plan column)
      └─ InlineCell           (Notes column, Expires column)
      └─ SortableHeader       (each <th>)

ReferralEventWizard
 ├─ packagesQuery (new)
 ├─ UserSearchField (Referrer)
 ├─ UserSearchField (Referee)
 │    └─ InlineMembershipSetup  (conditional)
 └─ Step 2 / Step 3 unchanged
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `src/components/admin/finance/shared/InlineAssignPackage.tsx` | Inline package picker for Plan column |
| `src/components/admin/finance/shared/SortableHeader.tsx` | Sortable + filterable `<th>` |
| `src/components/admin/finance/shared/UserSearchField.tsx` | Meilisearch-backed user search with chip |
| `src/components/admin/finance/hooks/useSortFilter.ts` | Sort + filter state + derived array |

## Files to Modify

| File | Change |
|------|--------|
| `apps/api/lib/milos_training/application/list_finance_members.ex` | Add `last_payment_on`, `last_payment_amount_cents`, `notes` to `build_row` |
| `apps/api/lib/milos_training/infrastructure/finance/ecto_finance_store.ex` | Extend `search_member_summaries` with last-payment subquery |
| `src/components/admin/finance/tabs/MembersTab.tsx` | Wire `useSortFilter`, `SortableHeader`, `packagesQuery`, new columns |
| `src/components/admin/finance/ReferralEventWizard.tsx` | Replace shared search with two `UserSearchField`s + inline membership setup |

## Files NOT changed

- `SidePanel`, `InlineCell`, `InlineToggle`, `Combobox` — reused as-is
- `MemberPanel` — unchanged; assign-package inside it stays for the detail view
- `ReferralsTab` — unchanged
- All backend routes, controllers, OpenAPI schemas — the list endpoint response shape gains 3 new fields (additive, non-breaking)

---

## Constraints & Notes

- All sorting and filtering is client-side; no new API endpoints needed
- `last_payment_on` / `last_payment_amount_cents`: the most recent payment is selected by `inserted_at DESC` (record-creation order, immune to admin back-dating). The displayed date is `paid_on` (the human-readable payment date), but the row selected is the latest by insertion.
- Notes inline edit calls the existing `updateFinanceMember` endpoint — no new backend route
- The `InlineAssignPackage` popover and filter popovers must close on outside-click and on Escape key
- Only one filter popover open at a time
- The wizard's `packages` list is fetched at the parent tab level and passed as a prop to avoid duplicate queries when both `MembersTab` and `ReferralEventWizard` are mounted simultaneously
