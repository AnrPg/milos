import type { ShopOptionAxis, ShopProductSummary, ShopVariant } from "@/api/shop";

/**
 * Variant availability for the product page and the grid (ADR-190), pure.
 * Every size stays visible (Baymard #850); one that is sold out in the
 * chosen colour is struck through and offers «Ειδοποίησέ με».
 */

/** Few enough units to say «Τελευταία n». */
export const LAST_UNITS_THRESHOLD = 5;

export type Selection = Record<string, string>;
export type ValueState = "available" | "low" | "sold_out" | "missing";

export function isSoldOut(variant: Pick<ShopVariant, "stock_status" | "available">) {
  return variant.stock_status === "out" || (variant.available !== null && variant.available <= 0);
}

export function isLow(variant: Pick<ShopVariant, "stock_status" | "available">) {
  if (isSoldOut(variant)) return false;
  // Members get no stock counts from the API, only `low`; staff-side data may carry a count.
  if (variant.available === null) return variant.stock_status === "low" || variant.stock_status === "critical";
  return variant.available <= LAST_UNITS_THRESHOLD;
}

function matches(variant: ShopVariant, selection: Selection, except?: string) {
  return Object.entries(selection).every(([axis, value]) => axis === except || variant.option_values[axis] === value);
}

/**
 * How each value of `axis` stands given what is chosen on the other axes:
 * `missing` when no variant has that combination, `sold_out` when every one
 * that has it is out, `low` when what is left is a few units.
 */
export function valueStates(axis: ShopOptionAxis, variants: ShopVariant[], selection: Selection): Record<string, ValueState> {
  const states: Record<string, ValueState> = {};
  for (const value of axis.values) {
    const candidates = variants.filter((variant) => variant.option_values[axis.name] === value && matches(variant, selection, axis.name));
    if (candidates.length === 0) states[value] = "missing";
    else if (candidates.every(isSoldOut)) states[value] = "sold_out";
    else if (candidates.filter((variant) => !isSoldOut(variant)).every(isLow)) states[value] = "low";
    else states[value] = "available";
  }
  return states;
}

/** The variant the selection names, once a value is chosen on every axis. */
export function selectedVariant(axes: ShopOptionAxis[], variants: ShopVariant[], selection: Selection) {
  if (axes.length === 0) return variants.length === 1 ? variants[0] : null;
  if (!axes.every((axis) => selection[axis.name])) return null;
  return variants.find((variant) => axes.every((axis) => variant.option_values[axis.name] === selection[axis.name])) ?? null;
}

/**
 * The selection the page opens with: an axis with one value is chosen for
 * the member, and a colour starts on the first one still in stock. Sizes are
 * never guessed.
 */
export function initialSelection(axes: ShopOptionAxis[], variants: ShopVariant[]): Selection {
  const selection: Selection = {};
  for (const axis of axes) {
    if (axis.values.length === 1) selection[axis.name] = axis.values[0];
  }
  const colour = axes.find((axis) => isColourAxis(axis) && !selection[axis.name]);
  if (colour) {
    const states = valueStates(colour, variants, selection);
    selection[colour.name] = colour.values.find((value) => states[value] === "available" || states[value] === "low") ?? colour.values[0];
  }
  return selection;
}

/** Choosing a value; one that has no variant with the rest of the selection clears the other axes. */
export function choose(axes: ShopOptionAxis[], variants: ShopVariant[], selection: Selection, axisName: string, value: string): Selection {
  const next = { ...selection, [axisName]: value };
  const exists = variants.some((variant) => matches(variant, next));
  return exists ? next : { [axisName]: value };
}

const COLOUR_NAMES = /^(χρώμα|χρωμα|colou?r|farbe|couleur|colore|cor|kleur|цвет|цвят|צבע|لون)$/iu;
const SIZE_NAMES = /^(μέγεθος|μεγεθος|size|größe|grösse|taille|taglia|tamanho|talla|maat|размер|מידה|مقاس|الحجم)$/iu;

export function isColourAxis(axis: ShopOptionAxis) {
  return axis.kind ? axis.kind === "colour" : COLOUR_NAMES.test(axis.name.trim());
}

export function isSizeAxis(axis: ShopOptionAxis) {
  return axis.kind ? axis.kind === "size" : SIZE_NAMES.test(axis.name.trim());
}

/** Units the member may add of a variant: stock, then the product's per-person limit. */
export function orderableUnits(variant: ShopVariant, perPersonLimit: number | null) {
  if (isSoldOut(variant)) return 0;
  const stock = variant.available;
  if (stock === null) return perPersonLimit;
  return perPersonLimit === null ? stock : Math.min(stock, perPersonLimit);
}

export type CardFlag = { kind: "sold_out" } | { kind: "last"; units: number } | { kind: "new" } | null;

/** What one grid card says: one card per product, its colours merged in. */
export function productCard(product: ShopProductSummary) {
  const live = product.variants;
  const prices = live.map((variant) => variant.price_cents);
  const fromPriceCents = prices.length > 0 ? Math.min(...prices) : null;
  const hasPriceRange = prices.length > 0 && Math.max(...prices) !== fromPriceCents;
  const inStock = live.filter((variant) => !isSoldOut(variant));
  const soldOut = live.length > 0 && inStock.length === 0;
  const tracked = inStock.filter((variant) => variant.available !== null);
  const left = tracked.length === inStock.length && inStock.length > 0 ? tracked.reduce((sum, variant) => sum + (variant.available ?? 0), 0) : null;
  const flag: CardFlag = soldOut
    ? { kind: "sold_out" }
    : left !== null && left <= LAST_UNITS_THRESHOLD
      ? { kind: "last", units: left }
      : product.is_new
        ? { kind: "new" }
        : null;
  const colour = product.options.axes.find(isColourAxis) ?? null;
  const size = product.options.axes.find(isSizeAxis) ?? null;
  return {
    fromPriceCents,
    hasPriceRange,
    currency: live[0]?.currency ?? null,
    soldOut,
    flag,
    colours: colour ? colour.values : [],
    sizeCount: size ? size.values.length : 0,
    variantCount: live.length,
  };
}
