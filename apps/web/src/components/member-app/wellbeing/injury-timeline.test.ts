import { describe, expect, it } from "vitest";

import { timelinePositions } from "./injury-timeline";

describe("timelinePositions", () => {
  it("spreads events by time from the report to the latest change", () => {
    expect(
      timelinePositions([
        { occurred_at: "2026-10-01T00:00:00Z" },
        { occurred_at: "2026-10-04T00:00:00Z" },
        { occurred_at: "2026-10-11T00:00:00Z" },
      ]),
    ).toEqual([0, 0.3, 1]);
  });

  it("spaces events evenly when they share a timestamp", () => {
    expect(timelinePositions([{ occurred_at: "2026-10-01T00:00:00Z" }])).toEqual([0]);
    expect(timelinePositions([{ occurred_at: "2026-10-01T00:00:00Z" }, { occurred_at: "2026-10-01T00:00:00Z" }])).toEqual([0, 1]);
    expect(timelinePositions([])).toEqual([]);
  });
});
