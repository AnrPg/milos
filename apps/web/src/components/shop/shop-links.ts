/**
 * The bell's words and links for the member's shop notices (ADR-190): an
 * order ready for pickup, the reminder of a ready order not yet picked up,
 * a cancellation, and a sold-out variant back in stock. Order notices open
 * the order in Box › Κατάστημα, the stock notice the product.
 *
 * Payload keys as `Palee.Notifications` emits them: `order_id`,
 * `order_number`, `pickup_code`, `pickup_location_id`, `reason`,
 * `product_id`, `variant_id`, `product_title`, `variant_title`. The API's
 * own `url` points at `/box/shop/products/:id`; the web route is singular,
 * so the link is built here. `organization_slug`, `box_name` and
 * `pickup_name` are read when present and otherwise fall back.
 */
export const SHOP_NOTIFICATION_TYPES = ["shop_order_ready", "shop_order_reminder", "shop_order_cancelled", "shop_back_in_stock"] as const;

export type ShopNotificationType = (typeof SHOP_NOTIFICATION_TYPES)[number];

export function isShopNotification(type: string): type is ShopNotificationType {
  return (SHOP_NOTIFICATION_TYPES as readonly string[]).includes(type);
}

const text = (payload: Record<string, unknown>, key: string) => (typeof payload[key] === "string" ? (payload[key] as string).trim() : "");

export function shopNotificationUrl(type: string, payload: Record<string, unknown>): string | null {
  if (!isShopNotification(type)) return null;
  const slug = text(payload, "organization_slug");
  const query = slug ? `?box=${encodeURIComponent(slug)}` : "";
  if (type === "shop_back_in_stock") {
    const productId = text(payload, "product_id");
    return productId ? `/box/shop/product/${encodeURIComponent(productId)}${query}` : `/box/shop${query}`;
  }
  const orderId = text(payload, "order_id");
  return orderId ? `/box/shop/orders/${encodeURIComponent(orderId)}${query}` : `/box/shop${query}`;
}

export function shopNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: (key: string, values?: Record<string, string | number>) => string,
): string | null {
  if (!isShopNotification(type)) return null;
  const number = payload.order_number;
  const product = [text(payload, "product_title"), text(payload, "variant_title")].filter(Boolean).join(" · ");
  const values = {
    number: typeof number === "number" || typeof number === "string" ? `K-${number}` : "",
    box: text(payload, "box_name") || t("notif.theBox"),
    place: text(payload, "pickup_name") || t("notif.theDesk"),
    product: product || t("notif.theProduct"),
  };
  return t(`notif.${type}.${part}`, values);
}
