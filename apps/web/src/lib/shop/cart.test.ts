import { describe, expect, it } from "vitest";

import {
  EMPTY_CART,
  MAX_LINE_QUANTITY,
  addToCart,
  cartItems,
  cartTotals,
  cartUnits,
  lineDiscountCents,
  memberUnitPriceCents,
  parseCart,
  removeLine,
  serializeCart,
  setLineQuantity,
  type PricedVariant,
} from "./cart";

const tee = { variantId: "tee-m", productId: "tee", quantity: 1 };
const whey = { variantId: "whey-choc", productId: "whey", quantity: 1 };

const catalog = new Map<string, PricedVariant>([
  ["tee-m", { productId: "tee", unitPriceCents: 2500, memberDiscountApplies: true, currency: "EUR" }],
  ["whey-choc", { productId: "whey", unitPriceCents: 3990, memberDiscountApplies: true, currency: "EUR" }],
  ["bar", { productId: "bar", unitPriceCents: 225, memberDiscountApplies: false, currency: "EUR" }],
]);

describe("cart lines", () => {
  it("merges the same variant into one line and caps it at the stock", () => {
    let cart = addToCart(EMPTY_CART, tee);
    cart = addToCart(cart, { ...tee, quantity: 2 }, 2);
    expect(cart.lines).toEqual([{ ...tee, quantity: 2 }]);
    expect(cartUnits(addToCart(cart, whey))).toBe(3);
  });

  it("never goes above the line maximum and ignores sold-out adds", () => {
    expect(addToCart(EMPTY_CART, { ...tee, quantity: 500 }).lines[0].quantity).toBe(MAX_LINE_QUANTITY);
    expect(addToCart(EMPTY_CART, tee, 0)).toBe(EMPTY_CART);
  });

  it("removes a line at zero and forgets the source with the last line", () => {
    const cart = { ...addToCart(EMPTY_CART, tee), source: { kind: "club_post" as const, id: "post-1" } };
    expect(setLineQuantity(cart, "tee-m", 3).lines[0].quantity).toBe(3);
    expect(removeLine(cart, "tee-m")).toEqual(EMPTY_CART);
  });

  it("builds the order request's lines", () => {
    expect(cartItems(addToCart(addToCart(EMPTY_CART, tee), whey))).toEqual([
      { variant_id: "tee-m", quantity: 1 },
      { variant_id: "whey-choc", quantity: 1 },
    ]);
  });
});

describe("cart totals in integer cents", () => {
  it("applies the package discount per line, half up, as the API does", () => {
    // The mockup's cart: 25,00 + 39,90 = 64,90 with −10% → 2,50 + 3,99 = 6,49 → 58,41.
    const cart = addToCart(addToCart(EMPTY_CART, tee), whey);
    const totals = cartTotals(cart, catalog, 10);
    expect(totals.subtotalCents).toBe(6490);
    expect(totals.discountCents).toBe(649);
    expect(totals.totalCents).toBe(5841);
    expect(totals.lines.map((line) => line.totalCents)).toEqual([2250, 3591]);
    expect(totals.currency).toBe("EUR");
  });

  it("leaves products without the member discount at full price", () => {
    const cart = addToCart(EMPTY_CART, { variantId: "bar", productId: "bar", quantity: 3 });
    expect(cartTotals(cart, catalog, 10)).toMatchObject({ subtotalCents: 675, discountCents: 0, totalCents: 675 });
  });

  it("drops lines that are no longer sold and reports them", () => {
    const cart = addToCart(addToCart(EMPTY_CART, tee), { variantId: "gone", productId: "x", quantity: 1 });
    const totals = cartTotals(cart, catalog, null);
    expect(totals.missing).toEqual(["gone"]);
    expect(totals.totalCents).toBe(2500);
  });

  it("rounds half up and never discounts more than the line", () => {
    expect(lineDiscountCents(5, true, 10)).toBe(1); // 0.5 → 1
    expect(lineDiscountCents(4, true, 10)).toBe(0); // 0.4 → 0
    expect(lineDiscountCents(999, true, 100)).toBe(999);
    expect(lineDiscountCents(999, true, 150)).toBe(0);
    expect(lineDiscountCents(999, false, 10)).toBe(0);
    expect(memberUnitPriceCents(2500, true, 10)).toBe(2250);
  });
});

describe("stored cart", () => {
  it("round-trips and drops malformed lines", () => {
    const cart = { ...addToCart(EMPTY_CART, tee), source: { kind: "club_post" as const, id: "p" } };
    expect(parseCart(serializeCart(cart))).toEqual(cart);
    expect(parseCart('{"lines":[{"variantId":"a","productId":"b","quantity":-1},{"variantId":3}]}')).toEqual(EMPTY_CART);
    expect(parseCart("not json")).toEqual(EMPTY_CART);
    expect(parseCart(null)).toEqual(EMPTY_CART);
  });
});
