import { describe, expect, it } from "vitest";

import type { PricingRow, ShopProduct, ShopVariant } from "@/api/shop";
import {
  addOptionValue,
  addToCart,
  cartTotals,
  changePercent,
  combinationKey,
  costCoverage,
  daysOfStockTone,
  lastComparablePriceChange,
  memberDiscountPercent,
  movementFor,
  orderActions,
  paceOf,
  pickupNeedsPayment,
  priceAgainstRange,
  priceRange,
  productStock,
  reconcileVariants,
  refundableLines,
  revenueStreamRows,
  setCartQuantity,
  shares,
  stockMeterPercent,
  stockStateFromDays,
  suggestionReasoning,
  unpaidBalanceCents,
  variantCombinations,
  weeklyBuckets,
  worstStockStatus,
  type CartLine,
} from "./console";

const size = { name: "Μέγεθος", values: ["S", "M"] };
const colour = { name: "Χρώμα", values: ["Μαύρο", "Λευκό"] };

function variant(extra: Partial<ShopVariant> = {}): ShopVariant {
  return {
    id: "v1",
    option_values: {},
    price_cents: 2500,
    track_inventory: true,
    stock_status: "ok",
    stock: [],
    on_hand: 10,
    reserved: 0,
    ...extra,
  };
}

describe("variants", () => {
  it("combines up to two options and ignores empty ones", () => {
    expect(variantCombinations([])).toEqual([{}]);
    expect(variantCombinations([size, colour])).toEqual([
      { Μέγεθος: "S", Χρώμα: "Μαύρο" },
      { Μέγεθος: "S", Χρώμα: "Λευκό" },
      { Μέγεθος: "M", Χρώμα: "Μαύρο" },
      { Μέγεθος: "M", Χρώμα: "Λευκό" },
    ]);
    expect(variantCombinations([size, { name: "", values: ["x"] }, colour, { name: "Τρίτη", values: ["a"] }])).toHaveLength(4);
  });

  it("keys a combination by option order, not object order", () => {
    expect(combinationKey({ Χρώμα: "Μαύρο", Μέγεθος: "M" }, [size, colour])).toBe("M · Μαύρο");
  });

  it("keeps existing rows and adds new combinations at the base price", () => {
    const existing = [{ key: "S", id: "v-s", option_values: { Μέγεθος: "S" }, price_cents: 3000 }];
    const next = reconcileVariants([{ ...size, values: ["S", "L"] }], existing, 2500);
    expect(next).toEqual([
      { key: "S", id: "v-s", option_values: { Μέγεθος: "S" }, price_cents: 3000 },
      { key: "L", option_values: { Μέγεθος: "L" }, price_cents: 2500 },
    ]);
  });

  it("adds an option value once", () => {
    expect(addOptionValue(size, " m ").values).toEqual(["S", "M"]);
    expect(addOptionValue(size, "XL").values).toEqual(["S", "M", "XL"]);
    expect(addOptionValue(size, "  ")).toBe(size);
  });
});

describe("stock", () => {
  it("picks the worst state", () => {
    expect(worstStockStatus(["ok", "low", "critical"])).toBe("critical");
    expect(worstStockStatus([])).toBe("ok");
  });

  it("derives the state from days of stock", () => {
    expect(stockStateFromDays(3, 0)).toBe("out");
    expect(stockStateFromDays(6, 4)).toBe("critical");
    expect(stockStateFromDays(9, 1)).toBe("low");
    expect(stockStateFromDays(40, 10)).toBe("ok");
    expect(stockStateFromDays(null, 10)).toBe("ok");
  });

  it("summarises a product's stock and its weakest variant", () => {
    const product = {
      variants: [
        variant({ id: "a", on_hand: 5, reserved: 1 }),
        variant({ id: "b", on_hand: 1, stock_status: "low" }),
        variant({ id: "c", on_hand: 0, stock_status: "out", archived_at: "2026-10-01" }),
      ],
    } as Pick<ShopProduct, "variants">;
    const stock = productStock(product);
    expect(stock.available).toBe(5);
    expect(stock.status).toBe("low");
    expect(stock.weakest?.id).toBe("b");
  });

  it("fills the meter against the reorder level", () => {
    expect(stockMeterPercent(10)).toBe(50);
    expect(stockMeterPercent(10, 10)).toBe(25);
    expect(stockMeterPercent(-3)).toBe(0);
    expect(stockMeterPercent(99)).toBe(100);
  });

  it("gives the price range of live variants", () => {
    expect(priceRange([])).toBeNull();
    expect(priceRange([{ price_cents: 2500 }, { price_cents: 2900 }, { price_cents: 100, archived_at: "x" }])).toEqual({ min: 2500, max: 2900 });
  });
});

describe("stock form", () => {
  const item = { variant_id: "v1", location_id: "loc-1", on_hand: 4 };

  it("records deliveries, recounts and write-offs", () => {
    expect(movementFor(item, "receive", 10, 1100, " Τιμολόγιο 0891 ")).toEqual({
      variant_id: "v1",
      location_id: "loc-1",
      note: "Τιμολόγιο 0891",
      kind: "receive",
      quantity: 10,
      unit_cost_cents: 1100,
    });
    expect(movementFor(item, "recount", 3, null, "")).toMatchObject({ kind: "adjustment", reason: "recount", quantity: -1, note: null });
    expect(movementFor(item, "damage", 2, null, "")).toMatchObject({ reason: "damage", quantity: -2 });
    expect(movementFor(item, "return", 1, null, "")).toMatchObject({ reason: "return", quantity: 1 });
  });

  it("refuses an entry that changes nothing", () => {
    expect(movementFor(item, "recount", 4, null, "")).toBeNull();
    expect(movementFor(item, "receive", 0, null, "")).toBeNull();
    expect(movementFor(item, "loss", -1, null, "")).toBeNull();
  });
});

describe("orders", () => {
  it("offers the next steps of the lifecycle", () => {
    expect(orderActions({ status: "placed", paid_cents: 0, refunded_cents: 0 })).toEqual(["ready", "cancel"]);
    expect(orderActions({ status: "ready_for_pickup", paid_cents: 0, refunded_cents: 0 })).toEqual(["pickup", "cancel"]);
    expect(orderActions({ status: "picked_up", paid_cents: 5000, refunded_cents: 0 })).toEqual(["refund"]);
    expect(orderActions({ status: "picked_up", paid_cents: 5000, refunded_cents: 5000 })).toEqual([]);
    expect(orderActions({ status: "cancelled", paid_cents: 0, refunded_cents: 0 })).toEqual([]);
  });

  it("asks for a payment at pickup only while money is owed", () => {
    expect(pickupNeedsPayment({ total_cents: 5841, paid_cents: 0 })).toBe(true);
    expect(pickupNeedsPayment({ total_cents: 5841, paid_cents: 5841 })).toBe(false);
  });

  it("lists what a refund can still return", () => {
    const lines = [
      { id: "l1", quantity: 2, refunded_quantity: 1 },
      { id: "l2", quantity: 1, refunded_quantity: 1 },
    ] as never;
    expect(refundableLines({ lines }).map((entry) => [entry.line.id, entry.remaining])).toEqual([["l1", 1]]);
  });
});

describe("desk cart", () => {
  const bar: Omit<CartLine, "quantity"> = {
    variantId: "bar",
    productTitle: "Μπάρα",
    variantTitle: "Φιστίκι",
    unitPriceCents: 250,
    memberDiscount: true,
    available: 1,
  };
  const chalk: Omit<CartLine, "quantity"> = { ...bar, variantId: "chalk", productTitle: "Μαγνησία", unitPriceCents: 600, memberDiscount: false, available: null };

  it("adds, merges and removes lines", () => {
    let cart = addToCart([], bar);
    cart = addToCart(cart, bar);
    cart = addToCart(cart, chalk);
    expect(cart.map((line) => [line.variantId, line.quantity])).toEqual([["bar", 2], ["chalk", 1]]);
    expect(setCartQuantity(cart, "bar", 0).map((line) => line.variantId)).toEqual(["chalk"]);
  });

  it("applies the member discount to eligible lines and flags short stock", () => {
    const cart = setCartQuantity(addToCart(addToCart([], bar), chalk), "bar", 2);
    expect(cartTotals(cart, 10)).toEqual({ subtotalCents: 1100, discountCents: 50, totalCents: 1050, shortLines: ["bar"] });
    expect(cartTotals(cart, null).discountCents).toBe(0);
  });

  it("sums the unpaid balance and finds the package discount", () => {
    expect(
      unpaidBalanceCents([
        { status: "issued", balance_due_cents: 5841 },
        { status: "paid", balance_due_cents: 0 },
        { status: "overdue", balance_due_cents: 1000 },
        { status: "void", balance_due_cents: 900 },
      ]),
    ).toBe(6841);
    expect(memberDiscountPercent([{ status: "active", member_discount_percent: 10 }, { status: "expired", member_discount_percent: 30 }])).toBe(10);
    expect(memberDiscountPercent([])).toBeNull();
  });
});

describe("analytics", () => {
  it("compares with the previous window", () => {
    expect(changePercent(118, 100)).toBe(18);
    expect(changePercent(10, 0)).toBeNull();
    expect(changePercent(10, null)).toBeNull();
  });

  it("sums days into Monday weeks and marks the running one", () => {
    const weeks = weeklyBuckets(
      [
        { date: "2026-10-12", net_cents: 100, orders: 1 },
        { date: "2026-10-18", net_cents: 50, orders: 1 },
        { date: "2026-10-19", net_cents: 70, orders: 2 },
      ],
      "2026-10-23",
    );
    expect(weeks).toEqual([
      { weekStart: "2026-10-12", netCents: 150, orders: 2, partial: false },
      { weekStart: "2026-10-19", netCents: 70, orders: 2, partial: true },
    ]);
  });

  it("rounds shares down", () => {
    expect(shares([1, 1, 1], (value) => value).map((entry) => entry.percent)).toEqual([33, 33, 33]);
    expect(shares([0, 0], (value) => value).map((entry) => entry.percent)).toEqual([0, 0]);
  });

  it("counts products with a cost", () => {
    expect(
      costCoverage([
        { cost_cents: 100, costed_revenue_cents: 500, net_revenue_cents: 500 },
        { cost_cents: 0, costed_revenue_cents: 0, net_revenue_cents: 300 },
        { cost_cents: 0, costed_revenue_cents: 0, net_revenue_cents: 0 },
      ]),
    ).toEqual({ costed: 1, total: 2 });
  });

  it("reads pace against the category median", () => {
    expect(paceOf(3, 2)).toBe("fast");
    expect(paceOf(1, 2)).toBe("slow");
    expect(paceOf(2, 2)).toBe("normal");
    expect(paceOf(null, 2)).toBe("unknown");
    expect(paceOf(2, 0)).toBe("unknown");
  });

  const suggestion: PricingRow["suggested_price"] = {
    advisory: true,
    low_cents: 1833,
    high_cents: 2017,
    inputs: {
      cost_cents: 1100,
      current_price_cents: 2500,
      target_margin_bp: 4000,
      target_margin_source: "default",
      velocity_per_week: 6,
      category_median_velocity_per_week: 3,
      elasticity: -1.4,
      elasticity_confidence: "medium",
    },
  };

  it("explains the advisory range from its inputs", () => {
    expect(suggestionReasoning(suggestion)).toEqual({
      targetMarginPercent: 40,
      targetFromCategory: false,
      pace: "fast",
      priceSensitive: true,
      costKnown: true,
    });
    expect(priceAgainstRange({ price_cents: 2500, suggested_price: suggestion })).toBe("above");
    expect(priceAgainstRange({ price_cents: 1900, suggested_price: suggestion })).toBe("within");
    expect(priceAgainstRange({ price_cents: 1900, suggested_price: { ...suggestion, low_cents: null } })).toBeNull();
  });

  it("picks the last price change with enough evidence", () => {
    const change = { changed_on: "2026-09-01", from_price_cents: 2200, to_price_cents: 2500, price_change_percent: 13.6, velocity_before: 4, velocity_after: 3, velocity_change_percent: -25, evidence: "sufficient" as const };
    expect(lastComparablePriceChange({ price_changes: [change, { ...change, changed_on: "2026-10-20", evidence: "insufficient" }] })?.changed_on).toBe("2026-09-01");
    expect(lastComparablePriceChange({ price_changes: [] })).toBeNull();
  });

  it("tones days of stock", () => {
    expect(daysOfStockTone(3)).toBe("danger");
    expect(daysOfStockTone(9)).toBe("warning");
    expect(daysOfStockTone(60)).toBe("neutral");
    expect(daysOfStockTone(null)).toBe("neutral");
  });
});

describe("revenue streams", () => {
  it("orders the streams and hides an empty «other»", () => {
    const rows = revenueStreamRows({ totals: { revenue_by_stream: { membership: 8420, package: 2180, event: 360, shop: 1103, other: 0 } } });
    expect(rows?.map((row) => row.stream)).toEqual(["membership", "package", "event", "shop"]);
    expect(rows?.find((row) => row.stream === "shop")?.percent).toBe(9);
  });

  it("prefers the per-stream rows and returns null before the API has them", () => {
    const rows = revenueStreamRows({ revenue_streams: [{ stream: "shop", net_cents: 500 }, { stream: "other", net_cents: 500 }] });
    expect(rows?.map((row) => [row.stream, row.netCents])).toEqual([["membership", 0], ["package", 0], ["event", 0], ["shop", 500], ["other", 500]]);
    expect(revenueStreamRows({ totals: {} })).toBeNull();
    expect(revenueStreamRows(null)).toBeNull();
  });
});
