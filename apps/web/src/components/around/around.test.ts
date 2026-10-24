import { describe, expect, it } from "vitest";

import {
  DEFAULT_FILTER,
  aroundKindHref,
  onlyKind,
  parseKind,
  singleKind,
  activeFilterCount,
  applyChip,
  bboxAround,
  buildOrigin,
  chipModel,
  clearNarrowing,
  filterKey,
  initialViewport,
  isMine,
  narrowingCount,
  originKey,
  parseFilter,
  pointOrigin,
  radiusChip,
  roundCoordinate,
  sameFilter,
  scopeFromParams,
  thinResults,
  toggleFree,
  toggleKind,
  toggleMine,
  togglePriceCap,
  viewportDiagonalKm,
  withDates,
  withPriceRange,
  priceSliderValue,
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
  it("keeps only «Πότε» and «Δωρεάν» as shortcut chips, so the row fits a phone", () => {
    const chips = chipModel({ ...DEFAULT_FILTER, when: "weekend", cost: ["free"], disciplines: ["boxing"] });
    expect(chips.map((chip) => chip.key)).toEqual(["when", "free"]);
    expect(chips[0]).toMatchObject({ kind: "menu", selected: ["weekend"], options: ["today", "tomorrow", "weekend", "week"] });
    expect(chips[1]).toMatchObject({ kind: "toggle", active: true });
    expect(chipModel({ ...DEFAULT_FILTER, when: "range", date_from: "2026-10-24", date_to: "2026-10-25" })[0]).toMatchObject({
      options: ["today", "tomorrow", "weekend", "week", "range"],
      selected: ["range"],
    });
  });

  it("still counts every facet that left the row in «Φίλτρα (n)»", () => {
    // Radius (beside «Αλλαγή περιοχής»), discipline, trial and posts are in the sheet only.
    expect(activeFilterCount({ ...DEFAULT_FILTER, radius_km: 10 })).toBe(1);
    expect(activeFilterCount({ ...DEFAULT_FILTER, disciplines: ["boxing"] })).toBe(1);
    expect(activeFilterCount({ ...DEFAULT_FILTER, cost: ["trial"] })).toBe(1);
    expect(activeFilterCount(toggleKind(DEFAULT_FILTER, "posts"))).toBe(1);
  });

  it("offers the usual radii plus the current one beside «Αλλαγή περιοχής»", () => {
    expect(radiusChip({ ...DEFAULT_FILTER, radius_km: 2 })).toMatchObject({
      key: "radius",
      kind: "menu",
      selected: ["2"],
      options: ["1", "2", "3", "5", "10", "25"],
    });
    expect(radiusChip(DEFAULT_FILTER).options).toEqual(["1", "3", "5", "10", "25"]);
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

describe("«Τα αθλήματά μου» (ADR-183)", () => {
  it("is on only when the filter's disciplines are exactly the person's", () => {
    expect(isMine({ ...DEFAULT_FILTER, disciplines: ["yoga", "bjj_grappling"] }, ["bjj_grappling", "yoga"])).toBe(true);
    expect(isMine({ ...DEFAULT_FILTER, disciplines: ["yoga"] }, ["bjj_grappling", "yoga"])).toBe(false);
    expect(isMine(DEFAULT_FILTER, [])).toBe(false);
  });

  it("toggles between their disciplines and none", () => {
    const on = toggleMine(DEFAULT_FILTER, ["bjj_grappling", "yoga"]);
    expect(on.disciplines).toEqual(["bjj_grappling", "yoga"]);
    expect(toggleMine(on, ["bjj_grappling", "yoga"]).disciplines).toEqual([]);
  });
});

describe("date range above «Πότε»", () => {
  it("reads one end as a single day and swaps ends picked the wrong way round", () => {
    expect(withDates(DEFAULT_FILTER, "2030-05-02", null)).toMatchObject({ when: "range", date_from: "2030-05-02", date_to: "2030-05-02" });
    expect(withDates(DEFAULT_FILTER, "2030-05-09", "2030-05-02")).toMatchObject({ date_from: "2030-05-02", date_to: "2030-05-09" });
  });

  it("cuts a range at the API's 62 days and clears back to no date", () => {
    expect(withDates(DEFAULT_FILTER, "2030-01-01", "2030-12-31").date_to).toBe("2030-03-03");
    const ranged = withDates({ ...DEFAULT_FILTER, when: "weekend" }, "2030-05-02", "2030-05-04");
    expect(withDates(ranged, null, null)).toMatchObject({ when: null, date_from: null, date_to: null });
    expect(activeFilterCount(ranged)).toBe(1);
  });
});

describe("price range above «Κόστος»", () => {
  it("leaves an end open at the slider's end and drops «Δωρεάν» for a hand-picked range", () => {
    const free: AroundFilter = { ...DEFAULT_FILTER, cost: ["free", "trial"] };
    expect(withPriceRange(free, { from: 500, to: 10_000 })).toMatchObject({ cost: ["trial"], min_price_cents: 500, max_price_cents: null });
    expect(withPriceRange(free, { from: 0, to: 10_000 })).toMatchObject({ cost: ["free", "trial"], min_price_cents: null, max_price_cents: null });
    expect(priceSliderValue({ ...DEFAULT_FILTER, max_price_cents: 2000 })).toEqual({ from: 0, to: 2000 });
  });

  it("makes «Δωρεάν» and «Έως €15» shortcuts that replace the range", () => {
    const ranged: AroundFilter = { ...DEFAULT_FILTER, min_price_cents: 500, max_price_cents: 3000 };
    expect(toggleFree(ranged)).toMatchObject({ cost: ["free"], min_price_cents: null, max_price_cents: null });
    expect(togglePriceCap(ranged)).toMatchObject({ min_price_cents: null, max_price_cents: 1500 });
    expect(togglePriceCap(togglePriceCap(ranged))).toMatchObject({ min_price_cents: null, max_price_cents: null });
    expect(activeFilterCount(ranged)).toBe(1);
    expect(sameFilter(ranged, { ...ranged, min_price_cents: null })).toBe(false);
  });

  it("parses a stored minimum, dropping one above the maximum", () => {
    expect(parseFilter({ min_price_cents: 500 }).min_price_cents).toBe(500);
    expect(parseFilter({ min_price_cents: 0 }).min_price_cents).toBeNull();
    expect(parseFilter({ min_price_cents: 900, max_price_cents: 500 }).min_price_cents).toBeNull();
  });
});

describe("one kind («Δες όλα», `?kind=`)", () => {
  it("narrows «what» to one kind, which Γύρω μου then lists in full", () => {
    const filter = onlyKind({ ...DEFAULT_FILTER, radius_km: 5 }, "boxes");
    expect(filter).toMatchObject({ kinds: ["boxes"], radius_km: 5 });
    expect(singleKind(filter)).toBe("boxes");
    expect(singleKind(DEFAULT_FILTER)).toBeNull();
    expect(activeFilterCount(onlyKind(DEFAULT_FILTER, "boxes"))).toBe(1);
    expect(clearNarrowing(filter).kinds).toEqual(DEFAULT_FILTER.kinds);
  });

  it("reads only known kinds from a link and builds the link", () => {
    expect(parseKind("events")).toBe("events");
    expect(parseKind("people")).toBeNull();
    expect(parseKind(null)).toBeNull();
    expect(aroundKindHref("clubs")).toBe("/around?kind=clubs");
  });
});
