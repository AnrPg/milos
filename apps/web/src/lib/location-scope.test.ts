import { describe, expect, it } from "vitest";

import {
  canGrantScope,
  coversLocation,
  hasSeveralBranches,
  membershipLocationScope,
  sameScope,
  toLocationScope,
  toPayload,
} from "./location-scope";

describe("location scope (ADR-186)", () => {
  it("reads the payload: no payload or the «all» flag means every branch", () => {
    expect(toLocationScope(null)).toBe("all");
    expect(toLocationScope({ all_locations: true, location_ids: ["a"] })).toBe("all");
    expect(toLocationScope({ all_locations: false, location_ids: ["b", "a", "b"] })).toEqual(["a", "b"]);
    expect(membershipLocationScope({})).toBe("all");
    expect(toPayload(["a"])).toEqual({ all_locations: false, location_ids: ["a"] });
    expect(toPayload("all")).toEqual({ all_locations: true, location_ids: [] });
  });

  it("covers branches and never grants wider than the granter", () => {
    expect(coversLocation("all", null)).toBe(true);
    expect(coversLocation(["a"], "a")).toBe(true);
    expect(coversLocation(["a"], "b")).toBe(false);
    expect(coversLocation(["a"], null)).toBe(false);
    expect(canGrantScope("all", ["a"])).toBe(true);
    expect(canGrantScope(["a", "b"], ["b"])).toBe(true);
    expect(canGrantScope(["a"], "all")).toBe(false);
    expect(canGrantScope(["a"], ["a", "b"])).toBe(false);
    expect(canGrantScope(["a"], [])).toBe(false);
  });

  it("compares scopes regardless of order and counts active branches", () => {
    expect(sameScope(["b", "a"], ["a", "b"])).toBe(true);
    expect(sameScope("all", ["a"])).toBe(false);
    expect(hasSeveralBranches([{ archived_at: null }, { archived_at: "2026-10-01" }])).toBe(false);
    expect(hasSeveralBranches([{ archived_at: null }, { archived_at: null }])).toBe(true);
    expect(hasSeveralBranches(undefined)).toBe(false);
  });
});
