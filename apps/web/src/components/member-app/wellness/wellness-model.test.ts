import { describe, expect, it } from "vitest";

import type { Craving, WellnessDay, WellnessEntry } from "@/api/wellness";

import {
  addDays,
  editable,
  fullOrder,
  glasses,
  mealSlots,
  mealsBySlot,
  moveItem,
  planFit,
  nightInstants,
  occurredAt,
  openCraving,
  portionBars,
  portionsFromGrams,
  sleepMinutes,
  stepPortion,
  usualNight,
  visibleItems,
  weekDots,
  weekOf,
  weekRows,
} from "./wellness-model";

const entry = (overrides: Partial<WellnessEntry>) =>
  ({
    id: "e1",
    kind: "sleep",
    occurred_on: "2026-10-20",
    occurred_at: "2026-10-20T07:00:00Z",
    corrected: false,
    journal_visibility: "private",
    value: {},
    ...overrides,
  }) as WellnessEntry;

const day = (date: string, water: string, sleep: string, meals: string, cravings = 0) =>
  ({
    date,
    water: { status: water },
    sleep: { status: sleep },
    meals: { status: meals },
    cravings: { count: cravings },
  }) as unknown as WellnessDay;

describe("days", () => {
  it("steps across month ends", () => {
    expect(addDays("2026-10-31", 1)).toBe("2026-11-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("lets the last seven days be filled in, never the future", () => {
    expect(editable("2026-10-20", "2026-10-20")).toBe(true);
    expect(editable("2026-10-13", "2026-10-20")).toBe(true);
    expect(editable("2026-10-12", "2026-10-20")).toBe(false);
    expect(editable("2026-10-21", "2026-10-20")).toBe(false);
  });

  it("builds the Monday-to-Sunday week and moves it by weeks", () => {
    expect(weekOf("2026-10-20")).toMatchObject({ from: "2026-10-19", to: "2026-10-25" });
    expect(weekOf("2026-10-25")).toMatchObject({ from: "2026-10-19", to: "2026-10-25" });
    expect(weekOf("2026-10-20", -1).dates).toHaveLength(7);
    expect(weekOf("2026-10-20", -1).from).toBe("2026-10-12");
  });

  it("back-fills a past day at now's time of day and leaves today to the server", () => {
    const now = new Date(2026, 9, 20, 18, 30);
    expect(occurredAt("2026-10-20", now)).toBeUndefined();
    expect(new Date(occurredAt("2026-10-18", now)!).getHours()).toBe(18);
  });
});

describe("item order", () => {
  it("keeps the member's order and appends items never placed", () => {
    expect(fullOrder(["mood", "water"])).toEqual(["mood", "water", "sleep", "meals", "plan"]);
  });

  it("hides turned-off items without losing their place", () => {
    expect(visibleItems({ item_order: ["meals", "water"], hidden_items: ["water", "plan"] })).toEqual([
      "meals",
      "sleep",
      "mood",
    ]);
  });

  it("moves an item one place and stops at the ends", () => {
    expect(moveItem([], "sleep", -1)).toEqual(["sleep", "water", "meals", "plan", "mood"]);
    expect(moveItem([], "water", -1)).toEqual(["water", "sleep", "meals", "plan", "mood"]);
    expect(moveItem([], "mood", 1)).toEqual(["water", "sleep", "meals", "plan", "mood"]);
  });

  it("keeps the cravings row even when items are hidden", () => {
    expect(weekRows(["water", "meals"])).toEqual(["sleep", "cravings"]);
  });
});

describe("water and sleep", () => {
  it("counts glasses against the member's own goal", () => {
    expect(glasses({ ml: 750, glass_ml: 250, goal_ml: 2000 } as WellnessDay["water"])).toEqual({ filled: 3, goal: 8 });
    expect(glasses({ ml: 0, glass_ml: 330, goal_ml: 2000 } as WellnessDay["water"])).toEqual({ filled: 0, goal: 7 });
  });

  it("measures a night across midnight", () => {
    expect(sleepMinutes("23:30", "07:00")).toBe(450);
    expect(sleepMinutes("01:00", "08:15")).toBe(435);
    expect(sleepMinutes("07:00", "07:00")).toBe(1440);
  });

  it("puts the bedtime on the evening before unless it is after midnight", () => {
    const late = nightInstants("2026-10-20", "23:00", "07:00");
    expect(new Date(late.bed_at).getDate()).toBe(19);
    expect(new Date(late.wake_at).getDate()).toBe(20);
    const early = nightInstants("2026-10-20", "00:30", "07:00");
    expect(new Date(early.bed_at).getDate()).toBe(20);
  });

  it("suggests the latest full night as the usual one, naps aside", () => {
    const bed = new Date(2026, 9, 18, 22, 45).toISOString();
    const wake = new Date(2026, 9, 19, 6, 30).toISOString();
    const nap = entry({ occurred_at: "2026-10-19T14:00:00Z", value: { nap: true, minutes: 20 } });
    const night = entry({ occurred_at: "2026-10-19T06:30:00Z", value: { bed_at: bed, wake_at: wake } });
    expect(usualNight([nap, night])).toEqual({ bed: "22:45", wake: "06:30" });
    expect(usualNight([])).toEqual({ bed: "23:00", wake: "07:00" });
  });
});

describe("meals and portions", () => {
  it("uses the plan's meal slots, else the three meals and a snack", () => {
    expect(mealSlots(null)).toEqual(["breakfast", "lunch", "dinner", "snack"]);
    expect(mealSlots({ meal_slots: ["breakfast", "post_workout"] } as never)).toEqual(["breakfast", "post_workout"]);
  });

  it("groups meals by slot and keeps the rest apart", () => {
    const lunch = entry({ id: "l", kind: "meal", value: { slot: "lunch" } });
    const late = entry({ id: "x", kind: "meal", value: { slot: "late_snack" } });
    const grouped = mealsBySlot([lunch, late], ["breakfast", "lunch"]);
    expect(grouped.named[1].meals).toEqual([lunch]);
    expect(grouped.other).toEqual([late]);
  });

  it("fills the bars against the plan's portions only", () => {
    expect(portionBars({ protein: 2 }, { protein: 4, veg: 3 } as never)).toEqual([
      { key: "protein", logged: 2, target: 4, ratio: 0.5 },
      { key: "veg", logged: 0, target: 3, ratio: 0 },
    ]);
    expect(portionBars({ protein: 6 }, { protein: 4 } as never)[0].ratio).toBe(1);
    expect(portionBars({}, undefined)).toEqual([]);
  });

  it("steps portions by halves between 0 and 10", () => {
    expect(stepPortion(0, -0.5)).toBe(0);
    expect(stepPortion(1, 0.5)).toBe(1.5);
    expect(stepPortion(10, 0.5)).toBe(10);
  });

  it("derives hand portions from grams as the API does", () => {
    expect(portionsFromGrams({ protein_grams: 160, carbs_grams: 200, fat_grams: 70 })).toEqual({
      protein: 6.5,
      carbs: 8,
      fat: 7,
    });
    expect(portionsFromGrams({ protein_grams: null, carbs_grams: 0 })).toEqual({});
  });
});

describe("week card and cravings", () => {
  it("draws one dot per day: full on target, half when partly, warm for a craving", () => {
    const dates = ["2026-10-19", "2026-10-20", "2026-10-21"];
    const dots = weekDots([day("2026-10-19", "full", "partial", "none", 2), day("2026-10-20", "none", "full", "full")], dates);
    expect(dots.water).toEqual(["full", "empty", "empty"]);
    expect(dots.sleep).toEqual(["half", "full", "empty"]);
    expect(dots.meals).toEqual(["empty", "full", "empty"]);
    expect(dots.cravings).toEqual(["warm", "empty", "empty"]);
  });

  it("treats a craving as open until it has an outcome other than ongoing", () => {
    expect(openCraving({ outcome: null } as unknown as Craving)).toBe(true);
    expect(openCraving({ outcome: "ongoing" } as unknown as Craving)).toBe(true);
    expect(openCraving({ outcome: "rode_it_out" } as unknown as Craving)).toBe(false);
  });
});

describe("planFit", () => {
  const meal = (value: Record<string, unknown>) => ({ kind: "meal", value }) as unknown as WellnessEntry;

  it("reads the known fits and ignores unknown or missing ones", () => {
    expect(planFit(meal({ plan_fit: "in_plan" }))).toBe("in_plan");
    expect(planFit(meal({ plan_fit: "off_plan" }))).toBe("off_plan");
    expect(planFit(meal({ plan_fit: "on_plan" }))).toBeNull();
    expect(planFit(meal({}))).toBeNull();
  });
});
