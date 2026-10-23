// Pure helpers of the shop console («Κατάστημα»): variants from options,
// stock states, order actions, the desk cart, and the KPI labels of
// «Αναλυτικά». No React, no fetching: the components and hooks call these.

import type {
  OrderAction,
  PricingRow,
  ShopOption,
  ShopOrder,
  ShopMovementInput,
  ShopProduct,
  ShopStockItem,
  ShopStockStatus,
  ShopVariant,
  ShopVariantInput,
} from "@/api/shop-admin";

/** The proposal allows up to two options per product (e.g. size × colour). */
export const MAX_OPTIONS = 2;

// ---- variants ----

/** Every combination of the options' values, in option order; one empty combination without options. */
export function variantCombinations(options: ShopOption[]): Record<string, string>[] {
  const usable = options.filter((option) => option.name.trim() && option.values.length > 0).slice(0, MAX_OPTIONS);
  return usable.reduce<Record<string, string>[]>(
    (combinations, option) =>
      combinations.flatMap((combination) => option.values.map((value) => ({ ...combination, [option.name.trim()]: value }))),
    [{}],
  );
}

/** A stable key of one combination, independent of object key order. */
export function combinationKey(values: Record<string, string>, options: ShopOption[]): string {
  const names = options.map((option) => option.name.trim()).filter(Boolean);
  return names.map((name) => values[name] ?? "").join(" · ");
}

export type VariantDraft = ShopVariantInput & { key: string };

/**
 * The variant rows for the current options: existing rows keep their id,
 * prices and stock; new combinations start at the product price.
 */
export function reconcileVariants(options: ShopOption[], existing: VariantDraft[], basePriceCents: number): VariantDraft[] {
  const byKey = new Map(existing.map((variant) => [variant.key, variant]));
  return variantCombinations(options).map((values) => {
    const key = combinationKey(values, options);
    const known = byKey.get(key);
    return known ? { ...known, option_values: values } : { key, option_values: values, price_cents: basePriceCents };
  });
}

export function draftsFromProduct(product: Pick<ShopProduct, "options" | "variants">): VariantDraft[] {
  return product.variants
    .filter((variant) => !variant.archived_at)
    .map((variant) => ({
      key: combinationKey(variant.option_values, product.options),
      id: variant.id,
      option_values: variant.option_values,
      sku: variant.sku ?? null,
      price_cents: variant.price_cents,
      compare_at_price_cents: variant.compare_at_price_cents ?? null,
      cost_price_cents: variant.cost_price_cents ?? null,
      low_stock_threshold: variant.low_stock_threshold ?? null,
      track_inventory: variant.track_inventory,
    }));
}

/** Adds a value to an option once (trimmed, case-insensitive); returns the same list when nothing changes. */
export function addOptionValue(option: ShopOption, raw: string): ShopOption {
  const value = raw.trim();
  if (!value || option.values.some((existing) => existing.toLocaleLowerCase() === value.toLocaleLowerCase())) return option;
  return { ...option, values: [...option.values, value] };
}

// ---- stock ----

const STOCK_RANK: Record<ShopStockStatus, number> = { out: 0, critical: 1, low: 2, ok: 3 };

export function worstStockStatus(statuses: ShopStockStatus[]): ShopStockStatus {
  return statuses.reduce<ShopStockStatus>((worst, status) => (STOCK_RANK[status] < STOCK_RANK[worst] ? status : worst), "ok");
}

export function needsAttention(status: ShopStockStatus) {
  return status !== "ok";
}

/** Stock days → state, as ADR-104's StockPolicy: critical under 7 days, low under 21. */
export function stockStateFromDays(daysLeft: number | null | undefined, onHand: number): ShopStockStatus {
  if (onHand <= 0) return "out";
  if (daysLeft === null || daysLeft === undefined) return "ok";
  if (daysLeft < 7) return "critical";
  if (daysLeft < 21) return "low";
  return "ok";
}

export type ProductStock = {
  available: number;
  status: ShopStockStatus;
  /** The variant that needs attention first, if any. */
  weakest: Pick<ShopVariant, "id" | "option_values" | "on_hand" | "reserved" | "stock_status"> | null;
};

export function productStock(product: Pick<ShopProduct, "variants">): ProductStock {
  const variants = product.variants.filter((variant) => !variant.archived_at && variant.track_inventory);
  const available = variants.reduce((sum, variant) => sum + Math.max(variant.on_hand - variant.reserved, 0), 0);
  const status = variants.length === 0 ? "ok" : worstStockStatus(variants.map((variant) => variant.stock_status));
  const weakest =
    [...variants]
      .filter((variant) => needsAttention(variant.stock_status))
      .sort((a, b) => STOCK_RANK[a.stock_status] - STOCK_RANK[b.stock_status] || a.on_hand - b.on_hand)[0] ?? null;
  return { available, status, weakest };
}

/** Fill of the stock meter, 0–100: against four times the reorder level, or 20 units when none is set. */
export function stockMeterPercent(available: number, lowThreshold?: number | null) {
  const full = Math.max((lowThreshold ?? 0) * 4, 20);
  return Math.round(Math.min(Math.max(available, 0) / full, 1) * 100);
}

/** The price shown in the list: one price, or the lowest when variants differ. */
export function priceRange(variants: Pick<ShopVariant, "price_cents" | "archived_at">[]): { min: number; max: number } | null {
  const prices = variants.filter((variant) => !variant.archived_at).map((variant) => variant.price_cents);
  if (prices.length === 0) return null;
  return { min: Math.min(...prices), max: Math.max(...prices) };
}

/** What happened to the stock, which is also the ledger reason: a delivery, or an adjustment and why. */
export type StockFormKind = "receive" | "recount" | "damage" | "loss" | "return";

/**
 * The ledger entry for the stock form's answer: a delivery adds, a recount
 * records the difference from what is on hand, damage and loss take away, a
 * return adds back. Null when nothing would change.
 */
export function movementFor(
  item: Pick<ShopStockItem, "variant_id" | "location_id" | "on_hand">,
  kind: StockFormKind,
  amount: number,
  unitCostCents: number | null,
  note: string,
): ShopMovementInput | null {
  if (!Number.isInteger(amount) || amount < 0) return null;
  const base = { variant_id: item.variant_id, location_id: item.location_id, note: note.trim() || null };
  if (kind === "receive") return amount > 0 ? { ...base, kind: "receive", quantity: amount, unit_cost_cents: unitCostCents } : null;
  // A recount sends what is on the shelf; the server books the difference.
  if (kind === "recount") return amount !== item.on_hand ? { ...base, kind: "recount", counted: amount } : null;
  if (amount === 0) return null;
  return { ...base, kind: "adjustment", reason: kind, quantity: kind === "return" ? amount : -amount };
}

/** How much a movement changes the stock on hand. */
export function stockDelta(movement: Pick<ShopMovementInput, "kind" | "quantity" | "counted">, onHand: number) {
  if (movement.kind === "recount") return (movement.counted ?? onHand) - onHand;
  return movement.quantity ?? 0;
}

// ---- orders ----

export type OrderActionName = OrderAction["action"];

/** What staff can do next with an order: prepare → ready → picked up; cancel before pickup, refund after. */
export function orderActions(order: Pick<ShopOrder, "status" | "paid_cents" | "refunded_cents">): OrderActionName[] {
  switch (order.status) {
    case "placed":
      return ["ready", "cancel"];
    case "ready_for_pickup":
      return ["pickup", "cancel"];
    case "picked_up":
      return order.paid_cents - order.refunded_cents > 0 ? ["refund"] : [];
    default:
      return [];
  }
}

/** A pickup records a payment only while something is still owed. */
export function pickupNeedsPayment(order: Pick<ShopOrder, "total_cents" | "paid_cents">) {
  return order.total_cents - order.paid_cents > 0;
}

/** «K-1042», the number staff read out. */
export function orderLabel(order: Pick<ShopOrder, "number">) {
  return `K-${order.number}`;
}

/** Lines a refund can still return: what was bought minus what was refunded. */
export function refundableLines(order: Pick<ShopOrder, "lines">) {
  return order.lines
    .map((line) => ({ line, remaining: line.quantity - line.refunded_quantity }))
    .filter((entry) => entry.remaining > 0);
}

// ---- the desk cart (Ταμείο) ----

export type CartLine = {
  variantId: string;
  productTitle: string;
  variantTitle: string | null;
  unitPriceCents: number;
  quantity: number;
  /** ADR-097: the member's package discount applies to this product. */
  memberDiscount: boolean;
  /** On hand minus reserved when the line was added; the desk warns, it does not block. */
  available: number | null;
};

export function addToCart(cart: CartLine[], line: Omit<CartLine, "quantity">, quantity = 1): CartLine[] {
  const existing = cart.find((entry) => entry.variantId === line.variantId);
  if (existing) return cart.map((entry) => (entry === existing ? { ...entry, quantity: entry.quantity + quantity } : entry));
  return [...cart, { ...line, quantity }];
}

export function setCartQuantity(cart: CartLine[], variantId: string, quantity: number): CartLine[] {
  if (quantity <= 0) return cart.filter((entry) => entry.variantId !== variantId);
  return cart.map((entry) => (entry.variantId === variantId ? { ...entry, quantity } : entry));
}

export type CartTotals = { subtotalCents: number; discountCents: number; totalCents: number; shortLines: string[] };

/**
 * Totals of the desk cart. The member discount is a percent of each eligible
 * line, rounded half up per line (as Finance rounds invoice lines); a walk-in
 * gets none. `shortLines` are the variants with less stock than asked.
 */
export function cartTotals(cart: CartLine[], memberDiscountPercent: number | null): CartTotals {
  const percent = memberDiscountPercent && memberDiscountPercent > 0 ? Math.min(memberDiscountPercent, 100) : 0;
  let subtotalCents = 0;
  let discountCents = 0;
  const shortLines: string[] = [];
  for (const line of cart) {
    const lineTotal = line.unitPriceCents * line.quantity;
    subtotalCents += lineTotal;
    if (percent && line.memberDiscount) discountCents += Math.round((lineTotal * percent) / 100);
    if (line.available !== null && line.quantity > line.available) shortLines.push(line.variantId);
  }
  return { subtotalCents, discountCents, totalCents: subtotalCents - discountCents, shortLines };
}

/** The member's unpaid balance: what is still due on issued, partly paid and overdue invoices. */
export function unpaidBalanceCents(invoices: Record<string, unknown>[]): number {
  return invoices.reduce((sum, invoice) => {
    const status = String(invoice.status ?? "");
    const due = typeof invoice.balance_due_cents === "number" ? invoice.balance_due_cents : 0;
    return ["issued", "partially_paid", "overdue"].includes(status) && due > 0 ? sum + due : sum;
  }, 0);
}

/** The highest member discount among the member's active packages (ADR-097), or null. */
export function memberDiscountPercent(subscriptions: Record<string, unknown>[]): number | null {
  const percents = subscriptions
    .filter((subscription) => !subscription.status || subscription.status === "active")
    .map((subscription) => Number(subscription.member_discount_percent ?? 0))
    .filter((value) => Number.isFinite(value) && value > 0);
  return percents.length ? Math.max(...percents) : null;
}

// ---- «Αναλυτικά» ----

/** Change against the previous window, in whole percent; null when there is nothing to compare with. */
export function changePercent(current: number, previous: number | null | undefined): number | null {
  if (previous === null || previous === undefined || previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 100);
}

export type WeekBucket = { weekStart: string; netCents: number; orders: number; partial: boolean };

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

function mondayOf(day: string) {
  const date = new Date(`${day}T00:00:00Z`);
  const offset = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - offset);
  return isoDate(date);
}

/**
 * Gym-local days (already bucketed by the server) summed into Monday weeks.
 * The week holding `today` is still in progress and is marked `partial`.
 */
export function weeklyBuckets(days: { date: string; net_cents: number; orders: number }[], today: string): WeekBucket[] {
  const weeks = new Map<string, WeekBucket>();
  const currentWeek = mondayOf(today);
  for (const day of days) {
    const weekStart = mondayOf(day.date);
    const bucket = weeks.get(weekStart) ?? { weekStart, netCents: 0, orders: 0, partial: weekStart === currentWeek };
    bucket.netCents += day.net_cents;
    bucket.orders += day.orders;
    weeks.set(weekStart, bucket);
  }
  return [...weeks.values()].sort((a, b) => a.weekStart.localeCompare(b.weekStart));
}

/** Share of each row in the whole, whole percent; rounding never makes the total pass 100. */
export function shares<T>(rows: T[], value: (row: T) => number): { row: T; percent: number }[] {
  const total = rows.reduce((sum, row) => sum + Math.max(value(row), 0), 0);
  return rows.map((row) => ({ row, percent: total > 0 ? Math.floor((Math.max(value(row), 0) / total) * 100) : 0 }));
}

/** «6/7 προϊόντα»: how many products carry a cost, so margin is never read as covering all of them. */
export function costCoverage(rows: { cost_cents: number; costed_revenue_cents: number; net_revenue_cents: number }[]) {
  const sold = rows.filter((row) => row.net_revenue_cents > 0);
  const costed = sold.filter((row) => row.costed_revenue_cents > 0);
  return { costed: costed.length, total: sold.length };
}

export type Pace = "fast" | "normal" | "slow" | "unknown";

// Mirrors Palee.Shop.Domain.PricingIndicators (ADR-192): 1.5× / 0.5× the category's median pace.
const FAST_RATIO = 1.5;
const SLOW_RATIO = 0.5;

export function paceOf(velocity: number | null | undefined, categoryMedian: number | null | undefined): Pace {
  if (velocity === null || velocity === undefined || !categoryMedian) return "unknown";
  if (velocity >= categoryMedian * FAST_RATIO) return "fast";
  if (velocity <= categoryMedian * SLOW_RATIO) return "slow";
  return "normal";
}

export type Reasoning = {
  /** Target margin in whole percent (from basis points). */
  targetMarginPercent: number;
  targetFromCategory: boolean;
  pace: Pace;
  /** Fast but price-sensitive: the upward room is halved. */
  priceSensitive: boolean;
  costKnown: boolean;
};

/**
 * The inputs of the advisory price range, in the terms the screen explains
 * them (the server's explanation strings are English, so the screen builds
 * its own sentence from these).
 */
export function suggestionReasoning(suggestion: PricingRow["suggested_price"]): Reasoning {
  const inputs = suggestion.inputs;
  const priceSensitive =
    inputs.elasticity !== null && inputs.elasticity <= -1 && (inputs.elasticity_confidence === "medium" || inputs.elasticity_confidence === "high");
  return {
    targetMarginPercent: Math.round(inputs.target_margin_bp / 100),
    targetFromCategory: inputs.target_margin_source === "category_setting",
    pace: paceOf(inputs.velocity_per_week, inputs.category_median_velocity_per_week),
    priceSensitive,
    costKnown: inputs.cost_cents !== null,
  };
}

/** The most recent price change with enough days on both sides to compare, if any. */
export function lastComparablePriceChange(row: Pick<PricingRow, "price_changes">) {
  const comparable = row.price_changes.filter((change) => change.evidence === "sufficient");
  return comparable[comparable.length - 1] ?? null;
}

/** Where the current price sits against the advisory range. */
export function priceAgainstRange(row: Pick<PricingRow, "price_cents" | "suggested_price">): "below" | "within" | "above" | null {
  const { low_cents: low, high_cents: high } = row.suggested_price;
  if (low === null || high === null) return null;
  if (row.price_cents < low) return "below";
  if (row.price_cents > high) return "above";
  return "within";
}

/** «Ημέρες αποθέματος» band, the same thresholds as the stock state. */
export function daysOfStockTone(days: number | null | undefined): "danger" | "warning" | "neutral" {
  if (days === null || days === undefined) return "neutral";
  if (days < 7) return "danger";
  if (days < 21) return "warning";
  return "neutral";
}

// ---- finance: revenue by stream (ADR-192 §2) ----

export const REVENUE_STREAMS = ["membership", "package", "event", "shop", "other"] as const;
export type RevenueStream = (typeof REVENUE_STREAMS)[number];

export type StreamRow = { stream: RevenueStream; netCents: number; percent: number };

/** The stream rows in a fixed order (stable layout), from `revenue_streams` or `totals.revenue_by_stream`. */
export function revenueStreamRows(summary: Record<string, unknown> | null | undefined): StreamRow[] | null {
  if (!summary) return null;
  const rows = Array.isArray(summary.revenue_streams) ? (summary.revenue_streams as Record<string, unknown>[]) : null;
  const totals = (summary.totals ?? {}) as Record<string, unknown>;
  const byStream = (totals.revenue_by_stream ?? null) as Record<string, unknown> | null;
  if (!rows && !byStream) return null;
  const net = (stream: RevenueStream) => {
    const row = rows?.find((entry) => entry.stream === stream);
    const value = row ? row.net_cents : byStream?.[stream];
    return typeof value === "number" ? value : Number(value ?? 0) || 0;
  };
  const values = REVENUE_STREAMS.map((stream) => ({ stream, netCents: net(stream) }));
  const withShares = shares(values, (row) => row.netCents);
  // «Άλλα» shows only when it holds money; the four named streams always keep their rows.
  return withShares
    .map(({ row, percent }) => ({ ...row, percent }))
    .filter((row) => row.stream !== "other" || row.netCents !== 0);
}
