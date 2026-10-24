/**
 * A list screen's filter as plain data (vision §7.2, §8.5): each field picks
 * one value, several, or is an on/off toggle. The shape is declared once per
 * screen, so the remembered params (ADR-151), the chip row and the sheet all
 * read the same thing, and an unknown or broken stored value falls back to
 * «nothing picked».
 */
export type ListFilterKind = "one" | "many" | "toggle";
export type ListFilterShape = Readonly<Record<string, ListFilterKind>>;
export type ListFilter<S extends ListFilterShape> = {
  [K in keyof S]: S[K] extends "toggle" ? boolean : string[];
};

const MAX_VALUES = 20;

export function emptyListFilter<S extends ListFilterShape>(shape: S): ListFilter<S> {
  return Object.fromEntries(
    Object.entries(shape).map(([key, kind]) => [key, kind === "toggle" ? false : []]),
  ) as ListFilter<S>;
}

/** The filter from stored params: unknown keys are dropped, bad values are «nothing picked». */
export function parseListFilter<S extends ListFilterShape>(shape: S, params: unknown): ListFilter<S> {
  const raw = params && typeof params === "object" && !Array.isArray(params) ? (params as Record<string, unknown>) : {};
  return Object.fromEntries(
    Object.entries(shape).map(([key, kind]) => {
      const value = raw[key];
      if (kind === "toggle") return [key, value === true];
      const strings = Array.isArray(value) ? Array.from(new Set(value.filter((item): item is string => typeof item === "string"))) : [];
      return [key, strings.slice(0, kind === "one" ? 1 : MAX_VALUES)];
    }),
  ) as ListFilter<S>;
}

/** «Φίλτρα (n)»: every field that narrows counts once. */
export function listFilterCount(filter: Record<string, string[] | boolean>): number {
  return Object.values(filter).filter((value) => (Array.isArray(value) ? value.length > 0 : value)).length;
}

/**
 * Whether an item passes one field: nothing picked passes everything;
 * otherwise the item's value (or one of its values) must be picked.
 */
export function picked(selected: readonly string[], value: string | null | undefined | readonly (string | null | undefined)[]) {
  if (selected.length === 0) return true;
  const values = Array.isArray(value) ? value : [value];
  return values.some((item) => typeof item === "string" && selected.includes(item));
}

/** Distinct options from a list, in first-seen order, labelled by `label`. */
export function distinctOptions<T>(items: readonly T[], value: (item: T) => string | null | undefined, label: (item: T) => string) {
  const seen = new Map<string, string>();
  for (const item of items) {
    const key = value(item);
    if (key && !seen.has(key)) seen.set(key, label(item) || key);
  }
  return [...seen].map(([key, text]) => ({ value: key, label: text }));
}
