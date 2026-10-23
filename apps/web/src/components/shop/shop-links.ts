/**
 * The bell's words and links for the member's shop orders (ADR-190): ready
 * for pickup (where and until when), the day-3 reminder, and a cancellation.
 * Each opens the order in Box › Κατάστημα.
 *
 * TODO(ADR-190): the type names and payload keys (`order_id`, `order_number`,
 * `organization_slug`, `box_name`, `pickup_name`, `expires_at`) follow the
 * proposal; confirm them when the shop-api branch emits the notifications.
 */
export const SHOP_NOTIFICATION_TYPES = ["shop_order_ready", "shop_order_reminder", "shop_order_cancelled"] as const;

export type ShopNotificationType = (typeof SHOP_NOTIFICATION_TYPES)[number];

export function isShopNotification(type: string): type is ShopNotificationType {
  return (SHOP_NOTIFICATION_TYPES as readonly string[]).includes(type);
}

const text = (payload: Record<string, unknown>, key: string) => (typeof payload[key] === "string" ? (payload[key] as string).trim() : "");

export function shopNotificationUrl(type: string, payload: Record<string, unknown>): string | null {
  if (!isShopNotification(type)) return null;
  const orderId = text(payload, "order_id");
  const slug = text(payload, "organization_slug");
  const query = slug ? `?box=${encodeURIComponent(slug)}` : "";
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
  const values = {
    number: typeof number === "number" || typeof number === "string" ? `K-${number}` : "",
    box: text(payload, "box_name") || t("notif.theBox"),
    place: text(payload, "pickup_name") || t("notif.theDesk"),
  };
  return t(`notif.${type}.${part}`, values);
}
