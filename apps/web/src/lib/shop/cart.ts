/**
 * The member's shop cart (ADR-190), pure: lines, quantities and totals, all
 * money in integer cents. The totals mirror the API's `OrderPricing`
 * (member discount per line, rounded half up, never above the line), so the
 * checkout shows the amount the order will be placed at; the server still
 * prices the order itself.
 */

export const MAX_LINE_QUANTITY = 99;
export const MAX_CART_LINES = 50;

export type CartLine = { variantId: string; productId: string; quantity: number };

/** Where the cart was started, for the order's `source` (ADR-192 attribution). */
export type CartSource = { kind: "club_post"; id: string } | null;

export type Cart = { lines: CartLine[]; source: CartSource };

export const EMPTY_CART: Cart = { lines: [], source: null };

function clampQuantity(quantity: number, cap: number | null = null) {
  const max = cap === null ? MAX_LINE_QUANTITY : Math.min(MAX_LINE_QUANTITY, Math.max(0, Math.floor(cap)));
  if (!Number.isFinite(quantity)) return 0;
  return Math.max(0, Math.min(max, Math.floor(quantity)));
}

/**
 * Adds `quantity` of a variant, merging with a line already in the cart.
 * `available` (units the member can order, null = untracked) caps the line.
 */
export function addToCart(cart: Cart, line: CartLine, available: number | null = null): Cart {
  const existing = cart.lines.find((item) => item.variantId === line.variantId);
  if (!existing && cart.lines.length >= MAX_CART_LINES) return cart;
  const quantity = clampQuantity((existing?.quantity ?? 0) + line.quantity, available);
  if (quantity === 0) return cart;
  const lines = existing
    ? cart.lines.map((item) => (item.variantId === line.variantId ? { ...item, quantity } : item))
    : [...cart.lines, { ...line, quantity }];
  return { ...cart, lines };
}

/** Sets a line's quantity; 0 removes it. */
export function setLineQuantity(cart: Cart, variantId: string, quantity: number, available: number | null = null): Cart {
  const next = clampQuantity(quantity, available);
  const lines =
    next === 0
      ? cart.lines.filter((item) => item.variantId !== variantId)
      : cart.lines.map((item) => (item.variantId === variantId ? { ...item, quantity: next } : item));
  return { ...cart, lines, source: lines.length === 0 ? null : cart.source };
}

export function removeLine(cart: Cart, variantId: string): Cart {
  return setLineQuantity(cart, variantId, 0);
}

export function cartUnits(cart: Cart) {
  return cart.lines.reduce((sum, line) => sum + line.quantity, 0);
}

/** The member package discount on a line's gross amount (ADR-097): half up, never above it. */
export function lineDiscountCents(grossCents: number, applies: boolean, percent: number | null | undefined) {
  if (!applies || !percent || !Number.isInteger(percent) || percent <= 0 || percent > 100) return 0;
  return Math.min(grossCents, Math.floor((grossCents * percent + 50) / 100));
}

export type PricedVariant = {
  productId: string;
  unitPriceCents: number;
  memberDiscountApplies: boolean;
  currency: string;
};

export type PricedLine = CartLine & {
  unitPriceCents: number;
  grossCents: number;
  discountCents: number;
  totalCents: number;
};

export type CartTotals = {
  lines: PricedLine[];
  /** Lines whose variant is no longer sold (unpublished, archived): left out of the totals. */
  missing: string[];
  currency: string | null;
  subtotalCents: number;
  discountCents: number;
  totalCents: number;
};

/** Prices the cart against the catalogue the app has loaded. */
export function cartTotals(
  cart: Cart,
  catalog: ReadonlyMap<string, PricedVariant>,
  memberDiscountPercent: number | null | undefined,
): CartTotals {
  const lines: PricedLine[] = [];
  const missing: string[] = [];
  let currency: string | null = null;
  for (const line of cart.lines) {
    const variant = catalog.get(line.variantId);
    if (!variant || !Number.isInteger(variant.unitPriceCents) || variant.unitPriceCents < 0) {
      missing.push(line.variantId);
      continue;
    }
    currency ??= variant.currency;
    const grossCents = variant.unitPriceCents * line.quantity;
    const discountCents = lineDiscountCents(grossCents, variant.memberDiscountApplies, memberDiscountPercent);
    lines.push({ ...line, unitPriceCents: variant.unitPriceCents, grossCents, discountCents, totalCents: grossCents - discountCents });
  }
  const subtotalCents = lines.reduce((sum, line) => sum + line.grossCents, 0);
  const discountCents = lines.reduce((sum, line) => sum + line.discountCents, 0);
  return { lines, missing, currency, subtotalCents, discountCents, totalCents: subtotalCents - discountCents };
}

/** The member's price for one unit, for «Με το πακέτο σου: 22,50 €». */
export function memberUnitPriceCents(unitPriceCents: number, applies: boolean, percent: number | null | undefined) {
  return unitPriceCents - lineDiscountCents(unitPriceCents, applies, percent);
}

/** The order request's lines. */
export function cartItems(cart: Cart) {
  return cart.lines.map((line) => ({ variant_id: line.variantId, quantity: line.quantity }));
}

// Persistence (one cart per box, in the browser) ------------------------------

export function serializeCart(cart: Cart) {
  return JSON.stringify(cart);
}

/** Reads a stored cart, dropping anything malformed. */
export function parseCart(raw: string | null | undefined): Cart {
  if (!raw) return EMPTY_CART;
  try {
    const value = JSON.parse(raw) as { lines?: unknown; source?: unknown };
    const lines = Array.isArray(value.lines)
      ? value.lines
          .filter(
            (line): line is CartLine =>
              typeof line === "object" &&
              line !== null &&
              typeof (line as CartLine).variantId === "string" &&
              typeof (line as CartLine).productId === "string" &&
              Number.isInteger((line as CartLine).quantity) &&
              (line as CartLine).quantity > 0,
          )
          .slice(0, MAX_CART_LINES)
          .map((line) => ({ variantId: line.variantId, productId: line.productId, quantity: clampQuantity(line.quantity) }))
      : [];
    const source = value.source as CartSource;
    const validSource = source && source.kind === "club_post" && typeof source.id === "string" ? source : null;
    return { lines, source: lines.length > 0 ? validSource : null };
  } catch {
    return EMPTY_CART;
  }
}
