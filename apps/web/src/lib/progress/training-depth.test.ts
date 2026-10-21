import { describe, expect, it } from "vitest";

import { formatRatio, isLoadBand, loadBars, QUALITY_IDS, qualityScores, radarPoint, radarPolygon, topQualities } from "./training-depth";

describe("training depth helpers (ADR-165)", () => {
  it("keeps the ten radar axes in order and tolerates missing or bad rows", () => {
    const rows = qualityScores([
      { id: "strength", score: 1, sets: 10, felt: 2 },
      { id: "stamina", score: 1.7, sets: 4 },
      { id: "nonsense", score: 0.4 },
    ]);
    expect(rows.map((row) => row.id)).toEqual([...QUALITY_IDS]);
    expect(rows.find((row) => row.id === "strength")).toEqual({ id: "strength", score: 1, sets: 10, felt: 2 });
    // Clamped to 0..1; missing fields are zero.
    expect(rows.find((row) => row.id === "stamina")).toEqual({ id: "stamina", score: 1, sets: 4, felt: 0 });
    expect(rows.find((row) => row.id === "balance")?.score).toBe(0);
    expect(qualityScores(undefined)).toHaveLength(10);
  });

  it("lists the most-trained and most-felt qualities with anything at all", () => {
    const rows = qualityScores([
      { id: "strength", sets: 10, felt: 0 },
      { id: "power", sets: 3, felt: 2 },
      { id: "speed", sets: 6, felt: 1 },
    ]);
    expect(topQualities(rows, "sets", 2)).toEqual(["strength", "speed"]);
    expect(topQualities(rows, "felt", 3)).toEqual(["power", "speed"]);
  });

  it("puts the first radar axis straight up and closes the polygon over every axis", () => {
    expect(radarPoint(0, 4, 1, 50, 10)).toEqual([50, 40]);
    const [x, y] = radarPoint(1, 4, 1, 50, 10);
    expect(Math.round(x)).toBe(60);
    expect(Math.round(y)).toBe(50);
    expect(radarPolygon([1, 0.5, 1, 0.5], 50, 10).split(" ")).toHaveLength(4);
  });

  it("scales load bars to the largest week", () => {
    expect(
      loadBars([
        { week_start: "2026-10-05", load: 200 },
        { week_start: "2026-10-12", load: 400 },
        { week_start: "2026-10-19" },
      ]),
    ).toEqual([
      { week_start: "2026-10-05", load: 200, percent: 50 },
      { week_start: "2026-10-12", load: 400, percent: 100 },
      { week_start: "2026-10-19", load: 0, percent: 0 },
    ]);
    expect(loadBars(undefined)).toEqual([]);
  });

  it("formats ratios in the locale and recognises bands", () => {
    expect(formatRatio(1.4, "el")).toBe("1,4 : 1");
    expect(formatRatio(2, "en")).toBe("2.0 : 1");
    expect(formatRatio(null, "en")).toBeNull();
    expect(formatRatio(0, "en")).toBeNull();
    expect(isLoadBand("well_above")).toBe(true);
    expect(isLoadBand("danger")).toBe(false);
  });
});
