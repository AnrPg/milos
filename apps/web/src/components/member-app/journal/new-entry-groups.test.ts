import { describe, expect, it } from "vitest";

import { newEntryGroups } from "./NewEntrySheet";

describe("newEntryGroups", () => {
  it("groups the entry kinds that exist today as the feature map does", () => {
    expect(newEntryGroups({ canRequestFormReview: false })).toEqual([
      { group: "training", kinds: ["workout", "pr"] },
      { group: "body", kinds: ["measure"] },
      { group: "wellbeing", kinds: ["wellness", "checkIn", "craving", "support", "injury"] },
      { group: "coach", kinds: ["review"] },
      { group: "note", kinds: ["note"] },
    ]);
  });

  it("leaves out Νερό · Ύπνος · Γεύμα when all three are turned off in Ευεξία", () => {
    expect(
      newEntryGroups({ canRequestFormReview: false, showWellness: false }).find((entry) => entry.group === "wellbeing")
        ?.kinds,
    ).toEqual(["checkIn", "craving", "support", "injury"]);
  });

  it("leaves Μέτρηση out when Σώμα is switched off", () => {
    expect(newEntryGroups({ canRequestFormReview: false, body: false }).map((entry) => entry.group)).not.toContain("body");
  });

  it("adds technique videos to Coach when the package allows them", () => {
    expect(newEntryGroups({ canRequestFormReview: true }).find((entry) => entry.group === "coach")?.kinds).toEqual([
      "formReview",
      "review",
    ]);
  });
});
