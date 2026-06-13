"use client";

import { useMemo, useState } from "react";
import type { FinanceRecord } from "@/api/finance";

export type ColumnKey =
  | "nickname"
  | "type"
  | "status"
  | "plan"
  | "expires"
  | "last_paid"
  | "amount"
  | "credits"
  | "notes"
  | "referred_by"
  | "referrals";

export type SortState = { column: ColumnKey | null; direction: "asc" | "desc" };

export type FilterValue =
  | { kind: "text"; value: string }
  | { kind: "multi"; values: string[] }
  | { kind: "presence"; value: "has" | "none" }
  | { kind: "sign"; value: "positive" | "negative" }
  | { kind: "date_preset"; preset: string };

export type FilterState = Partial<Record<ColumnKey, FilterValue>>;

function field(record: FinanceRecord | null | undefined, key: string): unknown {
  return record?.[key] ?? null;
}

function str(v: unknown): string {
  if (v === null || v === undefined) return "";
  return String(v);
}

function num(v: unknown): number {
  if (typeof v === "number") return v;
  return 0;
}

function membership(member: FinanceRecord): FinanceRecord | null {
  return (member.membership as FinanceRecord | null) ?? null;
}

function activeSub(member: FinanceRecord): FinanceRecord | null {
  return (member.active_package_subscription as FinanceRecord | null) ?? null;
}

function applyFilter(member: FinanceRecord, col: ColumnKey, filter: FilterValue): boolean {
  const mem = membership(member);
  const sub = activeSub(member);

  switch (col) {
    case "nickname": {
      if (filter.kind !== "text") return true;
      return str(field(member, "nickname")).toLowerCase().includes(filter.value.toLowerCase());
    }
    case "type": {
      if (filter.kind !== "multi" || filter.values.length === 0) return true;
      const role =
        str(field(mem, "user_type_snapshot")) || str(field(member, "identity_role"));
      return filter.values.includes(role);
    }
    case "status": {
      if (filter.kind !== "multi" || filter.values.length === 0) return true;
      return filter.values.includes(str(field(mem, "status")));
    }
    case "plan": {
      if (filter.kind !== "multi" || filter.values.length === 0) return true;
      const code = str(field(sub, "package_code_snapshot"));
      if (filter.values.includes("__none__")) {
        if (!code) return true;
      }
      return filter.values.includes(code);
    }
    case "expires": {
      if (filter.kind !== "date_preset") return true;
      const raw = str(field(sub, "ends_on")) || str(field(mem, "expires_on"));
      const now = Date.now();
      switch (filter.preset) {
        case "expired":
          return Boolean(raw) && new Date(raw).getTime() < now;
        case "next_30d": {
          if (!raw) return false;
          const t = new Date(raw).getTime();
          return t >= now && t < now + 30 * 86400_000;
        }
        case "no_expiry":
          return !raw;
        default:
          return true;
      }
    }
    case "last_paid": {
      if (filter.kind !== "date_preset") return true;
      const raw = str(field(member, "last_payment_on"));
      const now = Date.now();
      switch (filter.preset) {
        case "never":
          return !raw;
        case "last_30d":
          return Boolean(raw) && now - new Date(raw).getTime() <= 30 * 86400_000;
        case "last_90d":
          return Boolean(raw) && now - new Date(raw).getTime() <= 90 * 86400_000;
        default:
          return true;
      }
    }
    case "amount": {
      if (filter.kind !== "presence") return true;
      const has = Boolean(field(member, "last_payment_amount_cents"));
      return filter.value === "has" ? has : !has;
    }
    case "credits": {
      if (filter.kind !== "sign") return true;
      const bal = num(field(member, "credit_balance"));
      return filter.value === "positive" ? bal > 0 : bal < 0;
    }
    case "notes": {
      if (filter.kind !== "presence") return true;
      const has = Boolean(str(field(member, "notes")));
      return filter.value === "has" ? has : !has;
    }
    case "referred_by": {
      if (filter.kind !== "presence") return true;
      const has = Boolean(field(mem, "referred_by_user_id"));
      return filter.value === "has" ? has : !has;
    }
    case "referrals": {
      if (filter.kind !== "presence") return true;
      const count = ((member.referrals_made_user_ids as string[]) ?? []).length;
      return filter.value === "has" ? count > 0 : count === 0;
    }
  }
}

function cmp(a: FinanceRecord, b: FinanceRecord, col: ColumnKey): number {
  const memA = membership(a);
  const memB = membership(b);
  const subA = activeSub(a);
  const subB = activeSub(b);

  switch (col) {
    case "nickname":
      return str(field(a, "nickname")).localeCompare(str(field(b, "nickname")));
    case "type": {
      const ta = str(field(memA, "user_type_snapshot")) || str(field(a, "identity_role"));
      const tb = str(field(memB, "user_type_snapshot")) || str(field(b, "identity_role"));
      return ta.localeCompare(tb);
    }
    case "status":
      return str(field(memA, "status")).localeCompare(str(field(memB, "status")));
    case "plan":
      return str(field(subA, "package_code_snapshot")).localeCompare(
        str(field(subB, "package_code_snapshot"))
      );
    case "expires": {
      const ea = str(field(subA, "ends_on")) || str(field(memA, "expires_on"));
      const eb = str(field(subB, "ends_on")) || str(field(memB, "expires_on"));
      if (!ea && !eb) return 0;
      if (!ea) return 1;
      if (!eb) return -1;
      return new Date(ea).getTime() - new Date(eb).getTime();
    }
    case "last_paid": {
      const la = str(field(a, "last_payment_on"));
      const lb = str(field(b, "last_payment_on"));
      if (!la && !lb) return 0;
      if (!la) return 1;
      if (!lb) return -1;
      return new Date(la).getTime() - new Date(lb).getTime();
    }
    case "amount":
      return num(field(a, "last_payment_amount_cents")) - num(field(b, "last_payment_amount_cents"));
    case "credits":
      return num(field(a, "credit_balance")) - num(field(b, "credit_balance"));
    case "notes": {
      const na = str(field(a, "notes"));
      const nb = str(field(b, "notes"));
      if (Boolean(na) !== Boolean(nb)) return na ? -1 : 1;
      return na.localeCompare(nb);
    }
    case "referred_by": {
      const ra = Boolean(field(memA, "referred_by_user_id"));
      const rb = Boolean(field(memB, "referred_by_user_id"));
      return ra === rb ? 0 : ra ? -1 : 1;
    }
    case "referrals": {
      const ca = ((a.referrals_made_user_ids as string[]) ?? []).length;
      const cb = ((b.referrals_made_user_ids as string[]) ?? []).length;
      return ca - cb;
    }
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

  function clearFilters() {
    setFilters({});
  }

  const result = useMemo(() => {
    let out = members;

    const activeFilters = Object.entries(filters) as [ColumnKey, FilterValue][];
    if (activeFilters.length > 0) {
      out = out.filter((m) => activeFilters.every(([col, fv]) => applyFilter(m, col, fv)));
    }

    if (sort.column) {
      const col = sort.column;
      const dir = sort.direction === "asc" ? 1 : -1;
      out = [...out].sort((a, b) => cmp(a, b, col) * dir);
    }

    return out;
  }, [members, filters, sort]);

  return { sort, cycleSort, filters, setFilter, clearFilters, result };
}
