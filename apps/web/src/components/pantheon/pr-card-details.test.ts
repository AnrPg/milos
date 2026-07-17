import { describe, expect, it, vi } from "vitest";

import { formatPRCardDetails } from "@/components/pantheon/pr-card-details";

const translate = vi.fn((key: string) => key);

describe("formatPRCardDetails", () => {
  it("renders each supporting metric as localized, secondary card metadata", () => {
    expect(
      formatPRCardDetails(
        { reps: 5, load_kg: 80, variation: "strict" },
        translate,
      ),
    ).toBe("semanticLoad (kg1389845): 80 · reps702045f: 5 · variation15920a4: strict");
  });

  it("returns no detail line when a PR has no supporting metrics", () => {
    expect(formatPRCardDetails({}, translate)).toBe("");
  });
});
