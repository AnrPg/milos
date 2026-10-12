import { describe, expect, it } from "vitest";

import type { PRTimelineEntry } from "@/api/content";
import { formatPRScore, groupPRTimelineByMonth, prImprovement } from "@/components/client/pr-timeline";

function entry(overrides: Partial<PRTimelineEntry>): PRTimelineEntry {
  return {
    id: "h1",
    pr_record_id: "pr1",
    name: "Back squat",
    unit: "kg",
    higher_is_better: true,
    beaten_on: "2026-10-12",
    score: 120,
    previous_score: 115,
    change: 5,
    ...overrides,
  };
}

describe("PR timeline helpers", () => {
  it("groups by month, newest first", () => {
    const months = groupPRTimelineByMonth([
      entry({ id: "a", beaten_on: "2026-09-03" }),
      entry({ id: "b", beaten_on: "2026-10-12" }),
      entry({ id: "c", beaten_on: "2026-10-01" }),
    ]);
    expect(months.map((month) => [month.month, month.entries.map((value) => value.id)])).toEqual([
      ["2026-10", ["b", "c"]],
      ["2026-09", ["a"]],
    ]);
  });

  it("formats scores like the Pantheon", () => {
    expect(formatPRScore(120, "kg")).toBe("120");
    expect(formatPRScore(102.5, "kg")).toBe("102.50");
    expect(formatPRScore(305, "mins_secs")).toBe("05:05");
  });

  it("describes improvements, first records and time saved", () => {
    expect(prImprovement(entry({}))).toEqual({ kind: "amount", text: "+5" });
    expect(prImprovement(entry({ previous_score: null, change: null }))).toEqual({ kind: "first" });
    expect(
      prImprovement(entry({ unit: "mins_secs", higher_is_better: false, score: 290, previous_score: 305, change: -15 })),
    ).toEqual({ kind: "time_saved", text: "00:15" });
    expect(prImprovement(entry({ unit: "reps", higher_is_better: false, score: 8, previous_score: 10 }))).toEqual({
      kind: "amount",
      text: "−2",
    });
  });
});
