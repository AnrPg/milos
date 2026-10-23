import { describe, expect, it } from "vitest";

import { shopNotificationText, shopNotificationUrl } from "./shop-links";

describe("shop notifications", () => {
  it("open the order in its box's shop", () => {
    expect(shopNotificationUrl("shop_order_ready", { order_id: "o-1", organization_slug: "kypseli" })).toBe("/box/shop/orders/o-1?box=kypseli");
    expect(shopNotificationUrl("shop_order_cancelled", {})).toBe("/box/shop");
    expect(shopNotificationUrl("season_confirmed", { order_id: "o-1" })).toBeNull();
  });

  it("name the order, the place and the box", () => {
    const t = (key: string, values?: Record<string, string | number>) => `${key} ${JSON.stringify(values ?? {})}`;
    expect(shopNotificationText("shop_order_ready", { order_number: 1042, pickup_name: "Ρεσεψιόν" }, "body", t)).toBe(
      'notif.shop_order_ready.body {"number":"K-1042","box":"notif.theBox {}","place":"Ρεσεψιόν"}',
    );
    expect(shopNotificationText("chat_message", {}, "title", t)).toBeNull();
  });
});
