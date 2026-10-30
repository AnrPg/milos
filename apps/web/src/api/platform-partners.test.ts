import { describe, expect, it } from "vitest";

import { groupReportsByPerson, suggestionTotals, type PlatformReport, type SuggestionStats } from "./platform-partners";

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });

function report(id: string, target: string, createdAt: string, reason: PlatformReport["reason"] = "fake"): PlatformReport {
  return {
    id,
    reason,
    note: null,
    status: "open",
    created_at: createdAt,
    decided_at: null,
    decision_note: null,
    reports_on_target: 0,
    reporter: person(`reporter-${id}`, "Reporter"),
    target: person(target, target.toUpperCase()),
  };
}

describe("groupReportsByPerson", () => {
  it("gathers reports per person, the most reported first, then the oldest", () => {
    const groups = groupReportsByPerson([
      report("1", "a", "2026-10-29T10:00:00Z"),
      report("2", "b", "2026-10-28T10:00:00Z", "minor"),
      report("3", "c", "2026-10-27T10:00:00Z"),
      report("4", "b", "2026-10-30T10:00:00Z"),
    ]);
    expect(groups.map((group) => [group.target.id, group.reports.map((row) => row.id)])).toEqual([
      ["b", ["2", "4"]],
      ["c", ["3"]],
      ["a", ["1"]],
    ]);
  });
});

describe("suggestionTotals", () => {
  const stats: SuggestionStats = {
    since: "2026-10-01",
    days: [
      { day: "2026-10-28", shown: 10, proposed: 2, booked_together: 0, feedback: 1 },
      { day: "2026-10-29", shown: 30, proposed: 8, booked_together: 0, feedback: 3 },
    ],
    feedback_reasons: { bad_time: 2, not_near: 1, other: 0, wrong_level: 1 },
  };

  it("sums the days and gives the proposed share of shown", () => {
    expect(suggestionTotals(stats)).toEqual({ shown: 40, proposed: 10, booked_together: 0, feedback: 4, proposedShare: 25 });
  });

  it("has no share without anything shown", () => {
    expect(suggestionTotals({ ...stats, days: [] }).proposedShare).toBeNull();
  });
});
