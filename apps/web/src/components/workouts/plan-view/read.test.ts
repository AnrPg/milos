import { describe, expect, it } from "vitest";

import { backSquat, interrupted, restSection } from "./plan-fixtures";
import { isPlanSection, readPlanSections, readPlanSummary } from "./read";

describe("reading plan workouts", () => {
  it("reads the plan sections of a structured_plan workout only", () => {
    const sections = [{ id: "s1", name: "A", plan: backSquat() }, { id: "s2", name: "B", plan: { v: 2 } }];
    expect(readPlanSections({ authoring_mode: "structured_plan", sections }).map((section) => section.id)).toEqual(["s1"]);
    expect(readPlanSections({ authoring_mode: "free_text", sections })).toEqual([]);
    expect(isPlanSection({ v: 1, flow: "yoga", params: {}, blocks: [] })).toBe(false);
  });

  it("summarises a list's plan body, a full plan body, or the sections' plans", () => {
    expect(
      readPlanSummary({ body: { kind: "plan", sections: [{ name: "A", flow: "amrap", exercise_count: 3 }, { name: "x", flow: "nope" }] } }),
    ).toEqual([{ name: "A", flow: "amrap", exerciseCount: 3 }]);
    expect(readPlanSummary({ body: { kind: "plan", sections: [{ id: "1", name: "B", plan: interrupted() }] } })).toEqual([
      { name: "B", flow: "for_time", exerciseCount: 2 },
    ]);
    expect(
      readPlanSummary({ authoring_mode: "structured_plan", sections: [{ name: "C", plan: backSquat() }, { name: "Rest", plan: restSection() }] }),
    ).toEqual([
      { name: "C", flow: "sets", exerciseCount: 1 },
      { name: "Rest", flow: "rest", exerciseCount: 0 },
    ]);
    expect(readPlanSummary({ body: { kind: "free_text" }, authoring_mode: "free_text", sections: [] })).toEqual([]);
  });
});
