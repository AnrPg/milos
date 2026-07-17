import { describe, expect, it } from "vitest";

import { chronologicalPRHistory } from "@/components/pantheon/pr-history";

const current = {
  id: "pr-1",
  user_id: "user-1",
  name: "Back squat",
  current_score: 120,
  unit: "kg" as const,
  higher_is_better: true,
  beaten_on: "2026-07-15",
  supporting_metrics: {},
  notes: null,
  inserted_at: "2026-07-01T00:00:00Z",
  updated_at: "2026-07-15T00:00:00Z",
};

describe("chronologicalPRHistory", () => {
  it("includes the current result and orders every result from newest to oldest", () => {
    const entries = chronologicalPRHistory(current, [
      { id: "oldest", pr_record_id: "pr-1", score: 100, beaten_on: "2026-06-01", supporting_metrics: {}, notes: null, inserted_at: "2026-06-01T00:00:00Z" },
      { id: "middle", pr_record_id: "pr-1", score: 110, beaten_on: "2026-07-01", supporting_metrics: {}, notes: null, inserted_at: "2026-07-01T00:00:00Z" },
    ]);

    expect(entries.map((entry) => entry.id)).toEqual(["current-pr-1", "middle", "oldest"]);
  });
});
