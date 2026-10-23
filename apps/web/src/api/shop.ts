import { apiRequest } from "@/api/client";

/**
 * The member side of the box shop (ADR-190): the storefront summary for the
 * Box card, the catalogue, one-screen checkout and the member's orders.
 *
 * Every call names the box in its path (`/org/{slug}/me/shop/...`), so a
 * product card in a post of another box still opens that box's shop.
 *
 * TODO(ADR-190): the shop-api branch has the schema and domain only (no
 * controllers or OpenAPI yet). These types follow the ADR's data model and
 * the proposal (docs/product/2026-10-23-shop-and-perks-proposal.md). Once
 * `npm run generate:api` exports the shop schemas, replace them with
 * `components["schemas"][...]` aliases, as the other api modules do.
 */

export type ShopStockStatus = "ok" | "low" | "critical" | "out";
export type ShopPaymentMode = "at_pickup" | "on_account" | "online";
export type ShopOrderStatus = "placed" | "ready_for_pickup" | "picked_up" | "cancelled";
export type ShopPaymentStatus = "pending_payment" | "paid" | "partially_refunded" | "refunded" | "void";
/** Where the member came from (ADR-190 `shop_orders.source`, ADR-192 attribution). */
export type ShopOrderSource = "direct" | "club_post" | "promotion_code" | "public_page" | "other";

export type ShopPhoto = { id: string; url: string; alt?: string | null };

/** One option axis (size, colour), at most two per product. */
export type ShopOptionAxis = {
  name: string;
  values: string[];
  /** Lets the app draw colours as swatches and sizes as a grid. TODO(ADR-190): confirm the field. */
  kind?: "size" | "colour" | "other" | null;
};

export type ShopVariant = {
  id: string;
  title: string | null;
  /** One value per axis, `{ "Μέγεθος": "M", "Χρώμα": "Μαύρο" }`. */
  option_values: Record<string, string>;
  price_cents: number;
  compare_at_price_cents?: number | null;
  currency: string;
  stock_status: ShopStockStatus;
  /** Units the member can still order; null when the variant does not track stock. */
  available: number | null;
};

export type ShopProductSummary = {
  id: string;
  title: string;
  category: string | null;
  photos: ShopPhoto[];
  options: { axes: ShopOptionAxis[] };
  variants: ShopVariant[];
  member_discount_applies: boolean;
  per_person_limit: number | null;
  /** «Νέο» for 14 days after publishing (the proposal, Προώθηση). */
  is_new: boolean;
  published_at: string | null;
};

export type ShopProduct = ShopProductSummary & {
  description: string | null;
  /** Empty = every pickup point of the box. */
  pickup_location_ids: string[];
};

export type ShopPickupLocation = { id: string; name: string; hint: string | null };

export type ShopOrderLine = {
  id: string;
  product_id: string;
  variant_id: string;
  product_title: string;
  variant_title: string | null;
  photo_url: string | null;
  quantity: number;
  unit_price_cents: number;
  discount_cents: number;
  total_cents: number;
};

export type ShopOrder = {
  id: string;
  number: number;
  status: ShopOrderStatus;
  payment_status: ShopPaymentStatus;
  payment_mode: ShopPaymentMode;
  pickup_location: ShopPickupLocation | null;
  currency: string;
  subtotal_cents: number;
  discount_cents: number;
  total_cents: number;
  placed_at: string;
  ready_at: string | null;
  picked_up_at: string | null;
  cancelled_at: string | null;
  cancel_reason: string | null;
  /** Unpicked orders are cancelled after this (7 days by default). */
  expires_at: string | null;
  /** What the QR carries; the desk scans it at pickup. */
  pickup_code: string;
  can_cancel: boolean;
  lines: ShopOrderLine[];
};

export type ShopOrderSummary = Pick<ShopOrder, "id" | "number" | "status" | "total_cents" | "currency" | "placed_at">;

export type ShopStorefront = {
  /** False while the shop is closed: the Box card is absent for everyone. */
  open: boolean;
  published_count: number;
  new_count: number;
  preview: { id: string; title: string; photo_url: string | null }[];
  currency: string;
  /** The member's package discount on products (ADR-097), when they have one. */
  member_discount_percent: number | null;
  pickup_locations: ShopPickupLocation[];
  /** Pay-at-pickup is always on in the MVP; on-account only when the owner allows it. */
  payment_modes: { at_pickup: boolean; on_account: boolean };
  /** Online card payment: shown, greyed out and blocked until the payment provider ships. */
  online_payment: { available: boolean; reason: string | null };
  /** The member's orders not yet picked up, newest first. */
  open_orders: ShopOrderSummary[];
};

export type ShopCartItem = { variant_id: string; quantity: number };

export type ShopQuote = {
  currency: string;
  subtotal_cents: number;
  discount_cents: number;
  total_cents: number;
  promotion: { code: string; discount_cents: number } | null;
};

export type ShopOrderCreate = {
  lines: ShopCartItem[];
  pickup_location_id: string | null;
  payment_mode: Exclude<ShopPaymentMode, "online">;
  promotion_code?: string | null;
  source: ShopOrderSource;
  source_ref_id?: string | null;
  idempotency_key: string;
};

const id = (value: string) => encodeURIComponent(value);
const shopPath = (slug: string, path = "") => `/org/${id(slug)}/me/shop${path}`;

export const shopKeys = {
  all: ["shop"] as const,
  storefront: (slug: string) => ["shop", slug, "storefront"] as const,
  products: (slug: string) => ["shop", slug, "products"] as const,
  product: (slug: string, productId: string) => ["shop", slug, "products", productId] as const,
  orders: (slug: string) => ["shop", slug, "orders"] as const,
  order: (slug: string, orderId: string) => ["shop", slug, "orders", orderId] as const,
};

// TODO(ADR-190): GET /org/{slug}/me/shop
export async function fetchStorefront(token: string, slug: string) {
  const data = await apiRequest<{ shop?: ShopStorefront }>(shopPath(slug), { token });
  return data.shop ?? null;
}

// TODO(ADR-190): GET /org/{slug}/me/shop/products
export async function fetchShopProducts(token: string, slug: string) {
  const data = await apiRequest<{ products?: ShopProductSummary[] }>(shopPath(slug, "/products"), { token });
  return data.products ?? [];
}

// TODO(ADR-190): GET /org/{slug}/me/shop/products/{id}
export async function fetchShopProduct(token: string, slug: string, productId: string) {
  const data = await apiRequest<{ product: ShopProduct }>(shopPath(slug, `/products/${id(productId)}`), { token });
  return data.product;
}

/** The server's price for the cart, with a promotion code (prices never come from the client). */
// TODO(ADR-190): POST /org/{slug}/me/shop/orders/quote
export async function quoteShopCart(token: string, slug: string, body: { lines: ShopCartItem[]; promotion_code?: string | null }) {
  const data = await apiRequest<{ quote: ShopQuote }>(shopPath(slug, "/orders/quote"), { method: "POST", token, body });
  return data.quote;
}

// TODO(ADR-190): POST /org/{slug}/me/shop/orders
export async function placeShopOrder(token: string, slug: string, body: ShopOrderCreate) {
  const data = await apiRequest<{ order: ShopOrder }>(shopPath(slug, "/orders"), { method: "POST", token, body });
  return data.order;
}

// TODO(ADR-190): GET /org/{slug}/me/shop/orders/{id}
export async function fetchShopOrder(token: string, slug: string, orderId: string) {
  const data = await apiRequest<{ order: ShopOrder }>(shopPath(slug, `/orders/${id(orderId)}`), { token });
  return data.order;
}

// TODO(ADR-190): POST /org/{slug}/me/shop/orders/{id}/cancel
export async function cancelShopOrder(token: string, slug: string, orderId: string) {
  const data = await apiRequest<{ order: ShopOrder }>(shopPath(slug, `/orders/${id(orderId)}/cancel`), {
    method: "POST",
    token,
  });
  return data.order;
}

/** «Ειδοποίησέ με»: a back-in-stock notice for one variant. */
// TODO(ADR-190): POST /org/{slug}/me/shop/variants/{id}/notify is "later" in the proposal (§5).
export async function requestBackInStock(token: string, slug: string, variantId: string) {
  await apiRequest<unknown>(shopPath(slug, `/variants/${id(variantId)}/notify`), { method: "POST", token });
}
