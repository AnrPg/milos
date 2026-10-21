import { describe, expect, it } from "vitest";

import {
  aboutNodeId,
  atlasChildren,
  atlasHref,
  atlasPath,
  coverageLevel,
  coverageSets,
  exploreHighlights,
  feltCount,
  heatHighlights,
  indexCoverage,
  isAtlasRange,
} from "./atlas";
import { roleByTa2 } from "./figure";

const index = indexCoverage([
  { id: "thighs", sets: 8, level: "high" },
  { id: "quadriceps", sets: 6.5, level: "medium", felt: 2 },
  { id: "rectus-femoris", sets: 6.5, level: "medium" },
  { id: "vastus-lateralis", sets: 2, level: "low" },
  { id: "hamstrings", sets: 1, level: "low" },
  { id: "deltoid-anterior", sets: 4, level: "bogus" },
]);

describe("atlas navigation", () => {
  it("builds the breadcrumb path from the region down", () => {
    expect(atlasPath("rectus-femoris").map((node) => node.id)).toEqual(["thighs", "quadriceps", "rectus-femoris"]);
    expect(atlasPath("thighs").map((node) => node.id)).toEqual(["thighs"]);
    expect(atlasPath(null)).toEqual([]);
    expect(atlasPath("spleen")).toEqual([]);
  });

  it("lists regions for the body, groups for a region, heads for a group", () => {
    expect(atlasChildren(null).every((node) => node.kind === "region")).toBe(true);
    expect(atlasChildren("thighs").map((node) => node.id)).toEqual(["quadriceps", "hamstrings", "adductors"]);
    expect(atlasChildren("latissimus-dorsi")).toEqual([]);
  });

  it("heads reuse their group's description; regions have none", () => {
    expect(aboutNodeId("rectus-femoris")).toBe("quadriceps");
    expect(aboutNodeId("quadriceps")).toBe("quadriceps");
    expect(aboutNodeId("thighs")).toBeNull();
  });

  it("links to the atlas, on a node when it is known", () => {
    expect(atlasHref("glutes")).toBe("/journal/atlas?node=glutes");
    expect(atlasHref("nope")).toBe("/journal/atlas");
    expect(atlasHref()).toBe("/journal/atlas");
  });

  it("knows its ranges", () => {
    expect(isAtlasRange("12w")).toBe(true);
    expect(isAtlasRange("6m")).toBe(false);
  });
});

describe("coverage lookups", () => {
  it("tolerates missing nodes and fields", () => {
    expect(coverageLevel(index, "quadriceps")).toBe("medium");
    expect(coverageLevel(index, "glutes")).toBe("none");
    expect(coverageLevel(index, "deltoid-anterior")).toBe("none");
    expect(coverageSets(index, "quadriceps")).toBe(6.5);
    expect(coverageSets(index, "glutes")).toBe(0);
    expect(feltCount(index, "quadriceps")).toBe(2);
    expect(feltCount(index, "thighs")).toBe(0);
    expect(indexCoverage(undefined).size).toBe(0);
  });
});

describe("figure highlights", () => {
  it("explore mode paints the selection at its level", () => {
    expect(exploreHighlights(null)).toEqual({});
    expect(exploreHighlights("thighs")).toEqual({ thighs: "secondary" });
    expect(exploreHighlights("quadriceps")).toEqual({ quadriceps: "primary" });
    expect(exploreHighlights("rectus-femoris")).toEqual({ quadriceps: "secondary", "rectus-femoris": "primary" });
  });

  it("heat mode paints groups by level and opens the selected group's heads", () => {
    expect(heatHighlights(index, null)).toEqual({ quadriceps: "heat-medium", hamstrings: "heat-low" });
    expect(heatHighlights(index, "quadriceps")).toEqual({
      "rectus-femoris": "heat-medium",
      "vastus-lateralis": "heat-low",
      hamstrings: "heat-low",
    });
    // A selected head opens its group too.
    expect(heatHighlights(index, "vastus-lateralis")).toEqual(heatHighlights(index, "quadriceps"));
  });

  it("heat roles reach the meshes like goal roles", () => {
    const roles = roleByTa2(heatHighlights(index, null));
    expect(roles.get("2614")).toBe("heat-medium");
    expect(roles.get("2639")).toBe("heat-low");
    expect(roles.has("2598")).toBe(false);
  });
});
