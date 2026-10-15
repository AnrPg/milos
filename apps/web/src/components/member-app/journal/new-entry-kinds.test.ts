import { describe, expect, it } from "vitest";

import { newEntryKinds } from "./NewEntrySheet";

describe("newEntryKinds", () => {
  it("offers only the entry kinds that exist today, technique videos when the package allows", () => {
    expect(newEntryKinds({ canRequestFormReview: false })).toEqual(["workout", "pr", "injury", "review"]);
    expect(newEntryKinds({ canRequestFormReview: true })).toEqual(["workout", "pr", "injury", "formReview", "review"]);
  });
});
