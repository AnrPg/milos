import type { Machine, MachineEventKind, Supply } from "@/api/inventory";
import { can, type MembershipLike } from "@/lib/role-navigation";

// Pure helpers for the inventory page (ADR-104).

export type InventoryTab = "machines" | "supplies" | "report";

export function inventoryTab(requested: string | null | undefined, canManage: boolean): InventoryTab {
  if (requested === "supplies") return "supplies";
  if (requested === "report" && canManage) return "report";
  return "machines";
}

/** Kinds anyone on the team may log; the rest are for managers. */
export const REPORTER_EVENT_KINDS: MachineEventKind[] = ["note", "issue", "out_of_order"];
export const MANAGER_EVENT_KINDS: MachineEventKind[] = [...REPORTER_EVENT_KINDS, "repair_requested", "maintenance", "repaired", "retired"];

export function loggableEventKinds(membership: MembershipLike | null | undefined): MachineEventKind[] {
  if (can(membership, "manage_inventory")) return MANAGER_EVENT_KINDS;
  if (can(membership, "report_inventory")) return REPORTER_EVENT_KINDS;
  return [];
}

/** Service and repair entries carry a cost. */
export function eventKindHasCost(kind: MachineEventKind) {
  return kind === "maintenance" || kind === "repaired";
}

/** Problem reports carry severity, symptom and "still usable". */
export function eventKindIsProblem(kind: MachineEventKind) {
  return kind === "issue" || kind === "out_of_order";
}

const STOCK_RANK: Record<Supply["stock_status"], number> = { out: 0, critical: 1, low: 2, ok: 3 };

export function stockStatus(supply: Pick<Supply, "stock" | "stock_status">): Supply["stock_status"] {
  return supply.stock?.status ?? supply.stock_status;
}

/** Most urgent first: out, critical, low, ok; open reports first within a level, then fewest days left, then name. */
export function sortByUrgency<T extends Pick<Supply, "name" | "stock" | "stock_status" | "open_reports">>(supplies: T[]): T[] {
  return [...supplies].sort((a, b) => {
    const rank = STOCK_RANK[stockStatus(a)] - STOCK_RANK[stockStatus(b)];
    if (rank !== 0) return rank;
    const reported = Number((b.open_reports ?? []).length > 0) - Number((a.open_reports ?? []).length > 0);
    if (reported !== 0) return reported;
    const daysA = a.stock?.days_left ?? Number.POSITIVE_INFINITY;
    const daysB = b.stock?.days_left ?? Number.POSITIVE_INFINITY;
    if (daysA !== daysB) return daysA < daysB ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

const MACHINE_STATUS_RANK: Record<Machine["status"], number> = { out_of_order: 0, needs_attention: 1, working: 2, retired: 3 };

/** Training machines then appliances; broken ones first, then by name. Archived ones are dropped. */
export function groupMachines<T extends Pick<Machine, "category" | "status" | "name" | "archived_at">>(machines: T[]) {
  const sorted = machines
    .filter((machine) => !machine.archived_at)
    .sort((a, b) => MACHINE_STATUS_RANK[a.status] - MACHINE_STATUS_RANK[b.status] || a.name.localeCompare(b.name));
  return (["training", "appliance"] as const)
    .map((category) => ({ category, machines: sorted.filter((machine) => machine.category === category) }))
    .filter((group) => group.machines.length > 0);
}

/** "due" when the API says so or the date has passed; "soon" within `soonDays`. */
export function serviceState(
  machine: Pick<Machine, "service_due" | "next_service_on">,
  today: Date = new Date(),
  soonDays = 14,
): "due" | "soon" | null {
  if (machine.service_due) return "due";
  if (!machine.next_service_on) return null;
  const next = Date.parse(`${machine.next_service_on}T00:00:00Z`);
  if (Number.isNaN(next)) return null;
  const startOfToday = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  const days = (next - startOfToday) / 86_400_000;
  if (days < 0) return "due";
  return days <= soonDays ? "soon" : null;
}

export function formatMoney(cents: number | null | undefined, locale: string, currency = "EUR") {
  if (cents === null || cents === undefined) return "—";
  return new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100);
}

/** "12.50" / "12,50" → 1250; empty or invalid → null. */
export function parseMoneyToCents(value: string): number | null {
  const normalized = value.trim().replace(/\s/g, "").replace(",", ".");
  if (!normalized) return null;
  const amount = Number(normalized);
  if (!Number.isFinite(amount) || amount < 0) return null;
  return Math.round(amount * 100);
}

export function centsToInput(cents: number | null | undefined) {
  return cents === null || cents === undefined ? "" : (cents / 100).toFixed(2);
}

export function parseQuantity(value: string): number | null {
  const normalized = value.trim().replace(",", ".");
  if (!normalized) return null;
  const amount = Number(normalized);
  return Number.isFinite(amount) && amount >= 0 ? amount : null;
}

/** Bar width in percent of the largest value, never NaN. */
export function barPercent(value: number, max: number) {
  if (max <= 0 || value <= 0) return 0;
  return Math.min(100, Math.round((value / max) * 1000) / 10);
}
