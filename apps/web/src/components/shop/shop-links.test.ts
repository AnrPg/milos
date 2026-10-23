import { describe, expect, it } from "vitest";

import { isShopNotification, shopNotificationText, shopNotificationUrl } from "./shop-links";

const t = (key: string, values?: Record<string, string | number>) => `${key} ${JSON.stringify(values ?? {})}`;

describe("shop notifications", () => {
  it("open the order in its box's shop", () => {
    expect(shopNotificationUrl("shop_order_ready", { order_id: "o-1", organization_slug: "kypseli" })).toBe("/box/shop/orders/o-1?box=kypseli");
    expect(shopNotificationUrl("shop_order_reminder", { order_id: "o-2" })).toBe("/box/shop/orders/o-2");
    expect(shopNotificationUrl("shop_order_cancelled", {})).toBe("/box/shop");
    expect(shopNotificationUrl("season_confirmed", { order_id: "o-1" })).toBeNull();
  });

  it("open the product a back-in-stock notice is about, on the web's singular route", () => {
    expect(isShopNotification("shop_back_in_stock")).toBe(true);
    expect(shopNotificationUrl("shop_back_in_stock", { product_id: "p-1", variant_id: "v-1", url: "/box/shop/products/p-1" })).toBe("/box/shop/product/p-1");
    expect(shopNotificationUrl("shop_back_in_stock", {})).toBe("/box/shop");
  });

  it("name the order, the place, the box and the product", () => {
    expect(shopNotificationText("shop_order_ready", { order_number: 1042, pickup_name: "Ρεσεψιόν" }, "body", t)).toBe(
      'notif.shop_order_ready.body {"number":"K-1042","box":"notif.theBox {}","place":"Ρεσεψιόν","product":"notif.theProduct {}"}',
    );
    expect(shopNotificationText("shop_back_in_stock", { product_title: "Box tee", variant_title: "M" }, "body", t)).toContain('"product":"Box tee · M"');
    expect(shopNotificationText("chat_message", {}, "title", t)).toBeNull();
  });
});
