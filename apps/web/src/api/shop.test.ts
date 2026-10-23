import { describe, expect, it } from "vitest";

import { catalogView, orderActionRequest, productFromWire, salesFromWire, stockItemsFromCatalog } from "./shop";

const wireVariant = (extra: Record<string, unknown> = {}) => ({
  id: "v1",
  product_id: "p1",
  title: null,
  option_values: { Size: "M" },
  price_cents: 2500,
  track_inventory: true,
  stock_status: "ok" as const,
  archived_at: null,
  stock: {
    on_hand: 7,
    reserved: 2,
    available: 5,
    by_location: [
      { location_id: "loc-1", on_hand: 4, reserved: 2, available: 2 },
      { location_id: "loc-2", on_hand: 3, reserved: 0, available: 3 },
    ],
  },
  ...extra,
});

const wireProduct = (extra: Record<string, unknown> = {}) => ({
  id: "p1",
  title: "Box T-shirt",
  category: "Apparel",
  status: "published" as const,
  visibility: "members_only" as const,
  sell_in_app: true,
  sell_at_desk: true,
  member_discount_applies: false,
  all_locations: true,
  location_ids: [],
  media_ids: ["m1"],
  options: { axes: [{ name: "Size", values: ["M"] }] },
  variants: [wireVariant()],
  ...extra,
});

describe("wire shapes", () => {
  it("maps option axes, media ids and stock per branch", () => {
    const product = productFromWire(wireProduct());
    expect(product.options).toEqual([{ name: "Size", values: ["M"] }]);
    expect(product.media).toEqual([{ id: "m1" }]);
    expect(product.variants[0]).toMatchObject({
      on_hand: 7,
      reserved: 2,
      stock: [
        { location_id: "loc-1", on_hand: 4, reserved: 2 },
        { location_id: "loc-2", on_hand: 3, reserved: 0 },
      ],
    });
  });

  it("counts the filters and narrows by status, branch and search", () => {
    const shirt = productFromWire(wireProduct());
    const draft = productFromWire(wireProduct({ id: "p2", title: "Hoodie", status: "draft", all_locations: false, location_ids: ["loc-2"] }));
    const low = productFromWire(wireProduct({ id: "p3", title: "Bottle", category: "Gear", variants: [wireVariant({ id: "v3", stock_status: "low" })] }));
    const old = productFromWire(wireProduct({ id: "p4", status: "archived" }));

    const all = catalogView([shirt, draft, low], [old]);
    expect(all.counts).toEqual({ all: 3, published: 2, draft: 1, archived: 1, low_stock: 1 });
    expect(catalogView([shirt, draft, low], [old], { status: "low_stock" }).products.map((row) => row.id)).toEqual(["p3"]);
    expect(catalogView([shirt, draft, low], [old], { status: "archived" }).products.map((row) => row.id)).toEqual(["p4"]);
    expect(catalogView([shirt, draft, low], [old], { locationIds: "loc-1" }).counts.draft).toBe(0);
    expect(catalogView([shirt, draft, low], [old], { q: "gear" }).products.map((row) => row.id)).toEqual(["p3"]);
  });

  it("lists stock rows per variant and branch", () => {
    const product = productFromWire(wireProduct());
    const rows = stockItemsFromCatalog([product]);
    expect(rows.map((row) => [row.location_id, row.on_hand, row.variant_title])).toEqual([
      ["loc-1", 4, "M"],
      ["loc-2", 3, "M"],
    ]);
    expect(stockItemsFromCatalog([product], "loc-2").map((row) => row.location_id)).toEqual(["loc-2"]);
  });
});

describe("order actions", () => {
  it("sends refunds per order line with one idempotency key", () => {
    expect(orderActionRequest({ action: "refund", restock: true, lines: [{ line_id: "l1", quantity: 1 }, { line_id: "l2", quantity: 0 }] }, "refund-key-1")).toEqual({
      path: "refund",
      body: { lines: [{ order_line_id: "l1", quantity: 1, restock: true }], reason: null, idempotency_key: "refund-key-1" },
    });
    expect(orderActionRequest({ action: "pickup" })).toEqual({ path: "pickup", body: {} });
    expect(orderActionRequest({ action: "pickup", payment_method: "cash" })).toEqual({ path: "pickup", body: { payment_method: "cash" } });
  });
});

describe("sales report", () => {
  it("splits a doubled window into this period and the one before", () => {
    const day = (date: string, net: number) => ({ day: date, gross_cents: net, refunded_cents: 0, net_cents: net, orders: 1 });
    const report = salesFromWire({ series: [day("2026-10-20", 100), day("2026-10-21", 200), day("2026-10-22", 300), day("2026-10-23", 400)] }, 2);
    expect(report.days.map((row) => row.date)).toEqual(["2026-10-22", "2026-10-23"]);
    expect(report.totals).toMatchObject({ net_cents: 700, orders: 2, average_order_value_cents: 350 });
    expect(report.previous_totals).toMatchObject({ net_cents: 300 });
    expect(salesFromWire({ series: [day("2026-10-23", 400)] }, 2).previous_totals).toBeNull();
  });
});
