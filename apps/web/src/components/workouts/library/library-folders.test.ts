import { describe, expect, it } from "vitest";

import type { WorkoutFolder } from "@/api/workouts";

import {
  compareFolders,
  dayFolderBadge,
  folderDisplayName,
  folderIcon,
  folderKind,
  folderSubtreeIds,
  resolveWorkoutIcon,
  ruleIcon,
  workoutIcon,
} from "./library-folders";

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
    expect(folderKind(folder("v", "Variations for member", "member_variations"))).toBe("memberVariations");
    expect(folderKind(folder("w", "Maria", "member_variations:123"))).toBe("memberVariation");
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

  it("picks icons from keywords in English and Greek, ignoring accents and case", () => {
    expect(ruleIcon("Deload day")).toBe("💆");
    expect(ruleIcon("Mobility flow")).toBe("🧘");
    expect(ruleIcon("Murph")).toBe("🎖️");
    expect(ruleIcon("Fran")).toBe("🏆");
    expect(ruleIcon("Partner chipper")).toBe("🤝");
    expect(ruleIcon("5k run")).toBe("🏃");
    expect(ruleIcon("Back squat 5x5")).toBe("🏋️");
    expect(ruleIcon("Engine builder")).toBe("🫀");
    expect(ruleIcon("EMOM 20")).toBe("⏱️");
    expect(ruleIcon("Αποφόρτιση")).toBe("💆");
    expect(ruleIcon("ΚΙΝΗΤΙΚΟΤΗΤΑ")).toBe("🧘");
    expect(ruleIcon("Ενδυνάμωση ποδιών")).toBe("🦵");
    expect(ruleIcon("Monday")).toBeNull();
    expect(ruleIcon("Spring open gym")).toBeNull();
    expect(ruleIcon("Ring rows")).toBe("🚣");
  });

  it("prefers a stored icon, then rules, then the workout type", () => {
    expect(resolveWorkoutIcon({ icon: "🎉", title: "Deload day", type: "recovery" })).toBe("🎉");
    expect(resolveWorkoutIcon({ icon: null, title: "Deload day", type: "crossfit" })).toBe("💆");
    expect(resolveWorkoutIcon({ icon: null, title: "Monday", type: "gymnastics" })).toBe("🤸");
  });

  it("gives folders rule icons: system folders by kind, coach folders by name", () => {
    expect(folderIcon(folder("a", "Clients", "athletes"))).toBe("👥");
    expect(folderIcon(folder("b", "Benchmarks"))).toBe("🏆");
    expect(folderIcon(folder("c", "Misc"))).toBe("📁");
  });

  it("falls back to a barbell for unknown workout types", () => {
    expect(workoutIcon("gymnastics")).toBe("🤸");
    expect(workoutIcon("unknown")).toBe("🏋️");
  });
});
