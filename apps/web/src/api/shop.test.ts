import { describe, expect, it } from "vitest";

import { toQuote, toShopOrder, toShopProduct, toStorefront, type ApiMemberProduct, type ApiOrder } from "./shop";

const NOW = Date.parse("2026-10-23T12:00:00Z");

const product = (overrides: Partial<ApiMemberProduct> = {}): ApiMemberProduct => ({
  id: "p1",
  title: "Box tee",
  category: "Apparel",
  media_ids: [],
  options: { axes: [{ name: "Size", values: ["S", "M"] }] },
  per_person_limit: null,
  all_locations: true,
  location_ids: [],
  published_at: "2026-10-20T09:00:00Z",
  variants: [
    { id: "v1", title: "S", option_values: { Size: "S" }, price_cents: 2500, currency: "EUR", available: "in_stock" },
    { id: "v2", title: "M", option_values: { Size: "M" }, price_cents: 2500, currency: "EUR", available: "sold_out" },
    { id: "v3", title: "L", option_values: { Size: "L" }, price_cents: 2500, currency: "EUR", available: "low" },
  ],
  ...overrides,
});

describe("shop product adapter", () => {
  it("maps member availability to stock states without counts", () => {
    const mapped = toShopProduct(product(), NOW);
    expect(mapped.variants.map((variant) => [variant.stock_status, variant.available])).toEqual([
      ["ok", null],
      ["out", 0],
      ["low", null],
    ]);
  });

  it("marks a product new for 14 days and keeps branch limits", () => {
    expect(toShopProduct(product(), NOW).is_new).toBe(true);
    expect(toShopProduct(product({ published_at: "2026-10-01T09:00:00Z" }), NOW).is_new).toBe(false);
    expect(toShopProduct(product({ all_locations: false, location_ids: ["b1"] }), NOW).pickup_location_ids).toEqual(["b1"]);
    expect(toShopProduct(product(), NOW).pickup_location_ids).toEqual([]);
  });
});

describe("shop order adapter", () => {
  const order: ApiOrder = {
    id: "o1",
    number: 42,
    channel: "online",
    state: "pending_payment",
    pickup_code: "7Q4K",
    status: "placed",
    payment_status: "pending_payment",
    payment_mode: "at_pickup",
    pickup_location_id: "b1",
    currency: "EUR",
    subtotal_cents: 2500,
    discount_cents: 250,
    total_cents: 2250,
    placed_at: "2026-10-23T10:00:00Z",
    lines: [{ id: "l1", variant_id: "v1", product_title: "Box tee", variant_title: "S", quantity: 1, total_cents: 2250 }],
  };

  it("names the pickup branch and lets the buyer cancel an unpaid order before pickup", () => {
    const mapped = toShopOrder(order, [{ id: "b1", name: "Κυψέλη", hint: null }]);
    expect(mapped.pickup_location?.name).toBe("Κυψέλη");
    expect(mapped.can_cancel).toBe(true);
    expect(toShopOrder({ ...order, payment_status: "paid" }).can_cancel).toBe(false);
    expect(toShopOrder({ ...order, status: "ready_for_pickup" }).can_cancel).toBe(false);
  });

  it("carries the short pickup code, falling back to the order number", () => {
    expect(toShopOrder(order).pickup_code).toBe("7Q4K");
    expect(toShopOrder({ ...order, pickup_code: null }).pickup_code).toBe("42");
  });
});

describe("shop photos, storefront and quote adapters", () => {
  it("uses the thumbnail for tiles and keeps the full size, skipping media without a URL", () => {
    const mapped = toShopProduct(
      product({ media: [{ id: "m1", thumb_url: "https://cdn/t.jpg", full_url: "https://cdn/f.jpg", alt_text: "Tee" }, { id: "m2" }] }),
      NOW,
    );
    expect(mapped.photos).toEqual([{ id: "m1", url: "https://cdn/t.jpg", full_url: "https://cdn/f.jpg", alt: "Tee" }]);
    // The member presenter does not mark products: no member price is promised.
    expect(mapped.member_discount_applies).toBe(false);
  });

  it("reads the member discount, branches and online flag from the storefront", () => {
    const shop = toStorefront(
      {
        open: true,
        products: [product()],
        member_discount: { percent: 10 },
        pickup_locations: [{ id: "b1", name: "Κυψέλη", address: "Φωκίωνος 1" }],
        online_payment: { available: false, reason: "provider_unavailable" },
      },
      [],
      NOW,
    );
    expect(shop).toMatchObject({ open: true, published_count: 1, new_count: 1, member_discount_percent: 10 });
    expect(shop.pickup_locations).toEqual([{ id: "b1", name: "Κυψέλη", hint: "Φωκίωνος 1" }]);
    expect(shop.online_payment).toEqual({ available: false, reason: "provider_unavailable" });
    expect(toStorefront({ open: true, products: [], pickup_locations: [], online_payment: { available: false } }, []).open).toBe(false);
  });

  it("prices the basket with the member discount or the applied code", () => {
    const quote = toQuote({
      total_cents: 5841,
      subtotal_cents: 6490,
      discount_cents: 649,
      lines: [],
      member_discount: { percent: 10 },
      payment_modes: ["at_pickup", "online"],
      online_payment: { available: false },
      promotion_code: { code: "TEE10", applied: false },
    });
    expect(quote).toMatchObject({ member_discount_percent: 10, promotion_code: null, payment_modes: ["at_pickup", "online"] });
  });
});
