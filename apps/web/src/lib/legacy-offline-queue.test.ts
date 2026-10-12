import { describe, expect, it } from "vitest";

import { applyLegacyCheckoffs } from "./legacy-offline-queue";

describe("applyLegacyCheckoffs", () => {
  it("replays queued operations oldest first", () => {
    expect(
      applyLegacyCheckoffs(["a"], [
        { add: ["b"], remove: [] },
        { add: ["c"], remove: ["a"] },
        { add: [], remove: ["b"] },
      ]),
    ).toEqual(["c"]);
  });
});
