import { describe, expect, it } from "vitest";

import type { WorkoutFolder } from "@/api/workouts";

import { compareFolders, dayFolderBadge, folderDisplayName, folderKind, folderSubtreeIds, workoutIcon } from "./library-folders";

const folder = (id: string, name: string, system_key: string | null = null, parent_id: string | null = null): WorkoutFolder => ({
  id,
  name,
  parent_id,
  system_key,
});
const labels = { athletes: "Αθλητές", classes: "Τμήματα" };

describe("library folders", () => {
  it("recognises system folders by key", () => {
    expect(folderKind(folder("a", "Athletes", "athletes"))).toBe("athletes");
    expect(folderKind(folder("b", "Maria", "athlete:123"))).toBe("athlete");
    expect(folderKind(folder("c", "2026", "classes:2026"))).toBe("year");
    expect(folderKind(folder("d", "10", "classes:2026-10"))).toBe("month");
    expect(folderKind(folder("e", "2026-10-12", "classes:2026-10-12"))).toBe("day");
    expect(folderKind(folder("f", "Athletes"))).toBe("custom");
  });

  it("localises untouched system folder names and keeps coach renames", () => {
    expect(folderDisplayName(folder("a", "Athletes", "athletes"), labels)).toBe("Αθλητές");
    expect(folderDisplayName(folder("a", "Clients", "athletes"), labels)).toBe("Clients");
    expect(folderDisplayName(folder("d", "10", "classes:2026-10"), labels, "en")).toBe("October");
    expect(folderDisplayName(folder("e", "2026-10-12", "classes:2026-10-12"), labels, "en")).toBe("Mon, Oct 12");
    expect(folderDisplayName(folder("g", "Benchmarks"), labels)).toBe("Benchmarks");
  });

  it("orders Athletes and Classes first, then names naturally", () => {
    const sorted = [folder("1", "Zeta"), folder("2", "Classes", "classes"), folder("3", "10"), folder("4", "2"), folder("5", "Athletes", "athletes")]
      .sort(compareFolders)
      .map((item) => item.name);
    expect(sorted).toEqual(["Athletes", "Classes", "2", "10", "Zeta"]);
  });

  it("collects a folder subtree", () => {
    const folders = [folder("r", "Root"), folder("a", "A", null, "r"), folder("b", "B", null, "a"), folder("x", "X")];
    expect([...folderSubtreeIds(folders, "r")].sort()).toEqual(["a", "b", "r"]);
  });

  it("draws the real date on class-day folders", () => {
    expect(dayFolderBadge(folder("e", "2026-10-12", "classes:2026-10-12"), "en")).toEqual({ month: "Oct", day: "12" });
    expect(dayFolderBadge(folder("d", "10", "classes:2026-10"), "en")).toBeNull();
  });

  it("falls back to a barbell for unknown workout types", () => {
    expect(workoutIcon("gymnastics")).toBe("🤸");
    expect(workoutIcon("unknown")).toBe("🏋️");
  });
});
