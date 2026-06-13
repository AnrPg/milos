# Admin Members Table & Referral Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Members table with 3 new columns, inline Plan assignment, sortable/filterable headers, and redesign the ReferralEventWizard with two separate Meilisearch-backed user search fields plus inline membership setup.

**Architecture:** Backend extends `member_search_summaries` with a single DISTINCT ON batch query for last-payment data; frontend adds four new shared components (`InlineAssignPackage`, `SortableHeader`, `UserSearchField`, `useSortFilter`) that wire into the existing `MembersTab` and `ReferralEventWizard`.

**Tech Stack:** Elixir/Ecto (PostgreSQL DISTINCT ON), Next.js 15, React, TanStack Query, Tailwind CSS, existing `fetchAdminSearch` (Meilisearch-backed).

---

## File Map

**Create:**
- `apps/web/src/components/admin/finance/shared/InlineAssignPackage.tsx`
- `apps/web/src/components/admin/finance/shared/SortableHeader.tsx`
- `apps/web/src/components/admin/finance/shared/UserSearchField.tsx`
- `apps/web/src/components/admin/finance/hooks/useSortFilter.ts`

**Modify:**
- `apps/api/lib/milos_training/infrastructure/finance/ecto_finance_store.ex` — extend `member_search_summaries/1`
- `apps/api/lib/milos_training/application/list_finance_members.ex` — expose new fields in `build_row/3`
- `apps/web/src/components/admin/finance/tabs/MembersTab.tsx` — new columns, InlineAssignPackage, useSortFilter, SortableHeader
- `apps/web/src/components/admin/finance/ReferralEventWizard.tsx` — two UserSearchFields, inline membership setup

**Unchanged:** `SidePanel`, `InlineCell`, `InlineToggle`, `Combobox`, `MemberPanel`, `ReferralsTab`, all API routes.

---

## Task 1: Backend — extend `member_search_summaries` with last-payment data

**Files:**
- Modify: `apps/api/lib/milos_training/infrastructure/finance/ecto_finance_store.ex` (around line 1487)
- Test: `apps/api/test/milos_training/finance/finance_test.exs`

- [ ] **Step 1: Write the failing test**

Add at the end of `apps/api/test/milos_training/finance/finance_test.exs`:

```elixir
test "search_member_summaries includes last_payment_on and last_payment_amount_cents" do
  user = TestFixtures.user_fixture(%{role: :member})

  {:ok, membership} =
    Finance.upsert_membership(user.id, %{
      user_type_snapshot: "member",
      status: "active",
      signup_source: "admin_created"
    })

  {:ok, _payment} =
    Finance.record_payment(membership.id, %{
      amount_cents: 8000,
      paid_on: ~D[2026-01-15],
      payment_method: "cash",
      payment_status: "paid"
    })

  summaries = Finance.search_member_summaries(%{user_ids: [user.id], limit: 10})
  profile = Map.get(summaries, user.id)

  assert profile.last_payment_on == ~D[2026-01-15]
  assert profile.last_payment_amount_cents == 8000
end

test "search_member_summaries returns nil last_payment fields when no payments exist" do
  user = TestFixtures.user_fixture(%{role: :member})

  Finance.upsert_membership(user.id, %{
    user_type_snapshot: "member",
    status: "active",
    signup_source: "admin_created"
  })

  summaries = Finance.search_member_summaries(%{user_ids: [user.id], limit: 10})
  profile = Map.get(summaries, user.id)

  assert is_nil(profile.last_payment_on)
  assert is_nil(profile.last_payment_amount_cents)
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/api
mix test test/milos_training/finance/finance_test.exs --seed 0 2>&1 | tail -20
```

Expected: test fails with `KeyError` or `undefined field`.

- [ ] **Step 3: Extend `member_search_summaries/1` in `ecto_finance_store.ex`**

Find the `defp member_search_summaries(memberships) do` function (around line 1489). Replace the entire function body:

```elixir
defp member_search_summaries(memberships) do
  membership_ids = Enum.map(memberships, & &1.id)

  subscriptions_by_membership_id =
    MembershipPackageSubscription
    |> where([subscription], subscription.membership_id in ^membership_ids)
    |> order_by([subscription], desc: subscription.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.membership_id, &normalize_subscription/1)

  last_payments_by_membership_id =
    from(p in MembershipPayment,
      where: p.membership_id in ^membership_ids,
      distinct: p.membership_id,
      order_by: [asc: p.membership_id, desc: p.inserted_at],
      select: %{membership_id: p.membership_id, paid_on: p.paid_on, amount_cents: p.amount_cents}
    )
    |> Repo.all()
    |> Map.new(&{&1.membership_id, &1})

  Map.new(memberships, fn membership ->
    subscriptions = Map.get(subscriptions_by_membership_id, membership.id, [])
    last_payment = Map.get(last_payments_by_membership_id, membership.id)

    {membership.user_id,
     %{
       membership: normalize_membership(membership),
       package_subscriptions: subscriptions,
       active_package_subscription:
         Enum.find(
           subscriptions,
           &(&1.status in InvoiceLifecycle.active_subscription_statuses())
         ),
       last_payment_on: last_payment && last_payment.paid_on,
       last_payment_amount_cents: last_payment && last_payment.amount_cents
     }}
  end)
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/milos_training/finance/finance_test.exs --seed 0 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/api
git add lib/milos_training/infrastructure/finance/ecto_finance_store.ex test/milos_training/finance/finance_test.exs
git commit -m "feat(finance): add last_payment_on and last_payment_amount_cents to member_search_summaries"
```

---

## Task 2: Backend — expose new fields in `build_row`

**Files:**
- Modify: `apps/api/lib/milos_training/application/list_finance_members.ex`

- [ ] **Step 1: Replace `build_row/3` in `list_finance_members.ex`**

The current `build_row` (lines 31–48) returns 6 fields. Replace it with:

```elixir
defp build_row(user, finance_summaries, referrals_made) do
  profile = Map.get(finance_summaries, user.id)
  membership = if profile, do: profile.membership, else: nil
  active_sub = if profile, do: profile.active_package_subscription, else: nil

  made =
    referrals_made
    |> Map.get(user.id, [])
    |> Enum.map(& &1.referred_user_id)

  %{
    id: user.id,
    nickname: user.nickname,
    identity_role: to_string(user.role),
    membership: membership,
    active_package_subscription: active_sub,
    referrals_made_user_ids: made,
    last_payment_on: profile && Map.get(profile, :last_payment_on),
    last_payment_amount_cents: profile && Map.get(profile, :last_payment_amount_cents),
    notes: membership && Map.get(membership, :notes)
  }
end
```

- [ ] **Step 2: Run full test suite**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/api
mix test 2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/milos_training/application/list_finance_members.ex
git commit -m "feat(finance): expose last_payment_on, last_payment_amount_cents, notes in member list rows"
```

---

## Task 3: Frontend — `InlineAssignPackage` component

**Files:**
- Create: `apps/web/src/components/admin/finance/shared/InlineAssignPackage.tsx`

- [ ] **Step 1: Create the file**

```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import type { FinanceRecord } from "@/api/finance";

type Props = {
  currentCode: string | null;
  packages: FinanceRecord[];
  pending: boolean;
  onAssign: (packageId: string) => void;
};

function field(r: FinanceRecord | null | undefined, k: string, fb = "") {
  const v = r?.[k];
  return v == null ? fb : String(v);
}

export function InlineAssignPackage({ currentCode, packages, pending, onAssign }: Props) {
  const [open, setOpen] = useState(false);
  const [selectedId, setSelectedId] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onDown(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const activePackages = packages.filter((p) => p.active !== false);

  function handleAssign() {
    if (!selectedId) return;
    onAssign(selectedId);
    setOpen(false);
    setSelectedId("");
  }

  return (
    <div className="relative" ref={ref}>
      {currentCode ? (
        <button
          className="group flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold"
          style={{ background: "#1a1a28", color: "#c0c0d8" }}
          onClick={() => setOpen((v) => !v)}
          type="button"
          disabled={pending}
        >
          {currentCode}
          <span className="opacity-0 group-hover:opacity-60 transition-opacity text-[10px]">✎</span>
        </button>
      ) : (
        <button
          className="rounded-full px-3 py-1 text-xs font-semibold"
          style={{
            background: "rgba(217,93,57,0.08)",
            border: "1px solid rgba(217,93,57,0.2)",
            color: "#d95d39",
          }}
          onClick={() => setOpen((v) => !v)}
          type="button"
          disabled={pending}
        >
          + Assign
        </button>
      )}

      {open && (
        <div
          className="absolute left-0 top-full z-40 mt-1 min-w-[180px] rounded-[1rem] p-3 shadow-xl space-y-2"
          style={{ background: "#111118", border: "1px solid #1a1a28" }}
        >
          <select
            className="w-full rounded-[0.8rem] px-2 py-1.5 text-xs outline-none"
            style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
            value={selectedId}
            onChange={(e) => setSelectedId(e.target.value)}
            autoFocus
          >
            <option value="">Select package…</option>
            {activePackages.map((p) => (
              <option key={field(p, "id")} value={field(p, "id")}>
                {field(p, "name", field(p, "code"))}
              </option>
            ))}
          </select>
          <button
            className="w-full rounded-full py-1.5 text-xs font-semibold disabled:opacity-40"
            style={{ background: "#F0EDF8", color: "#0A0A0F" }}
            disabled={!selectedId || pending}
            onClick={handleAssign}
            type="button"
          >
            {pending ? "Assigning…" : "Assign"}
          </button>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | grep InlineAssignPackage
```

Expected: no errors for this file.

- [ ] **Step 3: Commit**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
git add src/components/admin/finance/shared/InlineAssignPackage.tsx
git commit -m "feat(web/finance): InlineAssignPackage component for Plan column inline assignment"
```

---

## Task 4: Frontend — `useSortFilter` hook

**Files:**
- Create: `apps/web/src/components/admin/finance/hooks/useSortFilter.ts`

- [ ] **Step 1: Create the hooks directory and file**

```bash
mkdir -p /home/rodochrousbisbiki/MyApps/milos/apps/web/src/components/admin/finance/hooks
```

Create `apps/web/src/components/admin/finance/hooks/useSortFilter.ts`:

```ts
import { useMemo, useState } from "react";
import type { FinanceRecord } from "@/api/finance";

export type ColumnKey =
  | "nickname" | "type" | "status" | "plan" | "expires"
  | "last_paid" | "amount" | "credits" | "notes" | "referred_by" | "referrals";

export type SortState = { column: ColumnKey | null; direction: "asc" | "desc" };

export type FilterValue =
  | { type: "text"; value: string }
  | { type: "multi"; values: string[] }
  | { type: "presence"; value: "has" | "none" }
  | { type: "date_preset"; value: "expired" | "next30d" | "no_expiry" | "never" | "last30d" | "last90d" }
  | { type: "sign"; value: "positive" | "negative" };

type FilterState = Partial<Record<ColumnKey, FilterValue>>;

function field(r: FinanceRecord | null | undefined, k: string, fb = "") {
  const v = r?.[k];
  return v == null ? fb : String(v);
}

function applyFilter(members: FinanceRecord[], column: ColumnKey, filter: FilterValue): FinanceRecord[] {
  const now = new Date();
  const ago30 = new Date(now); ago30.setDate(now.getDate() - 30);
  const ago90 = new Date(now); ago90.setDate(now.getDate() - 90);
  const ahead30 = new Date(now); ahead30.setDate(now.getDate() + 30);

  return members.filter((m) => {
    const membership = m.membership as FinanceRecord | null | undefined;
    const activeSub = m.active_package_subscription as FinanceRecord | null | undefined;

    switch (column) {
      case "nickname":
        if (filter.type !== "text") return true;
        return field(m, "nickname").toLowerCase().includes(filter.value.toLowerCase());

      case "type":
        if (filter.type !== "multi" || filter.values.length === 0) return true;
        return filter.values.includes(field(m, "identity_role"));

      case "status":
        if (filter.type !== "multi" || filter.values.length === 0) return true;
        return filter.values.includes(field(membership, "status"));

      case "plan":
        if (filter.type !== "multi" || filter.values.length === 0) return true;
        return filter.values.includes(field(activeSub, "package_code_snapshot") || "none");

      case "expires": {
        if (filter.type !== "date_preset") return true;
        const expiresOn = field(activeSub, "ends_on") || field(membership, "expires_on");
        const exp = expiresOn ? new Date(expiresOn) : null;
        if (filter.value === "no_expiry") return !exp;
        if (filter.value === "expired") return exp ? exp < now : false;
        if (filter.value === "next30d") return exp ? exp >= now && exp <= ahead30 : false;
        return true;
      }

      case "last_paid": {
        if (filter.type !== "date_preset") return true;
        const lp = typeof m.last_payment_on === "string" ? new Date(m.last_payment_on) : null;
        if (filter.value === "never") return !lp;
        if (filter.value === "last30d") return lp ? lp >= ago30 : false;
        if (filter.value === "last90d") return lp ? lp >= ago90 : false;
        return true;
      }

      case "amount":
        if (filter.type !== "presence") return true;
        return filter.value === "has" ? m.last_payment_on != null : m.last_payment_on == null;

      case "credits": {
        if (filter.type !== "sign") return true;
        const bal = typeof m.credit_balance === "number" ? m.credit_balance : 0;
        return filter.value === "positive" ? bal > 0 : bal < 0;
      }

      case "notes":
        if (filter.type !== "presence") return true;
        return filter.value === "has" ? Boolean(m.notes) : !m.notes;

      case "referred_by":
        if (filter.type !== "presence") return true;
        return filter.value === "has"
          ? Boolean(field(membership, "referred_by_user_id"))
          : !field(membership, "referred_by_user_id");

      case "referrals": {
        if (filter.type !== "presence") return true;
        const made = (m.referrals_made_user_ids as string[]) ?? [];
        return filter.value === "has" ? made.length > 0 : made.length === 0;
      }

      default: return true;
    }
  });
}

function cmp(a: FinanceRecord, b: FinanceRecord, column: ColumnKey, direction: "asc" | "desc"): number {
  const dir = direction === "asc" ? 1 : -1;
  const aM = a.membership as FinanceRecord | null | undefined;
  const bM = b.membership as FinanceRecord | null | undefined;
  const aS = a.active_package_subscription as FinanceRecord | null | undefined;
  const bS = b.active_package_subscription as FinanceRecord | null | undefined;

  switch (column) {
    case "nickname": return dir * field(a, "nickname").localeCompare(field(b, "nickname"));
    case "type": return dir * field(a, "identity_role").localeCompare(field(b, "identity_role"));
    case "status": return dir * field(aM, "status").localeCompare(field(bM, "status"));
    case "plan": return dir * field(aS, "package_code_snapshot").localeCompare(field(bS, "package_code_snapshot"));
    case "expires": {
      const aE = field(aS, "ends_on") || field(aM, "expires_on");
      const bE = field(bS, "ends_on") || field(bM, "expires_on");
      if (!aE && !bE) return 0;
      if (!aE) return dir;
      if (!bE) return -dir;
      return dir * aE.localeCompare(bE);
    }
    case "last_paid": {
      const aD = typeof a.last_payment_on === "string" ? a.last_payment_on : "";
      const bD = typeof b.last_payment_on === "string" ? b.last_payment_on : "";
      if (!aD && !bD) return 0;
      if (!aD) return dir;
      if (!bD) return -dir;
      return dir * aD.localeCompare(bD);
    }
    case "amount": {
      const aA = typeof a.last_payment_amount_cents === "number" ? a.last_payment_amount_cents : 0;
      const bA = typeof b.last_payment_amount_cents === "number" ? b.last_payment_amount_cents : 0;
      return dir * (aA - bA);
    }
    case "credits": {
      const aB = typeof a.credit_balance === "number" ? a.credit_balance : 0;
      const bB = typeof b.credit_balance === "number" ? b.credit_balance : 0;
      return dir * (aB - bB);
    }
    case "notes": {
      const aN = field(aM, "notes");
      const bN = field(bM, "notes");
      if (Boolean(aN) !== Boolean(bN)) return Boolean(aN) ? -1 : 1;
      return dir * aN.localeCompare(bN);
    }
    case "referred_by": {
      const aR = Boolean(field(aM, "referred_by_user_id"));
      const bR = Boolean(field(bM, "referred_by_user_id"));
      return aR === bR ? 0 : aR ? -dir : dir;
    }
    case "referrals": {
      const aC = ((a.referrals_made_user_ids as string[]) ?? []).length;
      const bC = ((b.referrals_made_user_ids as string[]) ?? []).length;
      return dir * (aC - bC);
    }
    default: return 0;
  }
}

export function useSortFilter(members: FinanceRecord[]) {
  const [sort, setSort] = useState<SortState>({ column: null, direction: "asc" });
  const [filters, setFilters] = useState<FilterState>({});

  function cycleSort(column: ColumnKey) {
    setSort((prev) => {
      if (prev.column !== column) return { column, direction: "asc" };
      if (prev.direction === "asc") return { column, direction: "desc" };
      return { column: null, direction: "asc" };
    });
  }

  function setFilter(column: ColumnKey, value: FilterValue | undefined) {
    setFilters((prev) => {
      if (value === undefined) {
        const next = { ...prev };
        delete next[column];
        return next;
      }
      return { ...prev, [column]: value };
    });
  }

  function clearFilters() { setFilters({}); }

  const result = useMemo(() => {
    let out = [...members];
    for (const [col, f] of Object.entries(filters) as [ColumnKey, FilterValue][]) {
      out = applyFilter(out, col, f);
    }
    if (sort.column) {
      out = [...out].sort((a, b) => cmp(a, b, sort.column!, sort.direction));
    }
    return out;
  }, [members, filters, sort]);

  return { sort, cycleSort, filters, setFilter, clearFilters, result };
}
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | grep useSortFilter
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/components/admin/finance/hooks/useSortFilter.ts
git commit -m "feat(web/finance): useSortFilter hook — client-side sort and filter for members table"
```

---

## Task 5: Frontend — `SortableHeader` component

**Files:**
- Create: `apps/web/src/components/admin/finance/shared/SortableHeader.tsx`

- [ ] **Step 1: Create the file**

```tsx
"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import type { ColumnKey, SortState } from "@/components/admin/finance/hooks/useSortFilter";

type Props = {
  column: ColumnKey;
  label: string;
  sort: SortState;
  hasFilter: boolean;
  onSort: () => void;
  filterSlot: ReactNode;
};

export function SortableHeader({ column, label, sort, hasFilter, onSort, filterSlot }: Props) {
  const [filterOpen, setFilterOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!filterOpen) return;
    function onDown(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setFilterOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setFilterOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [filterOpen]);

  const isActive = sort.column === column;
  const arrow = isActive ? (sort.direction === "asc" ? " ↑" : " ↓") : "";

  return (
    <div className="group relative flex items-center gap-1" ref={ref}>
      <button
        className="text-left text-xs font-semibold uppercase tracking-[0.18em] hover:opacity-80 transition-opacity whitespace-nowrap"
        style={{ color: isActive ? "#d95d39" : "#55556a" }}
        onClick={onSort}
        type="button"
      >
        {label}{arrow}
      </button>

      <button
        className={`rounded p-0.5 transition-opacity ${hasFilter ? "opacity-100" : "opacity-0 group-hover:opacity-60"}`}
        style={{ color: hasFilter ? "#d95d39" : "#55556a" }}
        onClick={() => setFilterOpen((v) => !v)}
        type="button"
        title={`Filter ${label}`}
      >
        <svg width="9" height="9" viewBox="0 0 9 9" fill="currentColor">
          <path d="M0 1h9L5.5 5.5V8.5l-2-1V5.5L0 1z" />
        </svg>
      </button>

      {filterOpen && (
        <div
          className="absolute left-0 top-full z-50 mt-1 min-w-[170px] rounded-[1rem] p-3 shadow-xl"
          style={{ background: "#111118", border: "1px solid #1a1a28" }}
        >
          {filterSlot}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | grep SortableHeader
```

- [ ] **Step 3: Commit**

```bash
git add src/components/admin/finance/shared/SortableHeader.tsx
git commit -m "feat(web/finance): SortableHeader component with sort cycle and filter popover slot"
```

---

## Task 6: Frontend — `UserSearchField` component

**Files:**
- Create: `apps/web/src/components/admin/finance/shared/UserSearchField.tsx`

- [ ] **Step 1: Create the file**

```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import { fetchAdminSearch, type FinanceRecord } from "@/api/finance";

type Props = {
  label: string;
  value: string;
  prefillUser?: FinanceRecord | null;
  token: string;
  onChange: (userId: string, user: FinanceRecord | null) => void;
  excludeUserId?: string;
};

function field(r: FinanceRecord | null | undefined, k: string, fb = "") {
  const v = r?.[k];
  return v == null ? fb : String(v);
}

export function UserSearchField({ label, value, prefillUser, token, onChange, excludeUserId }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<FinanceRecord[]>([]);
  const [selectedUser, setSelectedUser] = useState<FinanceRecord | null>(prefillUser ?? null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (prefillUser) setSelectedUser(prefillUser);
  }, [prefillUser]);

  useEffect(() => {
    if (query.length < 2) { setResults([]); return; }
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      void fetchAdminSearch(token, query, "all", { limit: "20" })
        .then((r) => {
          const filtered = r.users
            .filter((u) => ["member", "athlete"].includes(field(u, "identity_role")))
            .filter((u) => !excludeUserId || field(u, "id") !== excludeUserId);
          setResults(filtered.slice(0, 20));
        })
        .catch(() => setResults([]));
    }, 150);
    return () => { if (debounceRef.current) clearTimeout(debounceRef.current); };
  }, [query, token, excludeUserId]);

  function handleSelect(user: FinanceRecord) {
    setSelectedUser(user);
    setQuery("");
    setResults([]);
    onChange(field(user, "id"), user);
  }

  function handleClear() {
    setSelectedUser(null);
    setQuery("");
    setResults([]);
    onChange("", null);
  }

  return (
    <div className="space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
        {label}
      </span>

      {selectedUser ? (
        <div
          className="flex items-center justify-between gap-3 rounded-[0.9rem] px-3 py-2"
          style={{ background: "#111118", border: "1px solid #1a1a28" }}
        >
          <div className="min-w-0 flex items-center gap-2">
            <span className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
              {field(selectedUser, "nickname")}
            </span>
            <span
              className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase"
              style={{ background: "#1a1a28", color: "#8888aa" }}
            >
              {field(selectedUser, "identity_role")}
            </span>
          </div>
          <button
            className="flex-shrink-0 text-xs font-semibold"
            style={{ color: "#55556a" }}
            onClick={handleClear}
            type="button"
          >
            ✕
          </button>
        </div>
      ) : (
        <div className="relative">
          <input
            className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
            style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
            placeholder="Type to search (min 2 chars)…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {results.length > 0 && (
            <div
              className="absolute left-0 top-full z-30 mt-1 w-full rounded-[1rem] overflow-hidden shadow-xl"
              style={{ background: "#0d0d18", border: "1px solid #1a1a28", maxHeight: "14rem", overflowY: "auto" }}
            >
              {results.map((u) => (
                <button
                  key={field(u, "id")}
                  className="flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left hover:opacity-80 transition-opacity"
                  style={{ borderBottom: "1px solid #1a1a28" }}
                  onClick={() => handleSelect(u)}
                  type="button"
                >
                  <span className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                    {field(u, "nickname")}
                  </span>
                  <span
                    className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase flex-shrink-0"
                    style={{ background: "#1a1a28", color: "#8888aa" }}
                  >
                    {field(u, "identity_role")}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | grep UserSearchField
```

- [ ] **Step 3: Commit**

```bash
git add src/components/admin/finance/shared/UserSearchField.tsx
git commit -m "feat(web/finance): UserSearchField — debounced Meilisearch user search with chip selection"
```

---

## Task 7: Frontend — rewire `MembersTab`

**Files:**
- Modify: `apps/web/src/components/admin/finance/tabs/MembersTab.tsx`

- [ ] **Step 1: Replace the entire file**

```tsx
"use client";

import { useCallback, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";

import {
  assignFinancePackage,
  fetchFinanceMembers,
  fetchFinancePackages,
  fetchReferralPrograms,
  updateFinanceMember,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { InlineCell, InlineToggle } from "@/components/admin/finance/shared/InlineCell";
import { Combobox, type ComboboxOption } from "@/components/admin/finance/shared/Combobox";
import { InlineAssignPackage } from "@/components/admin/finance/shared/InlineAssignPackage";
import { SortableHeader } from "@/components/admin/finance/shared/SortableHeader";
import { MemberPanel } from "@/components/admin/finance/panels/MemberPanel";
import { ReferralEventWizard } from "@/components/admin/finance/ReferralEventWizard";
import {
  useSortFilter,
  type ColumnKey,
  type FilterValue,
} from "@/components/admin/finance/hooks/useSortFilter";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function expiresWarn(expiresOn: string): boolean {
  if (!expiresOn) return false;
  const diff = new Date(expiresOn).getTime() - Date.now();
  return diff > 0 && diff < 30 * 24 * 60 * 60 * 1000;
}

function money(cents: unknown) {
  const n = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" }).format(n / 100);
}

const MEMBERSHIP_STATUS_OPTIONS = [
  { value: "active", label: "Active", accent: true },
  { value: "trial", label: "Trial" },
  { value: "expiring", label: "Expiring" },
  { value: "expired", label: "Expired" },
  { value: "comped", label: "Comped" },
  { value: "paused", label: "Paused" },
];

const ALL_STATUSES = ["active", "trial", "expiring", "expired", "comped", "paused", "cancelled"];

// ── Filter UI primitives ──────────────────────────────────────────────────────

function PillGroup({
  options,
  active,
  onToggle,
  onClear,
}: {
  options: string[];
  active: string | null;
  onToggle: (v: string) => void;
  onClear: () => void;
}) {
  return (
    <div className="space-y-1.5">
      {options.map((opt) => (
        <button
          key={opt}
          className="block w-full rounded-full px-3 py-1 text-left text-xs font-semibold"
          style={
            active === opt
              ? { background: "#d95d39", color: "#fff" }
              : { background: "#1a1a28", color: "#c0c0d8" }
          }
          onClick={() => onToggle(opt)}
          type="button"
        >
          {opt}
        </button>
      ))}
      {active && (
        <button className="text-xs" style={{ color: "#55556a" }} onClick={onClear} type="button">
          Clear
        </button>
      )}
    </div>
  );
}

function MultiCheck({
  options,
  selected,
  onToggle,
  onClear,
}: {
  options: string[];
  selected: string[];
  onToggle: (v: string) => void;
  onClear: () => void;
}) {
  return (
    <div className="space-y-1.5">
      {options.map((opt) => (
        <label key={opt} className="flex items-center gap-2 text-xs cursor-pointer" style={{ color: "#c0c0d8" }}>
          <input
            type="checkbox"
            checked={selected.includes(opt)}
            onChange={() => onToggle(opt)}
            className="accent-orange-500"
          />
          {opt || "—none—"}
        </label>
      ))}
      {selected.length > 0 && (
        <button className="text-xs" style={{ color: "#55556a" }} onClick={onClear} type="button">
          Clear
        </button>
      )}
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export function MembersTab() {
  const { tokens } = useSession();
  const token = tokens?.access_token!;
  const queryClient = useQueryClient();
  const router = useRouter();
  const searchParams = useSearchParams();

  const openMemberId = searchParams.get("member");
  const showReferralWizard = searchParams.get("new-referral") === "true";
  const prefillReferrerId = searchParams.get("referrer") ?? undefined;

  const setParam = useCallback(
    (updates: Record<string, string | null>) => {
      const params = new URLSearchParams(searchParams.toString());
      Object.entries(updates).forEach(([k, v]) => {
        if (v === null) params.delete(k);
        else params.set(k, v);
      });
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  // ── Queries ────────────────────────────────────────────────────────────────

  const membersQuery = useQuery({
    queryKey: ["admin", "finance", "members"],
    enabled: Boolean(token),
    queryFn: () => fetchFinanceMembers(token),
  });

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token),
  });

  const referralProgramsQuery = useQuery({
    queryKey: ["admin", "finance", "referral-programs"],
    enabled: Boolean(token),
    queryFn: () => fetchReferralPrograms(token),
  });

  const members = membersQuery.data?.members ?? [];
  const packages = packagesQuery.data?.packages ?? [];
  const referralPrograms = referralProgramsQuery.data?.referral_programs ?? [];

  // ── Sort + filter ──────────────────────────────────────────────────────────

  const { sort, cycleSort, filters, setFilter, result: filteredMembers } = useSortFilter(members);

  // ── Unique plan codes for Plan filter ──────────────────────────────────────

  const uniquePlanCodes = useMemo(() => {
    const codes = new Set<string>();
    members.forEach((m) => {
      const sub = m.active_package_subscription as FinanceRecord | null | undefined;
      const code = field(sub, "package_code_snapshot");
      codes.add(code || "none");
    });
    return Array.from(codes).sort();
  }, [members]);

  // ── Combobox for Referred By ───────────────────────────────────────────────

  const [userQuery, setUserQuery] = useState("");

  function userOptions(): ComboboxOption[] {
    const q = userQuery.toLowerCase();
    const filtered = q.length < 1 ? members : members.filter(
      (u) => field(u, "nickname").toLowerCase().includes(q),
    );
    return filtered.slice(0, 30).map((u) => ({
      value: field(u, "id"),
      label: field(u, "nickname"),
      sublabel: field(u, "identity_role"),
    }));
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  const updateMutation = useMutation({
    mutationFn: ({ userId, body }: { userId: string; body: FinanceRecord }) =>
      updateFinanceMember(token, userId, body),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  const assignPackageMutation = useMutation({
    mutationFn: ({ userId, packageId }: { userId: string; packageId: string }) =>
      assignFinancePackage(token, userId, { membership_package_id: packageId }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  // ── Prefill for referral wizard ────────────────────────────────────────────

  const prefillUser = useMemo(
    () => (prefillReferrerId ? members.find((m) => field(m, "id") === prefillReferrerId) ?? null : null),
    [prefillReferrerId, members],
  );

  const openMember = members.find((m) => field(m, "id") === openMemberId) ?? null;

  // ── Filter helpers ─────────────────────────────────────────────────────────

  function getMulti(col: ColumnKey): string[] {
    const f = filters[col];
    return f?.type === "multi" ? f.values : [];
  }

  function toggleMulti(col: ColumnKey, val: string) {
    const current = getMulti(col);
    const next = current.includes(val) ? current.filter((v) => v !== val) : [...current, val];
    setFilter(col, next.length > 0 ? { type: "multi", values: next } : undefined);
  }

  function getDatePreset(col: ColumnKey): string | null {
    const f = filters[col];
    return f?.type === "date_preset" ? f.value : null;
  }

  function setDatePreset(col: ColumnKey, val: FilterValue["value"] & string) {
    const current = getDatePreset(col);
    setFilter(col, current === val ? undefined : { type: "date_preset", value: val as never });
  }

  function getPresence(col: ColumnKey): string | null {
    const f = filters[col];
    return f?.type === "presence" ? f.value : null;
  }

  function setPresence(col: ColumnKey, val: "has" | "none") {
    const current = getPresence(col);
    setFilter(col, current === val ? undefined : { type: "presence", value: val });
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  if (membersQuery.isLoading) {
    return <p className="px-6 py-10 text-sm" style={{ color: "#55556a" }}>Loading members…</p>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>
          {filteredMembers.length} / {members.length} member{members.length !== 1 ? "s" : ""}
        </p>
      </div>

      <div className="rounded-[2rem] overflow-hidden" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
        <div className="overflow-x-auto">
          <table className="w-full border-collapse" style={{ minWidth: "1100px" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid #1a1a28" }}>
                {/* Nickname */}
                <th className="sticky left-0 z-10 px-4 py-3 text-left" style={{ background: "#111118" }}>
                  <SortableHeader
                    column="nickname" label="Nickname" sort={sort} hasFilter={Boolean(filters.nickname)}
                    onSort={() => cycleSort("nickname")}
                    filterSlot={
                      <input
                        autoFocus
                        className="w-full rounded-[0.8rem] px-2 py-1.5 text-xs outline-none"
                        style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                        placeholder="Search nickname…"
                        value={filters.nickname?.type === "text" ? filters.nickname.value : ""}
                        onChange={(e) => setFilter("nickname", e.target.value ? { type: "text", value: e.target.value } : undefined)}
                      />
                    }
                  />
                </th>
                {/* Type */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="type" label="Type" sort={sort} hasFilter={Boolean(filters.type)}
                    onSort={() => cycleSort("type")}
                    filterSlot={
                      <MultiCheck
                        options={["athlete", "member"]}
                        selected={getMulti("type")}
                        onToggle={(v) => toggleMulti("type", v)}
                        onClear={() => setFilter("type", undefined)}
                      />
                    }
                  />
                </th>
                {/* Status */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="status" label="Status" sort={sort} hasFilter={Boolean(filters.status)}
                    onSort={() => cycleSort("status")}
                    filterSlot={
                      <MultiCheck
                        options={ALL_STATUSES}
                        selected={getMulti("status")}
                        onToggle={(v) => toggleMulti("status", v)}
                        onClear={() => setFilter("status", undefined)}
                      />
                    }
                  />
                </th>
                {/* Plan */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="plan" label="Plan" sort={sort} hasFilter={Boolean(filters.plan)}
                    onSort={() => cycleSort("plan")}
                    filterSlot={
                      <MultiCheck
                        options={uniquePlanCodes}
                        selected={getMulti("plan")}
                        onToggle={(v) => toggleMulti("plan", v)}
                        onClear={() => setFilter("plan", undefined)}
                      />
                    }
                  />
                </th>
                {/* Expires */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="expires" label="Expires" sort={sort} hasFilter={Boolean(filters.expires)}
                    onSort={() => cycleSort("expires")}
                    filterSlot={
                      <PillGroup
                        options={["expired", "next30d", "no_expiry"]}
                        active={getDatePreset("expires")}
                        onToggle={(v) => setDatePreset("expires", v as never)}
                        onClear={() => setFilter("expires", undefined)}
                      />
                    }
                  />
                </th>
                {/* Last paid */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="last_paid" label="Last paid" sort={sort} hasFilter={Boolean(filters.last_paid)}
                    onSort={() => cycleSort("last_paid")}
                    filterSlot={
                      <PillGroup
                        options={["never", "last30d", "last90d"]}
                        active={getDatePreset("last_paid")}
                        onToggle={(v) => setDatePreset("last_paid", v as never)}
                        onClear={() => setFilter("last_paid", undefined)}
                      />
                    }
                  />
                </th>
                {/* Amount */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="amount" label="Amount" sort={sort} hasFilter={Boolean(filters.amount)}
                    onSort={() => cycleSort("amount")}
                    filterSlot={
                      <PillGroup
                        options={["has", "none"]}
                        active={getPresence("amount")}
                        onToggle={(v) => setPresence("amount", v as "has" | "none")}
                        onClear={() => setFilter("amount", undefined)}
                      />
                    }
                  />
                </th>
                {/* Credits */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="credits" label="Credits" sort={sort} hasFilter={Boolean(filters.credits)}
                    onSort={() => cycleSort("credits")}
                    filterSlot={
                      <PillGroup
                        options={["positive", "negative"]}
                        active={filters.credits?.type === "sign" ? filters.credits.value : null}
                        onToggle={(v) => setFilter("credits", { type: "sign", value: v as "positive" | "negative" })}
                        onClear={() => setFilter("credits", undefined)}
                      />
                    }
                  />
                </th>
                {/* Notes */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="notes" label="Notes" sort={sort} hasFilter={Boolean(filters.notes)}
                    onSort={() => cycleSort("notes")}
                    filterSlot={
                      <PillGroup
                        options={["has", "none"]}
                        active={getPresence("notes")}
                        onToggle={(v) => setPresence("notes", v as "has" | "none")}
                        onClear={() => setFilter("notes", undefined)}
                      />
                    }
                  />
                </th>
                {/* Referred By */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="referred_by" label="Referred By" sort={sort} hasFilter={Boolean(filters.referred_by)}
                    onSort={() => cycleSort("referred_by")}
                    filterSlot={
                      <PillGroup
                        options={["has", "none"]}
                        active={getPresence("referred_by")}
                        onToggle={(v) => setPresence("referred_by", v as "has" | "none")}
                        onClear={() => setFilter("referred_by", undefined)}
                      />
                    }
                  />
                </th>
                {/* Referrals */}
                <th className="px-4 py-3 text-left">
                  <SortableHeader
                    column="referrals" label="Referrals" sort={sort} hasFilter={Boolean(filters.referrals)}
                    onSort={() => cycleSort("referrals")}
                    filterSlot={
                      <PillGroup
                        options={["has", "none"]}
                        active={getPresence("referrals")}
                        onToggle={(v) => setPresence("referrals", v as "has" | "none")}
                        onClear={() => setFilter("referrals", undefined)}
                      />
                    }
                  />
                </th>
              </tr>
            </thead>
            <tbody>
              {filteredMembers.length === 0 ? (
                <tr>
                  <td colSpan={11} className="px-6 py-8 text-sm" style={{ color: "#55556a" }}>
                    {members.length === 0 ? "No members yet." : "No members match the current filters."}
                  </td>
                </tr>
              ) : (
                filteredMembers.map((member, i) => (
                  <MemberRow
                    key={field(member, "id")}
                    member={member}
                    last={i === filteredMembers.length - 1}
                    packages={packages}
                    userOptions={userOptions()}
                    onUserSearch={setUserQuery}
                    updatePending={updateMutation.isPending}
                    assignPending={assignPackageMutation.isPending}
                    onSave={(body) => updateMutation.mutate({ userId: field(member, "id"), body })}
                    onAssignPackage={(packageId) =>
                      assignPackageMutation.mutate({ userId: field(member, "id"), packageId })
                    }
                    onOpenPanel={() => setParam({ member: field(member, "id"), tab: "members" })}
                    onOpenReferralWizard={() =>
                      setParam({ "new-referral": "true", referrer: field(member, "id") })
                    }
                  />
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {openMember ? (
        <MemberPanel
          userId={field(openMember, "id")}
          nickname={field(openMember, "nickname")}
          onClose={() => setParam({ member: null })}
        />
      ) : null}

      {showReferralWizard ? (
        <ReferralEventWizard
          programs={referralPrograms}
          packages={packages}
          prefillReferrerId={prefillReferrerId}
          prefillReferrerUser={prefillUser}
          onClose={() => setParam({ "new-referral": null, referrer: null })}
        />
      ) : null}
    </div>
  );
}

// ── MemberRow ─────────────────────────────────────────────────────────────────

function MemberRow({
  member,
  last,
  packages,
  userOptions,
  onUserSearch,
  updatePending,
  assignPending,
  onSave,
  onAssignPackage,
  onOpenPanel,
  onOpenReferralWizard,
}: {
  member: FinanceRecord;
  last: boolean;
  packages: FinanceRecord[];
  userOptions: ComboboxOption[];
  onUserSearch: (q: string) => void;
  updatePending: boolean;
  assignPending: boolean;
  onSave: (body: FinanceRecord) => void;
  onAssignPackage: (packageId: string) => void;
  onOpenPanel: () => void;
  onOpenReferralWizard: () => void;
}) {
  const membership = member.membership as FinanceRecord | null | undefined;
  const activeSub = member.active_package_subscription as FinanceRecord | null | undefined;
  const referralsMade = (member.referrals_made_user_ids as string[]) ?? [];

  const expiresOn = field(activeSub, "ends_on") || field(membership, "expires_on");
  const membershipStatus = field(membership, "status", "trial");
  const referredById = field(membership, "referred_by_user_id");
  const creditCents = typeof member.credit_balance === "number" ? member.credit_balance : 0;
  const userType = field(membership, "user_type_snapshot") || field(member, "identity_role");
  const currentPlanCode = field(activeSub, "package_code_snapshot") || null;
  const lastPaymentOn = typeof member.last_payment_on === "string" ? member.last_payment_on : null;
  const lastPaymentAmountCents = typeof member.last_payment_amount_cents === "number" ? member.last_payment_amount_cents : null;
  const notes = typeof member.notes === "string" ? member.notes : "";

  const borderStyle = last ? undefined : "1px solid #1a1a28";

  return (
    <tr style={{ borderBottom: borderStyle }}>
      {/* Nickname */}
      <td className="sticky left-0 z-10 px-4 py-3" style={{ background: "#111118" }}>
        <button
          className="text-sm font-semibold text-left hover:opacity-70 transition-opacity"
          style={{ color: "#F0EDF8" }}
          onClick={onOpenPanel}
          type="button"
        >
          {field(member, "nickname")}
        </button>
      </td>

      {/* Type */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {userType ? (
          <span
            className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-wider"
            style={{
              background: userType === "athlete" ? "rgba(217,93,57,0.12)" : "rgba(136,136,170,0.12)",
              color: userType === "athlete" ? "#d95d39" : "#8888aa",
            }}
          >
            {userType}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Status */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineToggle
          value={membershipStatus}
          options={MEMBERSHIP_STATUS_OPTIONS}
          onSave={(status) => onSave({ status })}
        />
      </td>

      {/* Plan */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineAssignPackage
          currentCode={currentPlanCode}
          packages={packages}
          pending={assignPending}
          onAssign={onAssignPackage}
        />
      </td>

      {/* Expires */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineCell
          value={expiresOn}
          type="date"
          onSave={(expires_on) => onSave({ expires_on })}
          placeholder="No expiry"
          warn={expiresWarn(expiresOn)}
          dimmed={!expiresOn}
        />
      </td>

      {/* Last paid */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {lastPaymentOn ? (
          <span className="text-xs" style={{ color: "#c0c0d8" }}>{lastPaymentOn}</span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Amount */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {lastPaymentAmountCents !== null ? (
          <span className="text-xs font-semibold" style={{ color: "#4db89c" }}>
            {money(lastPaymentAmountCents)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Credits */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {creditCents !== 0 ? (
          <span className="text-xs font-semibold" style={{ color: creditCents > 0 ? "#4db89c" : "#e07a5f" }}>
            {money(creditCents)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Notes */}
      <td className="px-4 py-3" style={{ minWidth: "160px" }}>
        <InlineCell
          value={notes}
          type="text"
          onSave={(notes) => onSave({ notes })}
          placeholder="Add note…"
          dimmed={!notes}
        />
      </td>

      {/* Referred By */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <Combobox
          value={referredById}
          placeholder="None"
          options={userOptions}
          onSearch={onUserSearch}
          onChange={(id) => onSave({ referred_by_user_id: id || null })}
          nullable
        />
      </td>

      {/* Referrals */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <div className="flex items-center gap-2">
          {referralsMade.length > 0 ? (
            <span className="text-xs font-semibold" style={{ color: "#c0c0d8" }}>
              {referralsMade.length}
            </span>
          ) : (
            <span className="text-xs" style={{ color: "#3a3a55" }}>0</span>
          )}
          <button
            className="rounded-full px-2 py-0.5 text-xs font-semibold"
            style={{
              background: "rgba(217,93,57,0.1)",
              border: "1px solid rgba(217,93,57,0.2)",
              color: "#d95d39",
            }}
            onClick={onOpenReferralWizard}
            disabled={updatePending}
            type="button"
            title="Record new referral"
          >
            +
          </button>
        </div>
      </td>
    </tr>
  );
}
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | grep -E "MembersTab|error"
```

Fix any type errors before proceeding.

- [ ] **Step 3: Commit**

```bash
git add src/components/admin/finance/tabs/MembersTab.tsx
git commit -m "feat(web/finance): Members table — 3 new columns, inline Plan assign, sort/filter headers"
```

---

## Task 8: Frontend — rewrite `ReferralEventWizard` Step 1

**Files:**
- Modify: `apps/web/src/components/admin/finance/ReferralEventWizard.tsx`

- [ ] **Step 1: Replace the file**

The entire file. Steps 2 and 3 (approve/reject/reward) are unchanged — only Step 1 is redesigned.

```tsx
"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  assignFinancePackage,
  createReferralEvent,
  createReferralReward,
  fetchFinancePackages,
  updateReferralEventStatus,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";

type Step = 1 | 2 | 3;

type WizardProps = {
  programs: FinanceRecord[];
  packages?: FinanceRecord[];
  prefillReferrerId?: string;
  prefillReferrerUser?: FinanceRecord | null;
  onClose: () => void;
};

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

export function ReferralEventWizard({
  programs,
  packages: packagesProp,
  prefillReferrerId,
  prefillReferrerUser,
  onClose,
}: WizardProps) {
  const { tokens } = useSession();
  const token = tokens?.access_token!;
  const queryClient = useQueryClient();

  const [step, setStep] = useState<Step>(1);
  const [createdEventId, setCreatedEventId] = useState<string | null>(null);

  const [referrerUser, setReferrerUser] = useState<FinanceRecord | null>(prefillReferrerUser ?? null);
  const [refereeUser, setRefereeUser] = useState<FinanceRecord | null>(null);

  const [form, setForm] = useState({
    referral_program_id: field(programs[0], "id"),
    referrer_user_id: prefillReferrerId ?? "",
    referred_user_id: "",
    membership_id: "",
    notes: "",
  });

  // Inline membership setup state
  const [showMembershipSetup, setShowMembershipSetup] = useState(false);
  const [inlinePackageId, setInlinePackageId] = useState("");

  // Packages — use prop if provided (from MembersTab), else fetch independently
  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token) && !packagesProp,
    queryFn: () => fetchFinancePackages(token),
  });
  const packages = packagesProp ?? packagesQuery.data?.packages ?? [];
  const activePackages = packages.filter((p) => p.active !== false);

  const selectedProgram = programs.find((p) => field(p, "id") === form.referral_program_id);

  const refereeMembership = refereeUser?.membership as FinanceRecord | null | undefined;
  const refereeHasNoMembership = Boolean(form.referred_user_id) && !form.membership_id;

  const canProceedStep1 = Boolean(
    form.referral_program_id && form.referrer_user_id && form.referred_user_id && form.membership_id,
  );

  // ── Mutations ──────────────────────────────────────────────────────────────

  const createEventMutation = useMutation({
    mutationFn: () =>
      createReferralEvent(token, {
        referral_program_id: form.referral_program_id,
        referrer_user_id: form.referrer_user_id,
        referred_user_id: form.referred_user_id,
        membership_id: form.membership_id || undefined,
        notes: form.notes,
        signup_source_snapshot: "referral",
      }),
    onSuccess: (data) => {
      setCreatedEventId(field(data.referral_event, "id"));
      setStep(2);
    },
  });

  const approveEventMutation = useMutation({
    mutationFn: () => updateReferralEventStatus(token, createdEventId!, "approved"),
    onSuccess: async () => {
      setStep(3);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
    },
  });

  const rejectEventMutation = useMutation({
    mutationFn: () => updateReferralEventStatus(token, createdEventId!, "rejected"),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
      onClose();
    },
  });

  const createRewardMutation = useMutation({
    mutationFn: () => createReferralReward(token, createdEventId!, {}),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referral-rewards"] });
      onClose();
    },
  });

  const assignMembershipMutation = useMutation({
    mutationFn: () =>
      assignFinancePackage(token, form.referred_user_id, { membership_package_id: inlinePackageId }),
    onSuccess: async (data) => {
      const membershipId = field(data.package_subscription, "membership_id");
      setForm((f) => ({ ...f, membership_id: membershipId }));
      setShowMembershipSetup(false);
      setInlinePackageId("");
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  // ── Handlers ───────────────────────────────────────────────────────────────

  function handleReferrerChange(userId: string, user: FinanceRecord | null) {
    setReferrerUser(user);
    setForm((f) => ({ ...f, referrer_user_id: userId }));
  }

  function handleRefereeChange(userId: string, user: FinanceRecord | null) {
    setRefereeUser(user);
    const membership = user?.membership as FinanceRecord | null | undefined;
    setForm((f) => ({
      ...f,
      referred_user_id: userId,
      membership_id: field(membership, "id"),
    }));
    setShowMembershipSetup(false);
    setInlinePackageId("");
  }

  const stepLabel = step === 1 ? "Record referral" : step === 2 ? "Review & decide" : "Issue reward";

  return (
    <SidePanel
      title="New referral event"
      subtitle={`Step ${step} of 3 — ${stepLabel}`}
      onClose={onClose}
    >
      {/* Step indicator */}
      <div className="flex gap-2">
        {([1, 2, 3] as Step[]).map((s) => (
          <div
            key={s}
            className="h-1 flex-1 rounded-full"
            style={{ background: s <= step ? "#d95d39" : "#1a1a28" }}
          />
        ))}
      </div>

      {/* ── Step 1 ── */}
      {step === 1 && (
        <div className="space-y-5">
          {/* Program */}
          <label className="block space-y-1">
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
              Referral program
            </span>
            <select
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
              value={form.referral_program_id}
              onChange={(e) => setForm({ ...form, referral_program_id: e.target.value })}
            >
              {programs.filter((p) => p.active !== false).map((p) => (
                <option key={field(p, "id")} value={field(p, "id")}>{field(p, "name")}</option>
              ))}
            </select>
          </label>

          {/* Referrer */}
          <UserSearchField
            label="Referrer"
            value={form.referrer_user_id}
            prefillUser={prefillReferrerUser}
            token={token}
            onChange={handleReferrerChange}
            excludeUserId={form.referred_user_id || undefined}
          />

          {/* Referee */}
          <div className="space-y-2">
            <UserSearchField
              label="Referee"
              value={form.referred_user_id}
              token={token}
              onChange={handleRefereeChange}
              excludeUserId={form.referrer_user_id || undefined}
            />

            {/* Inline membership setup */}
            {refereeHasNoMembership && (
              <div
                className="rounded-[1.2rem] p-4 space-y-3"
                style={{ background: "rgba(217,93,57,0.06)", border: "1px solid rgba(217,93,57,0.2)" }}
              >
                <p className="text-xs font-semibold" style={{ color: "#d95d39" }}>
                  ⚠ This user has no membership.
                </p>
                {!showMembershipSetup ? (
                  <button
                    className="text-xs font-semibold underline"
                    style={{ color: "#d95d39" }}
                    onClick={() => setShowMembershipSetup(true)}
                    type="button"
                  >
                    Assign a package to continue →
                  </button>
                ) : (
                  <div className="space-y-2">
                    <select
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      value={inlinePackageId}
                      onChange={(e) => setInlinePackageId(e.target.value)}
                    >
                      <option value="">Select package…</option>
                      {activePackages.map((p) => (
                        <option key={field(p, "id")} value={field(p, "id")}>
                          {field(p, "name", field(p, "code"))}
                        </option>
                      ))}
                    </select>
                    <div className="flex gap-2">
                      <button
                        className="flex-1 rounded-full py-2 text-xs font-semibold disabled:opacity-50"
                        style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                        disabled={!inlinePackageId || assignMembershipMutation.isPending}
                        onClick={() => assignMembershipMutation.mutate()}
                        type="button"
                      >
                        {assignMembershipMutation.isPending ? "Assigning…" : "Assign & continue"}
                      </button>
                      <button
                        className="rounded-full px-4 py-2 text-xs font-semibold"
                        style={{ background: "#1a1a28", color: "#c0c0d8" }}
                        onClick={() => setShowMembershipSetup(false)}
                        type="button"
                      >
                        Cancel
                      </button>
                    </div>
                    {assignMembershipMutation.error instanceof Error && (
                      <p className="text-xs" style={{ color: "#e07a5f" }}>
                        {assignMembershipMutation.error.message}
                      </p>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Summary */}
          <div className="rounded-[1.4rem] p-4 space-y-2" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
            <SummaryRow label="Referrer" value={field(referrerUser, "nickname") || form.referrer_user_id || "Not selected"} />
            <SummaryRow label="Referee" value={field(refereeUser, "nickname") || form.referred_user_id || "Not selected"} />
            <SummaryRow
              label="Membership"
              value={form.membership_id || (form.referred_user_id ? "No membership" : "Select referee")}
              warn={Boolean(form.referred_user_id && !form.membership_id)}
            />
          </div>

          {/* Notes */}
          <label className="block space-y-1">
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
              Notes (optional)
            </span>
            <textarea
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none resize-none"
              style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
              rows={3}
              value={form.notes}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
            />
          </label>

          <button
            className="w-full rounded-full py-3 text-sm font-semibold disabled:opacity-50"
            style={{
              background: canProceedStep1 ? "#F0EDF8" : "#1a1a28",
              color: canProceedStep1 ? "#0A0A0F" : "#55556a",
            }}
            disabled={!canProceedStep1 || createEventMutation.isPending}
            onClick={() => createEventMutation.mutate()}
            type="button"
          >
            {createEventMutation.isPending ? "Recording…" : "Record referral → Step 2"}
          </button>
          {createEventMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "#e07a5f" }}>{createEventMutation.error.message}</p>
          )}
        </div>
      )}

      {/* ── Step 2 ── (unchanged logic) */}
      {step === 2 && (
        <div className="space-y-5">
          <div className="rounded-[1.4rem] p-4 space-y-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Referral summary</p>
            <SummaryRow label="Program" value={field(selectedProgram, "name")} />
            <SummaryRow label="Referrer" value={field(referrerUser, "nickname") || form.referrer_user_id} />
            <SummaryRow label="Referee" value={field(refereeUser, "nickname") || form.referred_user_id} />
            <SummaryRow label="Membership" value={form.membership_id} />
            {form.notes && <SummaryRow label="Notes" value={form.notes} />}
          </div>
          <p className="text-sm leading-6" style={{ color: "#8888aa" }}>
            Approving records this referral as valid and enables reward issuance. Rejecting marks it as permanently invalid.
          </p>
          <div className="flex gap-3">
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "#F0EDF8", color: "#0A0A0F" }}
              disabled={approveEventMutation.isPending || rejectEventMutation.isPending}
              onClick={() => approveEventMutation.mutate()}
              type="button"
            >
              {approveEventMutation.isPending ? "Approving…" : "Approve → Step 3"}
            </button>
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.3)", color: "#d95d39" }}
              disabled={approveEventMutation.isPending || rejectEventMutation.isPending}
              onClick={() => rejectEventMutation.mutate()}
              type="button"
            >
              {rejectEventMutation.isPending ? "Rejecting…" : "Reject (terminal)"}
            </button>
          </div>
          {(approveEventMutation.error ?? rejectEventMutation.error) instanceof Error && (
            <p className="text-sm" style={{ color: "#e07a5f" }}>
              {((approveEventMutation.error ?? rejectEventMutation.error) as Error).message}
            </p>
          )}
        </div>
      )}

      {/* ── Step 3 ── (unchanged logic) */}
      {step === 3 && (
        <div className="space-y-5">
          <div className="rounded-[1.4rem] p-4 space-y-3" style={{ background: "rgba(77,184,156,0.07)", border: "1px solid rgba(77,184,156,0.2)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#4db89c" }}>Event approved</p>
            <p className="text-sm" style={{ color: "#8888aa" }}>
              Reward policy from <span style={{ color: "#F0EDF8" }}>{field(selectedProgram, "name")}</span>
            </p>
            <SummaryRow label="Reward type" value={field(selectedProgram, "reward_type")} />
            <SummaryRow label="Reward value" value={field(selectedProgram, "reward_value")} />
          </div>
          <p className="text-sm leading-6" style={{ color: "#8888aa" }}>
            Issue the reward now, or skip and create it later from the Rewards section.
          </p>
          <div className="flex gap-3">
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "#F0EDF8", color: "#0A0A0F" }}
              disabled={createRewardMutation.isPending}
              onClick={() => createRewardMutation.mutate()}
              type="button"
            >
              {createRewardMutation.isPending ? "Creating…" : "Create reward"}
            </button>
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold"
              style={{ background: "#1a1a28", color: "#c0c0d8" }}
              onClick={onClose}
              type="button"
            >
              Skip for now
            </button>
          </div>
          {createRewardMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "#e07a5f" }}>{createRewardMutation.error.message}</p>
          )}
        </div>
      )}
    </SidePanel>
  );
}

function SummaryRow({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 text-sm">
      <span style={{ color: "#55556a" }}>{label}</span>
      <span className="text-right font-semibold" style={{ color: warn ? "#e07a5f" : "#F0EDF8" }}>
        {value || "—"}
      </span>
    </div>
  );
}
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | grep -E "ReferralEventWizard|error"
```

Fix any errors before committing.

- [ ] **Step 3: Full TypeScript check**

```bash
npx tsc --noEmit 2>&1 | head -40
```

Expected: 0 errors across the whole web app.

- [ ] **Step 4: Commit**

```bash
git add src/components/admin/finance/ReferralEventWizard.tsx
git commit -m "feat(web/finance): referral wizard — dual UserSearchField, inline membership setup"
```

---

## Task 9: Final checks

- [ ] **Step 1: Run Elixir tests**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/api
mix test 2>&1 | tail -10
```

Expected: all tests pass, 0 failures.

- [ ] **Step 2: Run Elixir linter**

```bash
mix credo --strict 2>&1 | grep -E "error|warning" | head -20
```

Fix any issues introduced by the backend changes.

- [ ] **Step 3: Final TypeScript check**

```bash
cd /home/rodochrousbisbiki/MyApps/milos/apps/web
npx tsc --noEmit 2>&1 | head -20
```

Expected: 0 errors.

- [ ] **Step 4: Final commit if any cleanup was needed**

```bash
git add -p
git commit -m "fix: cleanup from final checks"
```
