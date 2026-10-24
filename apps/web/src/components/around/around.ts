import type {
  AroundKind,
  AroundNormalizedFilter,
  AroundOriginRequest,
  AroundSearchResponse,
  AroundViewport,
} from "@/api/around";

// Γύρω μου (ADR-154, vision §7.2): the pure parts of the screen. The filter
// mirrors the API's AroundFilter v1 so saved filters, the last-used filter and
// the chip row all speak one shape.

export type AroundFilter = AroundNormalizedFilter;
export type When = NonNullable<AroundFilter["when"]>;
export type DayTime = AroundFilter["times"][number];
export type Cost = AroundFilter["cost"][number];

export const DEFAULT_RADIUS_KM = 3;
export const MIN_RADIUS_KM = 0.5;
export const MAX_RADIUS_KM = 50;
export const MAX_NEIGHBOURHOODS = 5;
export const DEFAULT_KINDS: AroundKind[] = ["events", "boxes", "clubs"];
export const KIND_ORDER: AroundKind[] = ["events", "boxes", "clubs", "posts"];
export const WHENS: When[] = ["today", "tomorrow", "weekend", "week"];
export const DAY_TIMES: DayTime[] = ["morning", "midday", "evening"];
export const COSTS: Cost[] = ["free", "trial"];
/** «Έως €15», the price shortcut chip. */
export const PRICE_CAP_CENTS = 1500;
/** The price slider (cents): its top end means «no maximum». */
export const PRICE_SLIDER = { min: 0, max: 10_000, step: 100 } as const;
/** A date range spans at most this many days (AroundFilter, ADR-154). */
export const MAX_RANGE_DAYS = 62;
/** «Προσβάσιμο» is this amenity of the box-profile vocabulary. */
export const ACCESSIBLE_AMENITY = "wheelchair_accessible";
/** The radius slider's stops (km). */
export const RADIUS_STEPS = [0.5, 1, 2, 3, 5, 10, 15, 25, 50];
/** The radius chip's menu. */
export const RADIUS_CHIP_OPTIONS = [1, 3, 5, 10, 25];
/** Disciplines offered straight from the chip row (the rest are in the sheet). */
export const CHIP_DISCIPLINES = ["crossfit", "hyrox", "running", "powerlifting", "yoga", "martial_arts"];
/** Fewer results than this and the API sends wider counts (ADR-154 §8). */
export const THIN_THRESHOLD = 5;
/** «Ψάξε εδώ» refuses a viewport whose diagonal is longer (ADR-154 §9). */
export const MAX_VIEWPORT_KM = 60;

export const DEFAULT_FILTER: AroundFilter = {
  v: 1,
  radius_km: DEFAULT_RADIUS_KM,
  neighbourhood_ids: [],
  kinds: DEFAULT_KINDS,
  disciplines: [],
  when: null,
  date_from: null,
  date_to: null,
  times: [],
  cost: [],
  min_price_cents: null,
  max_price_cents: null,
  audiences: [],
  languages: [],
  amenities: [],
};

const strings = (value: unknown, allowed?: readonly string[], max = 20): string[] => {
  if (!Array.isArray(value)) return [];
  const picked = value.filter((item): item is string => typeof item === "string" && (!allowed || allowed.includes(item)));
  return Array.from(new Set(picked)).slice(0, max);
};

const isoDate = (value: unknown) => (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null);

/**
 * A filter from stored params (the last-used filter, a saved one, an older
 * client's): unknown keys are dropped, bad values fall back to the default.
 */
export function parseFilter(params: unknown): AroundFilter {
  if (!params || typeof params !== "object" || Array.isArray(params)) return DEFAULT_FILTER;
  const raw = params as Record<string, unknown>;
  const radius = typeof raw.radius_km === "number" && Number.isFinite(raw.radius_km) ? raw.radius_km : DEFAULT_RADIUS_KM;
  const kinds = strings(raw.kinds, KIND_ORDER) as AroundKind[];
  const when = typeof raw.when === "string" && [...WHENS, "range"].includes(raw.when) ? (raw.when as When) : null;
  const dateFrom = isoDate(raw.date_from);
  const dateTo = isoDate(raw.date_to);
  const cents = (value: unknown) => (typeof value === "number" && value >= 0 ? Math.round(value) : null);
  const maxPrice = cents(raw.max_price_cents);
  const minPrice = cents(raw.min_price_cents) || null;
  return {
    v: 1,
    radius_km: Math.min(MAX_RADIUS_KM, Math.max(MIN_RADIUS_KM, radius)),
    neighbourhood_ids: strings(raw.neighbourhood_ids, undefined, MAX_NEIGHBOURHOODS),
    kinds: kinds.length > 0 ? KIND_ORDER.filter((kind) => kinds.includes(kind)) : DEFAULT_KINDS,
    disciplines: strings(raw.disciplines, undefined, 10),
    when: when === "range" && !(dateFrom && dateTo) ? null : when,
    date_from: when === "range" ? dateFrom : null,
    date_to: when === "range" ? dateTo : null,
    times: strings(raw.times, DAY_TIMES) as DayTime[],
    cost: strings(raw.cost, COSTS) as Cost[],
    min_price_cents: minPrice !== null && maxPrice !== null && minPrice > maxPrice ? null : minPrice,
    max_price_cents: maxPrice,
    audiences: strings(raw.audiences, undefined, 10),
    languages: strings(raw.languages, undefined, 10).filter((code) => /^[a-z]{2}$/.test(code)),
    amenities: strings(raw.amenities, undefined, 10),
  };
}

const sameSet = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((item) => b.includes(item));

/** The «Πού» facet: a radius other than the default, or neighbourhoods. */
export function hasWhere(filter: AroundFilter) {
  return filter.neighbourhood_ids.length > 0 || filter.radius_km !== DEFAULT_RADIUS_KM;
}

/**
 * «Φίλτρα (n)», counted like the API (AroundFilter.active_count/1): where,
 * what, discipline, when, cost, audience, language and amenities count once each.
 */
export function activeFilterCount(filter: AroundFilter) {
  return [hasWhere(filter), ...narrowingFacets(filter)].filter(Boolean).length;
}

function narrowingFacets(filter: AroundFilter) {
  return [
    !sameSet(filter.kinds, DEFAULT_KINDS),
    filter.disciplines.length > 0,
    filter.when !== null || filter.times.length > 0,
    filter.cost.length > 0 || hasPriceRange(filter),
    filter.audiences.length > 0,
    filter.languages.length > 0,
    filter.amenities.length > 0,
  ];
}

/** Facets that can hide results (everything but where; turning posts on never hides). */
export function narrowingCount(filter: AroundFilter) {
  const kindsHide = !DEFAULT_KINDS.every((kind) => filter.kinds.includes(kind));
  return [kindsHide, ...narrowingFacets(filter).slice(1)].filter(Boolean).length;
}

/** «Καθάρισε φίλτρα» on thin results: keeps where you search (the chosen radius persists) and posts if on. */
export function clearNarrowing(filter: AroundFilter): AroundFilter {
  return {
    ...DEFAULT_FILTER,
    radius_km: filter.radius_km,
    neighbourhood_ids: filter.neighbourhood_ids,
    kinds: filter.kinds.includes("posts") ? [...DEFAULT_KINDS, "posts"] : DEFAULT_KINDS,
  };
}

/** A stable key for a filter (react-query keys, comparing with saved filters). */
export function filterKey(filter: AroundFilter) {
  const sorted = (values: readonly string[]) => [...values].sort();
  return JSON.stringify([
    filter.radius_km,
    sorted(filter.neighbourhood_ids),
    sorted(filter.kinds),
    sorted(filter.disciplines),
    filter.when,
    filter.date_from,
    filter.date_to,
    sorted(filter.times),
    sorted(filter.cost),
    filter.min_price_cents,
    filter.max_price_cents,
    sorted(filter.audiences),
    sorted(filter.languages),
    sorted(filter.amenities),
  ]);
}

export function sameFilter(a: AroundFilter, b: AroundFilter) {
  return filterKey(a) === filterKey(b);
}

export function toggleValue<T extends string>(values: readonly T[], value: T): T[] {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

/** «Δες όλα» (and old `/around/<kind>` links): the «what» filter narrowed to one kind. */
export function onlyKind(filter: AroundFilter, kind: AroundKind): AroundFilter {
  return { ...filter, kinds: [kind] };
}

/** The one kind the filter shows, when it shows exactly one: Γύρω μου then lists it in full. */
export function singleKind(filter: AroundFilter): AroundKind | null {
  return filter.kinds.length === 1 ? filter.kinds[0] : null;
}

/** A kind's string from a link (`?kind=`), when it names one. */
export function parseKind(value: string | null | undefined): AroundKind | null {
  return KIND_ORDER.find((kind) => kind === value) ?? null;
}

/** The link to Γύρω μου with one kind preselected. */
export function aroundKindHref(kind: AroundKind) {
  return `/around?kind=${encodeURIComponent(kind)}`;
}

/** Turning off the last kind is not allowed: the default kinds come back. */
export function toggleKind(filter: AroundFilter, kind: AroundKind): AroundFilter {
  const next = toggleValue(filter.kinds, kind);
  return { ...filter, kinds: next.length > 0 ? KIND_ORDER.filter((item) => next.includes(item)) : DEFAULT_KINDS };
}

export function withWhen(filter: AroundFilter, when: When | null): AroundFilter {
  return { ...filter, when, date_from: null, date_to: null };
}

const shiftDay = (iso: string, days: number) => {
  const date = new Date(`${iso}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
};

/** The last day a range starting on `from` may reach. */
export function lastRangeDay(from: string) {
  return shiftDay(from, MAX_RANGE_DAYS - 1);
}

/**
 * The date pickers above the «Πότε» shortcuts: one end picked is a single
 * day, ends picked the wrong way round swap, and a range longer than the API
 * allows is cut at its end. Both cleared means no date at all.
 */
export function withDates(filter: AroundFilter, from: string | null, to: string | null): AroundFilter {
  const start = from || to;
  if (!start) return filter.when === "range" ? withWhen(filter, null) : filter;
  const [first, last] = [start, to || from || start].sort();
  return { ...filter, when: "range", date_from: first, date_to: last > lastRangeDay(first) ? lastRangeDay(first) : last };
}

/** Whether the filter narrows by a price range (either end). */
export function hasPriceRange(filter: AroundFilter) {
  return filter.min_price_cents !== null || filter.max_price_cents !== null;
}

/** The price slider's thumbs for a filter: an open end sits at the slider's end. */
export function priceSliderValue(filter: AroundFilter) {
  const clamp = (cents: number) => Math.min(PRICE_SLIDER.max, Math.max(PRICE_SLIDER.min, cents));
  return {
    from: clamp(filter.min_price_cents ?? PRICE_SLIDER.min),
    to: clamp(filter.max_price_cents ?? PRICE_SLIDER.max),
  };
}

/**
 * The price slider moved: a thumb at its end leaves that end open, and a
 * range chosen by hand replaces «Δωρεάν» (which the slider cannot show).
 */
export function withPriceRange(filter: AroundFilter, range: { from: number; to: number }): AroundFilter {
  const min = range.from > PRICE_SLIDER.min ? range.from : null;
  const max = range.to < PRICE_SLIDER.max ? range.to : null;
  return {
    ...filter,
    cost: min !== null || max !== null ? filter.cost.filter((cost) => cost !== "free") : filter.cost,
    min_price_cents: min,
    max_price_cents: max,
  };
}

/** «Δωρεάν» is a shortcut: turning it on clears the hand-picked range. */
export function toggleFree(filter: AroundFilter): AroundFilter {
  const on = !filter.cost.includes("free");
  return on
    ? { ...filter, cost: COSTS.filter((cost) => cost === "free" || filter.cost.includes(cost)), min_price_cents: null, max_price_cents: null }
    : { ...filter, cost: filter.cost.filter((cost) => cost !== "free") };
}

/** «Έως €15» is on when the range is exactly up to the cap. */
export function isPriceCap(filter: AroundFilter) {
  return filter.min_price_cents === null && filter.max_price_cents === PRICE_CAP_CENTS;
}

/** «Έως €15» tapped: that range (dropping «Δωρεάν»), or no range again. */
export function togglePriceCap(filter: AroundFilter): AroundFilter {
  return isPriceCap(filter)
    ? { ...filter, min_price_cents: null, max_price_cents: null }
    : withPriceRange(filter, { from: PRICE_SLIDER.min, to: PRICE_CAP_CENTS });
}

// ------------------------------------------------------------------ chips

export type ChipKey = "radius" | "when" | "free" | "trial" | "discipline" | "posts";

export type ChipModel =
  | { key: ChipKey; kind: "menu"; options: string[]; selected: string[]; multiple: boolean }
  | { key: ChipKey; kind: "toggle"; active: boolean };

/**
 * The shortcut chips after «Φίλτρα (n)» and «Τα αθλήματά μου» (mockup `near`).
 * Only «Πότε» and «Δωρεάν»: the row must fit a 320 px phone without scrolling
 * sideways, so every other facet (discipline, trial, posts…) lives in the
 * filter sheet only, and «≤ X km» sits next to «Αλλαγή περιοχής» (`radiusChip`).
 */
export function chipModel(filter: AroundFilter): ChipModel[] {
  return [
    {
      key: "when",
      kind: "menu",
      options: filter.when === "range" ? [...WHENS, "range"] : WHENS,
      selected: filter.when ? [filter.when] : [],
      multiple: false,
    },
    { key: "free", kind: "toggle", active: filter.cost.includes("free") },
  ];
}

/** «≤ 3 km ▾», shown beside «Αλλαγή περιοχής»: the usual radii plus the current one. */
export function radiusChip(filter: AroundFilter): Extract<ChipModel, { kind: "menu" }> {
  const options = Array.from(new Set([...RADIUS_CHIP_OPTIONS, filter.radius_km])).sort((a, b) => a - b);
  return { key: "radius", kind: "menu", options: options.map(String), selected: [String(filter.radius_km)], multiple: false };
}

/** «Τα αθλήματά μου» is on when the filter's disciplines are exactly the person's (ADR-183). */
export function isMine(filter: AroundFilter, mine: readonly string[]) {
  return mine.length > 0 && sameSet(filter.disciplines, mine);
}

/** «Τα αθλήματά μου» tapped: their disciplines, or none again. */
export function toggleMine(filter: AroundFilter, mine: readonly string[]): AroundFilter {
  return { ...filter, disciplines: isMine(filter, mine) ? [] : [...mine] };
}

/** What a chip does to the filter: a menu chip's new values, or a toggle (values omitted). */
export function applyChip(filter: AroundFilter, key: ChipKey, values?: string[]): AroundFilter {
  switch (key) {
    case "radius": {
      const km = Number(values?.[0]);
      return Number.isFinite(km) && km > 0 ? { ...filter, radius_km: km } : { ...filter, radius_km: DEFAULT_RADIUS_KM };
    }
    case "when": {
      const when = values?.[0];
      return withWhen(filter, when && (WHENS as string[]).includes(when) ? (when as When) : null);
    }
    case "free":
      return toggleFree(filter);
    case "trial":
      return { ...filter, cost: toggleValue(filter.cost, "trial") };
    case "discipline":
      return { ...filter, disciplines: values ?? [] };
    case "posts":
      return toggleKind(filter, "posts");
  }
}

// ------------------------------------------------------------------ origin

/** Where a search starts, as the screen holds it. A device point is never stored anywhere. */
export type OriginChoice =
  | { type: "auto" }
  | { type: "point"; latitude: number; longitude: number }
  | { type: "place"; neighbourhoodId: string; label: string }
  | { type: "place"; query: string; label: string };

/** About 100 m (ADR-154 §3): what the API keeps of a device point, rounded here too. */
export function roundCoordinate(value: number) {
  const rounded = Math.round(value * 1000) / 1000;
  return Object.is(rounded, -0) ? 0 : rounded;
}

export function pointOrigin(latitude: number, longitude: number): OriginChoice {
  return { type: "point", latitude: roundCoordinate(latitude), longitude: roundCoordinate(longitude) };
}

/** The request's `origin`; left out, the API uses the filter's places, the saved area, then the box. */
export function buildOrigin(choice: OriginChoice): AroundOriginRequest | undefined {
  switch (choice.type) {
    case "auto":
      return undefined;
    case "point":
      return { type: "point", latitude: roundCoordinate(choice.latitude), longitude: roundCoordinate(choice.longitude) };
    case "place":
      return "neighbourhoodId" in choice
        ? { type: "place", neighbourhood_id: choice.neighbourhoodId }
        : { type: "place", query: choice.query.trim() };
  }
}

export function originKey(choice: OriginChoice) {
  return JSON.stringify(buildOrigin(choice) ?? null);
}

/** A one-off search elsewhere: it never changes the saved area or the remembered filter. */
export function isOneOff(choice: OriginChoice) {
  return choice.type !== "auto";
}

// ------------------------------------------------------------------ results

type SearchSummary = Pick<AroundSearchResponse, "sections" | "wider" | "filter">;

/** Everything the search found, across the kinds it looked at. */
export function foundTotal(sections: AroundSearchResponse["sections"]) {
  return KIND_ORDER.reduce((sum, kind) => sum + (sections[kind]?.total ?? 0), 0);
}

export type ThinResults = {
  found: number;
  radiusKm: number;
  /** Wider radii that find more, with their counts. */
  wider: Array<{ radiusKm: number; total: number }>;
  /** Filters are narrowing the search, so «Καθάρισε φίλτρα» may help. */
  canClear: boolean;
};

/** The «Τίποτα έως 3 km» card, or null when the search found enough. */
export function thinResults(response: SearchSummary): ThinResults | null {
  const found = foundTotal(response.sections);
  if (found >= THIN_THRESHOLD) return null;
  const filter = parseFilter(response.filter);
  const wider = response.wider
    .filter((rung) => rung.radius_km > filter.radius_km && rung.total > found)
    .map((rung) => ({ radiusKm: rung.radius_km, total: rung.total }));
  const canClear = narrowingCount(filter) > 0;
  if (found > 0 && wider.length === 0 && !canClear) return null;
  return { found, radiusKm: filter.radius_km, wider, canClear };
}

// ------------------------------------------------------------------ map

const KM_PER_DEGREE = 111.32;

/** A square viewport `km` from the centre each way. */
export function bboxAround(latitude: number, longitude: number, km: number): AroundViewport {
  const dLat = km / KM_PER_DEGREE;
  const dLng = km / (KM_PER_DEGREE * Math.max(0.01, Math.cos((latitude * Math.PI) / 180)));
  return { south: latitude - dLat, north: latitude + dLat, west: longitude - dLng, east: longitude + dLng };
}

/** The viewport's diagonal (haversine), for the 60 km cap. */
export function viewportDiagonalKm(bbox: AroundViewport) {
  const rad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = rad(bbox.north - bbox.south);
  const dLng = rad(bbox.east - bbox.west);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(bbox.south)) * Math.cos(rad(bbox.north)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** The first map frame: the search radius, kept under the viewport cap. */
export function initialViewport(latitude: number, longitude: number, radiusKm: number) {
  return bboxAround(latitude, longitude, Math.min(radiusKm, 20));
}

// ------------------------------------------------------------------ remembered choices

export type HomeScope = "clubs" | "around";

export const SCOPE_STORAGE_KEY = "palee:home-scope";

export function readStored(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function writeStored(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Private windows and blocked storage: the choice just isn't remembered here.
  }
}

/** The Αρχική scope inside the `feed` surface's last-used params (ADR-151). */
export function scopeFromParams(params: unknown): HomeScope | null {
  if (!params || typeof params !== "object") return null;
  const scope = (params as Record<string, unknown>).scope;
  return scope === "clubs" || scope === "around" ? scope : null;
}

export function parseScope(value: string | null): HomeScope | null {
  return value === "clubs" || value === "around" ? value : null;
}
