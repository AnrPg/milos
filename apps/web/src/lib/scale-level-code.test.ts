import { describe, expect, it } from "vitest";

import { newLevelCode, slugifyLevelName } from "./scale-level-code";

describe("slugifyLevelName", () => {
  it("keeps the codes the default levels use", () => {
    expect(slugifyLevelName("Scaled")).toBe("scaled");
    expect(slugifyLevelName("Rx")).toBe("rx");
    expect(slugifyLevelName("Rx+")).toBe("rx-plus");
  });

  it("transliterates Greek and Cyrillic names into the code alphabet the API accepts", () => {
    expect(slugifyLevelName("Αρχάριοι")).toBe("archarioi");
    expect(slugifyLevelName("Μέτριο επίπεδο")).toBe("metrio-epipedo");
    expect(slugifyLevelName("Начинающий")).toBe("nachinayushtii");
  });

  it("returns only a-z0-9 words joined by single hyphens", () => {
    expect(slugifyLevelName("  Élite -- (Pro)! ")).toBe("elite-pro");
    expect(slugifyLevelName("مبتدئ")).toBe("");
  });
});

describe("newLevelCode", () => {
  it("avoids codes already taken", () => {
    expect(newLevelCode("Rx", ["rx"], 4)).toBe("rx-2");
    expect(newLevelCode("Rx", ["rx", "rx-2"], 4)).toBe("rx-3");
  });

  it("falls back to level-N when the name has no letters it can spell", () => {
    expect(newLevelCode("مبتدئ", [], 4)).toBe("level-4");
    expect(newLevelCode("", [], 2)).toBe("level-2");
  });
});
