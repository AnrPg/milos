import fs from "node:fs";
import path from "node:path";

import {
  DEFAULT_ANATOMY_PALETTE,
  focusBounds,
  highlightsByRole,
  highlightsKey,
  paletteKey,
  parseAtlasNodeName,
  readAnatomyPalette,
  resolvePick,
  roleByTa2,
  type AtlasIndex,
} from "./figure";

const index = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, "../../../public/anatomy/v1/index.json"), "utf8"),
) as AtlasIndex;

describe("parseAtlasNodeName", () => {
  it("reads atlas names before and after three.js sanitising", () => {
    expect(parseAtlasNodeName("ta2-2453.l")).toEqual({ ta2: "2453", side: "l" });
    expect(parseAtlasNodeName("ta2-2453l")).toEqual({ ta2: "2453", side: "l" });
    expect(parseAtlasNodeName("ta2-2357r")).toEqual({ ta2: "2357", side: "r" });
    expect(parseAtlasNodeName("ta2-2327m")).toEqual({ ta2: "2327", side: "m" });
    expect(parseAtlasNodeName("ta2-2327")).toEqual({ ta2: "2327", side: null });
  });

  it("rejects other names", () => {
    expect(parseAtlasNodeName("Scene")).toBeNull();
    expect(parseAtlasNodeName("ta2-2453x")).toBeNull();
    expect(parseAtlasNodeName("ta2-")).toBeNull();
  });
});

describe("roleByTa2", () => {
  it("maps groups and heads to their meshes", () => {
    const roles = roleByTa2({ quadriceps: "primary", "deltoid-anterior": "secondary" });
    expect(roles.get("2614")).toBe("primary");
    expect(roles.get("2620")).toBe("primary");
    expect(roles.get("2453")).toBe("secondary");
    expect(roles.has("2454")).toBe(false);
  });

  it("lets the stronger role win and felt win over the plan", () => {
    const roles = roleByTa2({ deltoid: "stabilizer", "deltoid-lateral": "primary", "deltoid-posterior": "secondary" });
    expect(roles.get("2453")).toBe("stabilizer");
    expect(roles.get("2454")).toBe("primary");
    expect(roles.get("2455")).toBe("secondary");
    expect(roleByTa2({ glutes: "primary", "gluteus-medius": "felt" }).get("2599")).toBe("felt");
    expect(roleByTa2({ "gluteus-medius": "felt", glutes: "primary" }).get("2599")).toBe("felt");
  });

  it("ignores unknown ids and roles", () => {
    expect(roleByTa2({ "not-a-muscle": "primary" }).size).toBe(0);
    expect(roleByTa2({ glutes: "bogus" as never }).size).toBe(0);
  });
});

describe("highlight helpers", () => {
  it("builds an order-independent key without unknown ids", () => {
    expect(highlightsKey({ glutes: "primary", deltoid: "felt", nope: "primary" })).toBe("deltoid:felt,glutes:primary");
    expect(highlightsKey({ deltoid: "felt", glutes: "primary" })).toBe(highlightsKey({ glutes: "primary", deltoid: "felt" }));
  });

  it("groups highlighted ids by role in tree order", () => {
    expect(highlightsByRole({ hamstrings: "secondary", quadriceps: "primary", glutes: "primary" })).toEqual([
      ["primary", ["glutes", "quadriceps"]],
      ["secondary", ["hamstrings"]],
    ]);
  });
});

describe("resolvePick", () => {
  it("picks the group first, then the head under the pointer", () => {
    const first = resolvePick("2454", null);
    expect(first).toEqual({ nodeId: "deltoid", level: "group" });
    const second = resolvePick("2454", first);
    expect(second).toEqual({ nodeId: "deltoid-lateral", level: "head" });
    expect(resolvePick("2455", second)).toEqual({ nodeId: "deltoid-posterior", level: "head" });
  });

  it("starts over on another group", () => {
    expect(resolvePick("2614", { nodeId: "deltoid-lateral", level: "head" })).toEqual({ nodeId: "quadriceps", level: "group" });
  });

  it("keeps a group without heads at group level", () => {
    const first = resolvePick("2231", null);
    expect(first).toEqual({ nodeId: "latissimus-dorsi", level: "group" });
    expect(resolvePick("2231", first)).toEqual({ nodeId: "latissimus-dorsi", level: "group" });
  });

  it("ignores meshes outside the taxonomy", () => {
    expect(resolvePick("2045", null)).toBeNull();
  });
});

describe("focusBounds", () => {
  it("spans both sides and tells front from back", () => {
    const quads = focusBounds("quadriceps", index);
    expect(quads).not.toBeNull();
    expect(quads!.center[0]).toBeCloseTo(0, 2);
    expect(quads!.size[0]).toBeGreaterThan(0.2);
    expect(quads!.posterior).toBe(false);
    expect(focusBounds("glutes", index)!.posterior).toBe(true);
    expect(focusBounds("deltoid-posterior", index)!.posterior).toBe(true);
    expect(focusBounds("unknown", index)).toBeNull();
  });
});

describe("readAnatomyPalette", () => {
  afterEach(() => document.documentElement.removeAttribute("style"));

  it("reads the CSS tokens and falls back to defaults", () => {
    document.documentElement.style.setProperty("--anatomy-primary", "#112233");
    const palette = readAnatomyPalette();
    expect(palette.primary).toBe("#112233");
    expect(palette.felt).toBe(DEFAULT_ANATOMY_PALETTE.felt);
    expect(paletteKey(palette)).toContain("#112233");
  });
});
