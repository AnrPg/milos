import { describe, expect, it } from "vitest";

import { newEntryGroups } from "./NewEntrySheet";

describe("newEntryGroups", () => {
  it("groups the entry kinds that exist today as the feature map does", () => {
    expect(newEntryGroups({ canRequestFormReview: false })).toEqual([
      { group: "training", kinds: ["workout", "pr"] },
      { group: "wellbeing", kinds: ["checkIn", "injury"] },
      { group: "coach", kinds: ["review"] },
      { group: "note", kinds: ["note"] },
    ]);
  });

  it("adds technique videos to Coach when the package allows them", () => {
    expect(newEntryGroups({ canRequestFormReview: true }).find((entry) => entry.group === "coach")?.kinds).toEqual([
      "formReview",
      "review",
    ]);
  });
});
