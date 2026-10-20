import { describe, expect, it } from "vitest";

import {
  DEFAULT_FILTER,
  activeFilterCount,
  applyChip,
  bboxAround,
  buildOrigin,
  chipModel,
  clearNarrowing,
  filterKey,
  initialViewport,
  narrowingCount,
  originKey,
  parseFilter,
  pointOrigin,
  roundCoordinate,
  sameFilter,
  scopeFromParams,
  thinResults,
  toggleKind,
  viewportDiagonalKm,
  type AroundFilter,
} from "./around";

const sections = (totals: Partial<Record<"events" | "boxes" | "clubs" | "posts", number>>) =>
  ({
    events: totals.events === undefined ? null : { items: [], next_cursor: null, total: totals.events },
    boxes: totals.boxes === undefined ? null : { items: [], next_cursor: null, total: totals.boxes, placement: "category" },
    clubs: totals.clubs === undefined ? null : { items: [], next_cursor: null, total: totals.clubs },
    posts: totals.posts === undefined ? null : { items: [], next_cursor: null, total: totals.posts },
  }) as Parameters<typeof thinResults>[0]["sections"];

describe("parseFilter", () => {
  it("falls back to the default for missing or bad params", () => {
    expect(parseFilter(null)).toEqual(DEFAULT_FILTER);
    expect(parseFilter([])).toEqual(DEFAULT_FILTER);
    expect(parseFilter({ radius_km: "far", kinds: [], cost: ["gratis"], languages: ["greek", "el"] })).toEqual({
      ...DEFAULT_FILTER,
      languages: ["el"],
    });
  });

  it("keeps known values, clamps the radius and orders kinds", () => {
    const filter = parseFilter({ radius_km: 120, kinds: ["posts", "events"], when: "weekend", extra: true });
    expect(filter.radius_km).toBe(50);
    expect(filter.kinds).toEqual(["events", "posts"]);
    expect(filter.when).toBe("weekend");
    expect(filter).not.toHaveProperty("extra");
  });

  it("drops a range without both dates", () => {
    expect(parseFilter({ when: "range", date_from: "2026-10-24" }).when).toBeNull();
    expect(parseFilter({ when: "range", date_from: "2026-10-24", date_to: "2026-10-25" })).toMatchObject({
      when: "range",
      date_from: "2026-10-24",
      date_to: "2026-10-25",
    });
  });
});

describe("activeFilterCount", () => {
  it("is zero for the default", () => {
    expect(activeFilterCount(DEFAULT_FILTER)).toBe(0);
  });

  it("counts each facet once, like the API", () => {
    const filter: AroundFilter = {
      ...DEFAULT_FILTER,
      radius_km: 5,
      neighbourhood_ids: ["n-1"],
      when: "weekend",
      times: ["morning"],
      cost: ["free", "trial"],
      max_price_cents: 1500,
      disciplines: ["hyrox"],
    };
    expect(activeFilterCount(filter)).toBe(4);
    expect(activeFilterCount(toggleKind(DEFAULT_FILTER, "posts"))).toBe(1);
  });

  it("narrowing leaves out where and turning posts on", () => {
    expect(narrowingCount({ ...DEFAULT_FILTER, radius_km: 10, kinds: ["events", "boxes", "clubs", "posts"] })).toBe(0);
    expect(narrowingCount({ ...DEFAULT_FILTER, kinds: ["events"] })).toBe(1);
    expect(narrowingCount({ ...DEFAULT_FILTER, cost: ["free"], audiences: ["beginners"] })).toBe(2);
  });

  it("clearing narrowing keeps the radius, places and posts", () => {
    const cleared = clearNarrowing({
      ...DEFAULT_FILTER,
      radius_km: 10,
      neighbourhood_ids: ["n-1"],
      kinds: ["events", "posts"],
      cost: ["free"],
    });
    expect(cleared).toEqual({ ...DEFAULT_FILTER, radius_km: 10, neighbourhood_ids: ["n-1"], kinds: ["events", "boxes", "clubs", "posts"] });
  });
});

describe("chips", () => {
  it("maps the filter to chips", () => {
    const chips = chipModel({ ...DEFAULT_FILTER, radius_km: 2, cost: ["free"], disciplines: ["boxing"] });
    const radius = chips.find((chip) => chip.key === "radius");
    expect(radius).toMatchObject({ kind: "menu", selected: ["2"] });
    expect(radius && radius.kind === "menu" ? radius.options : []).toEqual(["1", "2", "3", "5", "10", "25"]);
    expect(chips.find((chip) => chip.key === "free")).toMatchObject({ active: true });
    expect(chips.find((chip) => chip.key === "trial")).toMatchObject({ active: false });
    const discipline = chips.find((chip) => chip.key === "discipline");
    expect(discipline && discipline.kind === "menu" ? discipline.options : []).toContain("boxing");
  });

  it("maps chips back to the filter", () => {
    expect(applyChip(DEFAULT_FILTER, "radius", ["10"]).radius_km).toBe(10);
    expect(applyChip(DEFAULT_FILTER, "radius", []).radius_km).toBe(3);
    expect(applyChip({ ...DEFAULT_FILTER, when: "range", date_from: "2026-10-24", date_to: "2026-10-25" }, "when", ["today"])).toMatchObject({
      when: "today",
      date_from: null,
      date_to: null,
    });
    expect(applyChip({ ...DEFAULT_FILTER, when: "today" }, "when", []).when).toBeNull();
    expect(applyChip(DEFAULT_FILTER, "free").cost).toEqual(["free"]);
    expect(applyChip({ ...DEFAULT_FILTER, cost: ["free"] }, "free").cost).toEqual([]);
    expect(applyChip(DEFAULT_FILTER, "posts").kinds).toEqual(["events", "boxes", "clubs", "posts"]);
    expect(applyChip(DEFAULT_FILTER, "discipline", ["hyrox", "running"]).disciplines).toEqual(["hyrox", "running"]);
  });

  it("never leaves no kind at all", () => {
    expect(toggleKind({ ...DEFAULT_FILTER, kinds: ["clubs"] }, "clubs").kinds).toEqual(["events", "boxes", "clubs"]);
  });

  it("compares filters regardless of order", () => {
    const a = { ...DEFAULT_FILTER, cost: ["free", "trial"] as AroundFilter["cost"] };
    const b = { ...DEFAULT_FILTER, cost: ["trial", "free"] as AroundFilter["cost"] };
    expect(sameFilter(a, b)).toBe(true);
    expect(filterKey(a)).toBe(filterKey(b));
    expect(sameFilter(a, DEFAULT_FILTER)).toBe(false);
  });
});

describe("origin", () => {
  it("rounds a device point to 3 decimals", () => {
    expect(roundCoordinate(37.98765)).toBe(37.988);
    expect(roundCoordinate(-0.0001)).toBe(0);
    expect(pointOrigin(37.98765, 23.72749)).toEqual({ type: "point", latitude: 37.988, longitude: 23.727 });
  });

  it("builds the request origin", () => {
    expect(buildOrigin({ type: "auto" })).toBeUndefined();
    expect(buildOrigin({ type: "point", latitude: 40.64012, longitude: 22.94449 })).toEqual({
      type: "point",
      latitude: 40.64,
      longitude: 22.944,
    });
    expect(buildOrigin({ type: "place", neighbourhoodId: "n-1", label: "Κυψέλη" })).toEqual({ type: "place", neighbourhood_id: "n-1" });
    expect(buildOrigin({ type: "place", query: "  Θεσσαλονίκη ", label: "Θεσσαλονίκη" })).toEqual({ type: "place", query: "Θεσσαλονίκη" });
  });

  it("keys on what is sent, not on labels or extra precision", () => {
    expect(originKey({ type: "point", latitude: 37.98761, longitude: 23.7271 })).toBe(
      originKey({ type: "point", latitude: 37.98759, longitude: 23.72711 }),
    );
    expect(originKey({ type: "place", neighbourhoodId: "n-1", label: "A" })).toBe(originKey({ type: "place", neighbourhoodId: "n-1", label: "B" }));
  });
});

describe("thinResults", () => {
  const filter = { ...DEFAULT_FILTER };

  it("is null when the search found enough", () => {
    expect(thinResults({ sections: sections({ events: 3, boxes: 1, clubs: 1 }), wider: [], filter })).toBeNull();
  });

  it("offers wider radii that find more", () => {
    const thin = thinResults({
      sections: sections({ events: 0, boxes: 0, clubs: 0 }),
      wider: [
        { radius_km: 10, total: 4, by_kind: { events: 4 } },
        { radius_km: 25, total: 12, by_kind: { events: 9, boxes: 3 } },
      ],
      filter,
    });
    expect(thin).toEqual({
      found: 0,
      radiusKm: 3,
      wider: [
        { radiusKm: 10, total: 4 },
        { radiusKm: 25, total: 12 },
      ],
      canClear: false,
    });
  });

  it("skips rungs that find nothing more and offers clearing when filters narrow", () => {
    const thin = thinResults({
      sections: sections({ events: 2 }),
      wider: [{ radius_km: 10, total: 2, by_kind: { events: 2 } }],
      filter: { ...filter, kinds: ["events"], cost: ["free"] },
    });
    expect(thin).toEqual({ found: 2, radiusKm: 3, wider: [], canClear: true });
  });

  it("stays quiet with a few results and nothing to offer", () => {
    expect(thinResults({ sections: sections({ events: 2 }), wider: [], filter })).toBeNull();
  });

  it("still shows the empty card with nothing to offer", () => {
    expect(thinResults({ sections: sections({ events: 0 }), wider: [], filter })).toEqual({
      found: 0,
      radiusKm: 3,
      wider: [],
      canClear: false,
    });
  });
});

describe("map viewport", () => {
  it("builds a square box around a point", () => {
    const bbox = bboxAround(37.98, 23.73, 3);
    expect(bbox.north - bbox.south).toBeCloseTo((2 * 3) / 111.32, 5);
    expect(bbox.east - bbox.west).toBeGreaterThan(bbox.north - bbox.south);
    expect(viewportDiagonalKm(bbox)).toBeCloseTo(2 * 3 * Math.SQRT2, 0);
  });

  it("keeps the first frame under the 60 km cap", () => {
    expect(viewportDiagonalKm(initialViewport(37.98, 23.73, 50))).toBeLessThan(60);
    expect(viewportDiagonalKm(bboxAround(37.98, 23.73, 25))).toBeGreaterThan(60);
  });
});

describe("scope", () => {
  it("reads the remembered scope from the feed's params", () => {
    expect(scopeFromParams({ scope: "around" })).toBe("around");
    expect(scopeFromParams({ scope: "global" })).toBeNull();
    expect(scopeFromParams(null)).toBeNull();
  });
});
