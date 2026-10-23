import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * The member side of the box shop (ADR-190): the storefront for the Box card,
 * the catalogue, one-screen checkout, back-in-stock alerts and the member's
 * orders and shop transactions, plus the public catalogue of a box page.
 *
 * Every member call names the box in its path (`/org/{slug}/me/shop/...`), so
 * a product card in a post of another box still opens that box's shop.
 *
 * The UI types below are what the screens read; the `Api*` types alias the
 * generated OpenAPI schemas (PaleeWeb.Schemas.Shop) and the adapters map them.
 */

type Schemas = components["schemas"];

export type ApiMemberProduct = Schemas["ShopMemberProduct"];
export type ApiMemberVariant = Schemas["ShopMemberVariant"];
export type ApiProductPhoto = Schemas["ShopProductPhoto"];
export type ApiStorefront = Schemas["ShopStorefront"];
export type ApiCartPreview = Schemas["ShopCartPreview"];
export type ApiCheckoutBody = Schemas["ShopCheckoutBody"];
export type ApiOrder = Schemas["ShopOrderList"]["orders"][number];
export type ApiStockAlert = Schemas["ShopStockAlert"];
export type ShopTransaction = Schemas["ShopTransaction"];

export type ShopStockStatus = "ok" | "low" | "critical" | "out";
export type ShopPaymentMode = "at_pickup" | "on_account" | "online";
export type ShopOrderStatus = ApiOrder["status"];
export type ShopPaymentStatus = ApiOrder["payment_status"];
/** Where the member came from (ADR-190 `shop_orders.source`, ADR-192 attribution). */
export type ShopOrderSource = NonNullable<ApiCheckoutBody["source"]>;

export type ShopPhoto = { id: string; url: string; full_url: string | null; alt?: string | null };

/** One option axis (size, colour), at most two per product. */
export type ShopOptionAxis = {
  name: string;
  values: string[];
  /** Lets the app draw colours as swatches and sizes as a grid; absent → guessed from the name. */
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
  /** Units the member can still order; null when unknown (members get no counts) or untracked. */
  available: number | null;
};

export type ShopProductSummary = {
  id: string;
  title: string;
  category: string | null;
  photos: ShopPhoto[];
  options: { axes: ShopOptionAxis[] };
  variants: ShopVariant[];
  /**
   * Whether the package discount applies. The member presenter does not say
   * which products are marked, so screens promise no member price and the
   * cart preview (which knows) prices the basket.
   */
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
  /** The short code the QR carries and the desk types or scans at pickup. */
  pickup_code: string;
  can_cancel: boolean;
  lines: ShopOrderLine[];
};

export type ShopOrderSummary = Pick<ShopOrder, "id" | "number" | "status" | "total_cents" | "currency" | "placed_at">;

export type ShopStorefront = {
  /** False while nothing is published (or the business is not live): the Box card is absent. */
  open: boolean;
  closed_reason: ApiStorefront["closed_reason"];
  published_count: number;
  new_count: number;
  preview: { id: string; title: string; photo_url: string | null }[];
  categories: string[];
  currency: string;
  /** The member's package discount on marked products (ADR-097), when they have one. */
  member_discount_percent: number | null;
  pickup_locations: ShopPickupLocation[];
  /** Online card payment: shown, greyed out and blocked until the payment provider ships. */
  online_payment: { available: boolean; reason: string | null };
  /** The member's orders not yet picked up. */
  open_orders: ShopOrderSummary[];
};

export type ShopCartItem = { variant_id: string; quantity: number };

/** The server's price of the basket (POST …/cart/preview). */
export type ShopQuote = {
  currency: string;
  subtotal_cents: number;
  discount_cents: number;
  total_cents: number;
  /** The package discount the price includes; never stacked with a promotion code. */
  member_discount_percent: number | null;
  /** Where this basket can be picked up; empty = every branch of the box. */
  pickup_location_ids: string[];
  payment_modes: ShopPaymentMode[];
  online_payment: { available: boolean; reason: string | null };
  /** The promotion code the price includes, as the API normalised it. */
  promotion_code: string | null;
};

export type ShopOrderCreate = {
  lines: ShopCartItem[];
  pickup_location_id: string | null;
  // "online" only once `online_payment.available`; the provider's card step then supplies `payment_token`.
  payment_mode: ShopPaymentMode;
  promotion_code?: string | null;
  source: ShopOrderSource;
  source_ref_id?: string | null;
  idempotency_key: string;
};

/** A back-in-stock alert the member set on a sold-out variant. */
export type ShopStockAlert = { id: string; variant_id: string; product_id: string | null; notified_at: string | null };

const id = (value: string) => encodeURIComponent(value);
const shopPath = (slug: string, path = "") => `/org/${id(slug)}/me/shop${path}`;

export const shopKeys = {
  all: ["shop"] as const,
  storefront: (slug: string) => ["shop", slug, "storefront"] as const,
  products: (slug: string) => ["shop", slug, "products"] as const,
  product: (slug: string, productId: string) => ["shop", slug, "products", productId] as const,
  preview: (slug: string, signature: string) => ["shop", slug, "preview", signature] as const,
  orders: (slug: string) => ["shop", slug, "orders"] as const,
  order: (slug: string, orderId: string) => ["shop", slug, "orders", orderId] as const,
  stockAlerts: (slug: string) => ["shop", slug, "stock-alerts"] as const,
  transactions: (slug: string) => ["shop", slug, "transactions"] as const,
  publicProducts: (slug: string) => ["shop", "public", slug] as const,
};

// ── Adapters ──────────────────────────────────────────────────────────────

/** «Νέο» for 14 days after publishing (the proposal, Προώθηση). */
const NEW_FOR_MS = 14 * 24 * 60 * 60 * 1000;

const STOCK: Record<ApiMemberVariant["available"], ShopStockStatus> = { in_stock: "ok", low: "low", sold_out: "out" };

function toVariant(variant: ApiMemberVariant): ShopVariant {
  return {
    id: variant.id,
    title: variant.title ?? null,
    option_values: variant.option_values ?? {},
    price_cents: variant.price_cents,
    compare_at_price_cents: variant.compare_at_price_cents ?? null,
    currency: variant.currency,
    stock_status: STOCK[variant.available] ?? "ok",
    // Members see availability, not counts.
    available: variant.available === "sold_out" ? 0 : null,
  };
}

export function toPhoto(media: ApiProductPhoto): ShopPhoto | null {
  const url = media.thumb_url ?? media.url ?? media.full_url ?? null;
  return url ? { id: media.id, url, full_url: media.full_url ?? media.url ?? url, alt: media.alt_text ?? null } : null;
}

/** `options` is free-form in the schema; the API stores `{ axes: [{ name, values }] }`. */
function toAxes(options: ApiMemberProduct["options"]): ShopOptionAxis[] {
  const axes = (options as { axes?: unknown } | undefined)?.axes;
  if (!Array.isArray(axes)) return [];
  return axes.flatMap((axis) => {
    const { name, values, kind } = (axis ?? {}) as { name?: unknown; values?: unknown; kind?: unknown };
    if (typeof name !== "string" || !Array.isArray(values)) return [];
    const strings = values.filter((value): value is string => typeof value === "string");
    const known = kind === "size" || kind === "colour" || kind === "other" ? kind : null;
    return [{ name, values: strings, kind: known }];
  });
}

export function toShopProduct(product: ApiMemberProduct, now = Date.now()): ShopProduct {
  const published = product.published_at ? Date.parse(product.published_at) : Number.NaN;
  const marked = (product as { member_discount_applies?: boolean }).member_discount_applies;
  return {
    id: product.id,
    title: product.title,
    category: product.category ?? null,
    photos: (product.media ?? []).map(toPhoto).filter((photo): photo is ShopPhoto => photo !== null),
    options: { axes: toAxes(product.options) },
    variants: product.variants.map(toVariant),
    member_discount_applies: marked ?? false,
    per_person_limit: product.per_person_limit ?? null,
    is_new: Number.isFinite(published) && now - published < NEW_FOR_MS,
    published_at: product.published_at ?? null,
    description: product.description ?? null,
    pickup_location_ids: product.all_locations === false ? (product.location_ids ?? []) : [],
  };
}

function toPlace(location: ApiStorefront["pickup_locations"][number]): ShopPickupLocation {
  return { id: location.id, name: location.name ?? "", hint: location.address ?? null };
}

export function toShopOrder(order: ApiOrder, places: ShopPickupLocation[] = []): ShopOrder {
  const pickup = order.pickup_location_id ? (places.find((place) => place.id === order.pickup_location_id) ?? null) : null;
  return {
    id: order.id,
    number: order.number,
    status: order.status,
    payment_status: order.payment_status,
    payment_mode: (order.payment_mode as ShopPaymentMode | null | undefined) ?? "at_pickup",
    pickup_location: pickup,
    currency: order.currency ?? "EUR",
    subtotal_cents: order.subtotal_cents ?? order.total_cents,
    discount_cents: order.discount_cents ?? 0,
    total_cents: order.total_cents,
    placed_at: order.placed_at ?? new Date(0).toISOString(),
    ready_at: order.ready_at ?? null,
    picked_up_at: order.picked_up_at ?? null,
    cancelled_at: order.cancelled_at ?? null,
    cancel_reason: order.cancel_reason ?? null,
    expires_at: order.expires_at ?? null,
    pickup_code: order.pickup_code || String(order.number),
    // Fulfilment.cancel_mine: the buyer may cancel an unpaid order before pickup.
    can_cancel: order.status === "placed" && order.payment_status === "pending_payment",
    lines: order.lines.map((line) => ({
      id: line.id,
      product_id: line.product_id ?? "",
      variant_id: line.variant_id,
      product_title: line.product_title,
      variant_title: line.variant_title ?? null,
      photo_url: null,
      quantity: line.quantity,
      unit_price_cents: line.unit_price_cents ?? 0,
      discount_cents: line.discount_cents ?? 0,
      total_cents: line.total_cents,
    })),
  };
}

/** Order lines carry no photo; the catalogue's first photo of the product stands in. */
function withLinePhotos(order: ShopOrder, products: ApiMemberProduct[]): ShopOrder {
  const photos = new Map(products.map((product) => [product.id, (product.media ?? []).map(toPhoto).find(Boolean)?.url ?? null]));
  return { ...order, lines: order.lines.map((line) => ({ ...line, photo_url: photos.get(line.product_id) ?? null })) };
}

export function toStorefront(data: ApiStorefront, orders: ShopOrderSummary[], now = Date.now()): ShopStorefront {
  const products = data.products.map((product) => toShopProduct(product, now));
  return {
    open: data.open && products.length > 0,
    closed_reason: data.closed_reason ?? null,
    published_count: products.length,
    new_count: products.filter((product) => product.is_new).length,
    preview: products.map((product) => ({ id: product.id, title: product.title, photo_url: product.photos[0]?.url ?? null })),
    categories: data.categories ?? [],
    currency: products[0]?.variants[0]?.currency ?? "EUR",
    member_discount_percent: data.member_discount?.percent ?? null,
    pickup_locations: data.pickup_locations.map(toPlace),
    online_payment: { available: data.online_payment.available, reason: data.online_payment.reason ?? null },
    open_orders: orders,
  };
}

export function toQuote(data: ApiCartPreview): ShopQuote {
  return {
    currency: data.currency ?? "EUR",
    subtotal_cents: data.subtotal_cents ?? data.total_cents,
    discount_cents: data.discount_cents ?? 0,
    total_cents: data.total_cents,
    member_discount_percent: data.member_discount?.percent ?? null,
    pickup_location_ids: data.pickup_location_ids ?? [],
    payment_modes: data.payment_modes ?? ["at_pickup"],
    online_payment: { available: data.online_payment?.available ?? false, reason: data.online_payment?.reason ?? null },
    promotion_code: data.promotion_code?.applied ? (data.promotion_code.code ?? null) : null,
  };
}

const OPEN: ShopOrderStatus[] = ["placed", "ready_for_pickup"];

async function quietly<T>(request: Promise<T>, fallback: T) {
  try {
    return await request;
  } catch {
    return fallback;
  }
}

// ── Calls ─────────────────────────────────────────────────────────────────

const getStorefront = (token: string, slug: string) => apiRequest<ApiStorefront>(shopPath(slug, "/storefront"), { token });

/** GET /org/{slug}/me/shop/products */
export async function fetchShopProducts(token: string, slug: string): Promise<ShopProductSummary[]> {
  const data = await apiRequest<{ products?: ApiMemberProduct[] }>(shopPath(slug, "/products"), { token });
  const now = Date.now();
  return (data.products ?? []).map((product) => toShopProduct(product, now));
}

/** GET /org/{slug}/me/shop/products/{id} */
export async function fetchShopProduct(token: string, slug: string, productId: string) {
  const data = await apiRequest<{ product: ApiMemberProduct }>(shopPath(slug, `/products/${id(productId)}`), { token });
  return toShopProduct(data.product);
}

/** GET /org/{slug}/me/shop/orders */
export async function fetchShopOrders(token: string, slug: string): Promise<ShopOrderSummary[]> {
  const data = await apiRequest<{ orders?: ApiOrder[] }>(shopPath(slug, "/orders"), { token });
  return (data.orders ?? []).map((order) => ({
    id: order.id,
    number: order.number,
    status: order.status,
    total_cents: order.total_cents,
    currency: order.currency ?? "EUR",
    placed_at: order.placed_at ?? new Date(0).toISOString(),
  }));
}

/** GET /org/{slug}/me/shop/storefront, with the member's orders not yet picked up. */
export async function fetchStorefront(token: string, slug: string): Promise<ShopStorefront> {
  const [data, orders] = await Promise.all([
    getStorefront(token, slug),
    quietly(fetchShopOrders(token, slug), [] as ShopOrderSummary[]),
  ]);
  return toStorefront(data, orders.filter((order) => OPEN.includes(order.status)));
}

/** POST /org/{slug}/me/shop/cart/preview: the server's price (member discount or a promotion code), pickup branches, payment modes and online flag. */
export async function previewShopCart(
  token: string,
  slug: string,
  body: { lines: ShopCartItem[]; pickup_location_id?: string | null; promotion_code?: string | null },
): Promise<ShopQuote> {
  return toQuote(await apiRequest<ApiCartPreview>(shopPath(slug, "/cart/preview"), { method: "POST", token, body }));
}

/** POST /org/{slug}/me/shop/orders (idempotent per idempotency_key). */
export async function placeShopOrder(token: string, slug: string, body: ShopOrderCreate) {
  const request: ApiCheckoutBody = body;
  const data = await apiRequest<{ order: ApiOrder }>(shopPath(slug, "/orders"), { method: "POST", token, body: request });
  return toShopOrder(data.order);
}

/** GET /org/{slug}/me/shop/orders/{id}, with its pickup branch and the products' photos. */
export async function fetchShopOrder(token: string, slug: string, orderId: string) {
  const [data, storefront] = await Promise.all([
    apiRequest<{ order: ApiOrder }>(shopPath(slug, `/orders/${id(orderId)}`), { token }),
    quietly(getStorefront(token, slug), null),
  ]);
  const order = toShopOrder(data.order, storefront?.pickup_locations.map(toPlace) ?? []);
  return storefront ? withLinePhotos(order, storefront.products) : order;
}

/** POST /org/{slug}/me/shop/orders/{id}/pay: card payment of an online order, with the provider's token. */
export async function payShopOrder(token: string, slug: string, orderId: string, paymentToken: string) {
  const body: Schemas["ShopPayBody"] = { payment_token: paymentToken };
  const data = await apiRequest<{ order: ApiOrder }>(shopPath(slug, `/orders/${id(orderId)}/pay`), { method: "POST", token, body });
  return toShopOrder(data.order);
}

/** POST /org/{slug}/me/shop/orders/{id}/cancel */
export async function cancelShopOrder(token: string, slug: string, orderId: string) {
  const data = await apiRequest<{ order: ApiOrder }>(shopPath(slug, `/orders/${id(orderId)}/cancel`), {
    method: "POST",
    token,
    body: { reason: null },
  });
  return toShopOrder(data.order);
}

const toAlert = (alert: ApiStockAlert): ShopStockAlert => ({
  id: alert.id,
  variant_id: alert.variant_id,
  product_id: alert.product_id ?? null,
  notified_at: alert.notified_at ?? null,
});

/** GET /org/{slug}/me/shop/stock-alerts */
export async function fetchStockAlerts(token: string, slug: string): Promise<ShopStockAlert[]> {
  const data = await apiRequest<{ stock_alerts?: ApiStockAlert[] }>(shopPath(slug, "/stock-alerts"), { token });
  return (data.stock_alerts ?? []).map(toAlert);
}

/** «Ειδοποίησέ με»: PUT /org/{slug}/me/shop/variants/{id}/stock-alert */
export async function requestBackInStock(token: string, slug: string, variantId: string) {
  const data = await apiRequest<{ stock_alert: ApiStockAlert }>(shopPath(slug, `/variants/${id(variantId)}/stock-alert`), { method: "PUT", token });
  return toAlert(data.stock_alert);
}

/** DELETE /org/{slug}/me/shop/variants/{id}/stock-alert */
export async function cancelBackInStock(token: string, slug: string, variantId: string) {
  await apiRequest<unknown>(shopPath(slug, `/variants/${id(variantId)}/stock-alert`), { method: "DELETE", token });
}

/** GET /org/{slug}/me/shop/transactions: the member's shop purchases with invoices, payments and refunds. */
export async function fetchShopTransactions(token: string, slug: string): Promise<ShopTransaction[]> {
  const data = await apiRequest<{ transactions?: ShopTransaction[] }>(shopPath(slug, "/transactions"), { token });
  return data.transactions ?? [];
}

/** GET /boxes/{slug}/shop/products: the products a box shows to anyone on its public page. */
export async function fetchPublicShopProducts(slug: string): Promise<ShopProductSummary[]> {
  const data = await apiRequest<{ products?: ApiMemberProduct[] }>(`/boxes/${id(slug)}/shop/products`, { scope: "account" });
  const now = Date.now();
  return (data.products ?? []).map((product) => toShopProduct(product, now));
}
