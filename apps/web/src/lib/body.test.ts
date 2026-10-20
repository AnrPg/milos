import { describe, expect, it } from "vitest";

import {
  checkMeasure,
  defaultComparePair,
  formatDelta,
  formatMetric,
  formFields,
  metricsPatch,
  parseMetricInput,
  seriesPaths,
  seriesSummary,
  sharedPoses,
  shouldAskWeightDisplay,
  snapshotChange,
  toDeltaRows,
  shapePath,
  unitOf,
} from "./body";

const catalog = [
  { key: "weight" as const, min: 20, max: 400, unit: "kg" },
  { key: "waist" as const, min: 30, max: 250, unit: "cm" },
  { key: "body_fat" as const, min: 2, max: 75, unit: "%" },
];

describe("formFields", () => {
  it("shows the usual fields before anything was measured", () => {
    const { fields, extras } = formFields(null);
    expect(fields).toEqual(["weight", "body_fat", "waist", "hips", "chest", "arm", "thigh"]);
    expect(extras).toEqual(["neck", "calf", "arm_left", "arm_right", "thigh_left", "thigh_right"]);
  });

  it("puts the fields used last time first, withheld ones included, and keeps opened extras", () => {
    const { fields, extras } = formFields({ metrics: { thigh: 55, neck: 38 }, withheld_metrics: ["weight"] }, ["calf"]);
    expect(fields.slice(0, 3)).toEqual(["weight", "thigh", "neck"]);
    expect(fields).toContain("calf");
    expect(extras).not.toContain("neck");
    expect(extras).not.toContain("calf");
  });
});

describe("form validation", () => {
  it("reads both decimal signs and refuses text", () => {
    expect(parseMetricInput("72,4")).toBe(72.4);
    expect(parseMetricInput(" 72.4 ")).toBe(72.4);
    expect(parseMetricInput("")).toBeNull();
    expect(parseMetricInput("abc")).toBeNaN();
    expect(parseMetricInput("-3")).toBeNaN();
  });

  it("needs at least one value or one photo", () => {
    expect(checkMeasure({}, 0, catalog)).toMatchObject({ ok: false, empty: true });
    expect(checkMeasure({ weight: "" }, 1, catalog)).toMatchObject({ ok: true, empty: false });
    expect(checkMeasure({ waist: "81" }, 0, catalog)).toMatchObject({ ok: true, metrics: { waist: 81 } });
  });

  it("flags numbers outside the catalog range and non-numbers", () => {
    const check = checkMeasure({ weight: "7", waist: "x", body_fat: "22,5" }, 0, catalog);
    expect(check.ok).toBe(false);
    expect(check.empty).toBe(false);
    expect(check.errors).toEqual({ weight: "range", waist: "invalid" });
    expect(check.metrics).toEqual({ body_fat: 22.5 });
  });

  it("sends changed values and null for cleared ones on edit", () => {
    expect(metricsPatch({ weight: 72.4, waist: 81 }, { weight: 72.4, hips: 96 })).toEqual({ waist: null, hips: 96 });
  });
});

describe("unit formatting", () => {
  it("writes values and changes in the locale with a real minus", () => {
    expect(formatMetric(72.4, "kg", "el")).toBe("72,4 kg");
    expect(formatMetric(72.4, "kg", "en")).toBe("72.4 kg");
    expect(formatDelta(-0.8, "kg", "el")).toBe("−0,8 kg");
    expect(formatDelta(1, "cm", "en")).toBe("+1 cm");
    expect(formatDelta(0.04, "cm", "en")).toBe("0 cm");
  });

  it("takes the unit from the catalog, imperial when no catalog", () => {
    expect(unitOf("weight", catalog, "metric")).toBe("kg");
    expect(unitOf("waist", [], "imperial")).toBe("in");
    expect(unitOf("weight", [], "imperial")).toBe("lb");
  });
});

describe("trend rendering", () => {
  const at = (day: number) => `2026-07-${String(day).padStart(2, "0")}T08:00:00Z`;

  it("draws the server's 0..1 shape, spaced by time, top for 1 and bottom for 0", () => {
    expect(shapePath(undefined, 200, 50)).toBe("");
    expect(shapePath([], 200, 50)).toBe("");
    const path = shapePath([{ at: at(1), y: 1 }, { at: at(4), y: 0.5 }, { at: at(11), y: 0 }], 200, 50);
    expect(path).toBe("M0.0,6.0L60.0,25.0L200.0,44.0");
  });

  it("draws a flat series in the middle and one point as a short flat line", () => {
    expect(shapePath([{ at: at(1), y: 0.5 }, { at: at(8), y: 0.5 }], 100, 50)).toBe("M0.0,25.0L100.0,25.0");
    expect(shapePath([{ at: at(1), y: 0.5 }], 100, 50)).toBe("M0,25.0L100.0,25.0");
  });

  it("carries no number of the person's weight, only the shape", () => {
    expect(shapePath([{ at: at(1), y: 1 }, { at: at(8), y: 0.2 }], 240, 60)).not.toMatch(/72/);
  });

  it("draws readings and a smoothed line from real points", () => {
    const points = [
      { at: at(1), value: 74.5, smoothed: 74.5 },
      { at: at(8), value: 72.4, smoothed: 73.87 },
    ];
    const paths = seriesPaths(points, 100, 40);
    expect(paths.raw.startsWith("M0.0,")).toBe(true);
    expect(seriesSummary(points)).toEqual({ latest: 72.4, change: -2.1 });
    expect(seriesSummary([])).toBeNull();
  });
});

describe("compare", () => {
  it("defaults to the first and the latest snapshot", () => {
    expect(defaultComparePair([{ id: "c", taken_at: "2026-10-14T00:00:00Z" }, { id: "b", taken_at: "2026-09-01T00:00:00Z" }, { id: "a", taken_at: "2026-07-01T00:00:00Z" }])).toEqual({ from: "a", to: "c" });
    expect(defaultComparePair([{ id: "a", taken_at: "2026-07-01T00:00:00Z" }])).toBeNull();
  });

  it("lists numbers where shown and words where weight is a trend", () => {
    expect(
      toDeltaRows([
        { metric: "waist", delta: -4, direction: "down" },
        { metric: "weight", delta: null, direction: "slightly_down" },
      ]),
    ).toEqual([
      { metric: "waist", kind: "number", delta: -4 },
      { metric: "weight", kind: "trend", direction: "slightly_down" },
    ]);
  });

  it("offers only poses both snapshots have ready", () => {
    const photo = (pose: "front" | "side" | "back", status: "ready" | "processing" = "ready") => ({ id: pose, pose, status });
    expect(sharedPoses({ photos: [photo("front"), photo("side")] }, { photos: [photo("front"), photo("side", "processing"), photo("back")] })).toEqual(["front"]);
  });

  it("reads the change since the previous snapshot on a shown metric", () => {
    expect(snapshotChange({ metrics: { weight: 72.4, waist: 81 } }, { metrics: { weight: 73.2 } })).toEqual({ metric: "weight", delta: -0.8 });
    expect(snapshotChange({ metrics: { waist: 81 } }, { metrics: { weight: 73.2, waist: 82 } })).toEqual({ metric: "waist", delta: -1 });
    expect(snapshotChange({ metrics: {} }, null)).toBeNull();
  });
});

describe("the weight display question", () => {
  it("is asked once, with the first weight, while the choice is the default", () => {
    const base = { typedWeight: true, weightDisplay: "number" as const, history: [], answered: false };
    expect(shouldAskWeightDisplay(base)).toBe(true);
    expect(shouldAskWeightDisplay({ ...base, typedWeight: false })).toBe(false);
    expect(shouldAskWeightDisplay({ ...base, answered: true })).toBe(false);
    expect(shouldAskWeightDisplay({ ...base, weightDisplay: "trend" })).toBe(false);
    expect(shouldAskWeightDisplay({ ...base, history: [{ metrics: { weight: 70 }, withheld_metrics: [] }] })).toBe(false);
  });
});

describe("metricDeltas", () => {
  it("lists only metrics both snapshots show as numbers", async () => {
    const { metricDeltas } = await import("./body");
    expect(metricDeltas({ metrics: { waist: 85, weight: 74 } }, { metrics: { waist: 81, thigh: 55 } })).toEqual([
      { metric: "waist", delta: -4, direction: null },
    ]);
  });
});
