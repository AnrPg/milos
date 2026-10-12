import { describe, expect, it } from "vitest";

import {
  barPercent,
  formatMoney,
  groupMachines,
  inventoryTab,
  loggableEventKinds,
  parseMoneyToCents,
  serviceState,
  sortByUrgency,
} from "@/components/inventory/inventory-helpers";

type SupplyLike = Parameters<typeof sortByUrgency>[0][number];

const supply = (name: string, status: SupplyLike["stock_status"], extra: Partial<SupplyLike> = {}): SupplyLike => ({
  name,
  stock_status: status,
  open_reports: [],
  ...extra,
});

describe("sortByUrgency", () => {
  it("orders out, critical, low, ok", () => {
    const sorted = sortByUrgency([supply("a", "ok"), supply("b", "low"), supply("c", "out"), supply("d", "critical")]);
    expect(sorted.map((item) => item.name)).toEqual(["c", "d", "b", "a"]);
  });

  it("prefers the computed stock status, then reported items, then fewer days left", () => {
    const report = { id: "r", level: "running_low" as const, reported_at: "2026-01-01T00:00:00Z", supply_id: "x" };
    const sorted = sortByUrgency([
      supply("towels", "ok", { stock: { status: "low", days_left: 9, daily_use: 1, basis: "observed" } }),
      supply("soap", "low", { stock: { status: "low", days_left: 3, daily_use: 1, basis: "estimated" } }),
      supply("chalk", "low", { open_reports: [report] }),
      supply("tape", "ok"),
    ]);
    expect(sorted.map((item) => item.name)).toEqual(["chalk", "soap", "towels", "tape"]);
  });
});

describe("groupMachines", () => {
  it("groups by category, broken first, skipping archived", () => {
    const groups = groupMachines([
      { name: "Rower", category: "training", status: "working", archived_at: null },
      { name: "Bike", category: "training", status: "out_of_order", archived_at: null },
      { name: "Washer", category: "appliance", status: "working", archived_at: null },
      { name: "Old", category: "appliance", status: "working", archived_at: "2026-01-01T00:00:00Z" },
    ]);
    expect(groups.map((group) => [group.category, group.machines.map((machine) => machine.name)])).toEqual([
      ["training", ["Bike", "Rower"]],
      ["appliance", ["Washer"]],
    ]);
  });
});

describe("loggableEventKinds", () => {
  it("limits reporters to notes, issues and out of order", () => {
    expect(loggableEventKinds({ role: "janitor", capabilities: { report_inventory: "all" } })).toEqual(["note", "issue", "out_of_order"]);
    expect(loggableEventKinds({ role: "front_desk", capabilities: { manage_inventory: "all" } })).toContain("maintenance");
    expect(loggableEventKinds({ role: "member", capabilities: {} })).toEqual([]);
  });
});

describe("inventoryTab", () => {
  it("defaults to machines and hides the report from reporters", () => {
    expect(inventoryTab(null, false)).toBe("machines");
    expect(inventoryTab("supplies", false)).toBe("supplies");
    expect(inventoryTab("report", false)).toBe("machines");
    expect(inventoryTab("report", true)).toBe("report");
  });
});

describe("serviceState", () => {
  const today = new Date("2026-10-12T10:00:00Z");
  it("flags due and soon", () => {
    expect(serviceState({ service_due: true, next_service_on: null }, today)).toBe("due");
    expect(serviceState({ service_due: false, next_service_on: "2026-10-01" }, today)).toBe("due");
    expect(serviceState({ service_due: false, next_service_on: "2026-10-20" }, today)).toBe("soon");
    expect(serviceState({ service_due: false, next_service_on: "2026-12-20" }, today)).toBeNull();
    expect(serviceState({ next_service_on: null }, today)).toBeNull();
  });
});

describe("money", () => {
  it("formats euros and parses inputs", () => {
    expect(formatMoney(1250, "en")).toBe("€12.50");
    expect(formatMoney(null, "en")).toBe("—");
    expect(parseMoneyToCents("12,5")).toBe(1250);
    expect(parseMoneyToCents(" ")).toBeNull();
    expect(parseMoneyToCents("-3")).toBeNull();
  });

  it("scales bars safely", () => {
    expect(barPercent(50, 200)).toBe(25);
    expect(barPercent(5, 0)).toBe(0);
  });
});
