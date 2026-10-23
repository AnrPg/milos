import { afterEach, describe, expect, it } from "vitest";

import { FIRST_RUN, markFirstRunDone, needsFirstRun, safeNext } from "@/lib/first-run";

describe("first-run gate", () => {
  afterEach(() => window.sessionStorage.clear());

  it("greets a new account once, never a vendor", () => {
    expect(needsFirstRun({ id: "u1", completed_tours: [] })).toBe(true);
    expect(needsFirstRun({ id: "u1", completed_tours: [FIRST_RUN] })).toBe(false);
    expect(needsFirstRun({ id: "u1", vendor: true, completed_tours: [] })).toBe(false);
    expect(needsFirstRun(null)).toBe(false);
  });

  it("stops asking in this session as soon as it is finished", () => {
    markFirstRunDone("u1");
    expect(needsFirstRun({ id: "u1", completed_tours: [] })).toBe(false);
    expect(needsFirstRun({ id: "u2", completed_tours: [] })).toBe(true);
  });

  it("only follows same-site next paths", () => {
    expect(safeNext("/join/box")).toBe("/join/box");
    expect(safeNext("//evil.example")).toBe("/");
    expect(safeNext("https://evil.example")).toBe("/");
    expect(safeNext(null)).toBe("/");
  });
});
