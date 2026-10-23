import { apiRequest } from "@/api/client";

/**
 * The member side of the box shop (ADR-190): the storefront summary for the
 * Box card, the catalogue, one-screen checkout and the member's orders.
 *
 * Every call names the box in its path (`/org/{slug}/me/shop/...`), so a
 * product card in a post of another box still opens that box's shop.
 *
 * The UI types below are what the screens read; the `Api*` types are the
 * shop-api OpenAPI schemas (PaleeWeb.Schemas.Shop: ShopMemberProduct,
 * ShopMemberVariant, ShopCartPreview, ShopOrder), mapped by the adapters
 * further down.
 * TODO(ADR-190): run `npm run generate:api` (needs `mix`) and alias the
 * `Api*` types to `components["schemas"][...]`, as the other api modules do.
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
  /** False while nothing is published: the Box card is absent. */
  open: boolean;
  published_count: number;
  new_count: number;
  preview: { id: string; title: string; photo_url: string | null }[];
  currency: string;
  /** The member's package discount on products (ADR-097), when known. */
  member_discount_percent: number | null;
  pickup_locations: ShopPickupLocation[];
  /** Pay-at-pickup is always on in the MVP; the basket preview says what else is allowed. */
  payment_modes: { at_pickup: boolean; on_account: boolean };
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
  // "online" only once `online_payment.available` (TODO(ADR-190): the provider's card step).
  payment_mode: ShopPaymentMode;
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
  preview: (slug: string, signature: string) => ["shop", slug, "preview", signature] as const,
  orders: (slug: string) => ["shop", slug, "orders"] as const,
  order: (slug: string, orderId: string) => ["shop", slug, "orders", orderId] as const,
};

// ── API shapes (PaleeWeb.Schemas.Shop) ───────────────────────────────────

export type ApiMemberVariant = {
  id: string;
  product_id?: string;
  title?: string | null;
  option_values?: Record<string, string> | null;
  price_cents: number;
  currency: string;
  compare_at_price_cents?: number | null;
  available: "in_stock" | "low" | "sold_out";
};

export type ApiMemberProduct = {
  id: string;
  title: string;
  description?: string | null;
  category?: string | null;
  media_ids?: string[];
  /** TODO(ADR-190): photo URLs; the member presenter has `media_ids` only so far. */
  photos?: ShopPhoto[];
  options?: { axes?: ShopOptionAxis[] } | null;
  per_person_limit?: number | null;
  all_locations?: boolean;
  location_ids?: string[];
  published_at?: string | null;
  /** TODO(ADR-190): not in ShopMemberProduct yet; the preview applies the discount either way. */
  member_discount_applies?: boolean;
  variants: ApiMemberVariant[];
};

type ApiOrderLine = {
  id: string;
  product_id?: string;
  variant_id: string;
  product_title: string;
  variant_title?: string | null;
  quantity: number;
  unit_price_cents?: number;
  discount_cents?: number;
  total_cents: number;
};

export type ApiOrder = {
  id: string;
  number: number;
  status: ShopOrderStatus;
  payment_status: ShopPaymentStatus;
  payment_mode?: string | null;
  pickup_location_id?: string | null;
  currency?: string;
  subtotal_cents?: number;
  discount_cents?: number;
  total_cents: number;
  placed_at?: string | null;
  expires_at?: string | null;
  ready_at?: string | null;
  picked_up_at?: string | null;
  cancelled_at?: string | null;
  cancel_reason?: string | null;
  lines: ApiOrderLine[];
};

type ApiPreview = {
  currency?: string;
  subtotal_cents?: number;
  discount_cents?: number;
  total_cents: number;
  pickup_location_ids?: string[];
  payment_modes: ShopPaymentMode[];
  online_payment: { available: boolean; reason?: string | null };
  promotion_code?: { id: string; code: string; applied: boolean } | null;
};

type ApiLocation = { id: string; name: string; address?: string | null; archived_at?: string | null };

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

export function toShopProduct(product: ApiMemberProduct, now = Date.now()): ShopProduct {
  const published = product.published_at ? Date.parse(product.published_at) : Number.NaN;
  return {
    id: product.id,
    title: product.title,
    category: product.category ?? null,
    photos: product.photos ?? [],
    options: { axes: product.options?.axes ?? [] },
    variants: product.variants.map(toVariant),
    member_discount_applies: product.member_discount_applies ?? true,
    per_person_limit: product.per_person_limit ?? null,
    is_new: Number.isFinite(published) && now - published < NEW_FOR_MS,
    published_at: product.published_at ?? null,
    description: product.description ?? null,
    pickup_location_ids: product.all_locations === false ? (product.location_ids ?? []) : [],
  };
}

function toPlace(location: ApiLocation): ShopPickupLocation {
  return { id: location.id, name: location.name, hint: location.address ?? null };
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
    // TODO(ADR-190): the API has no pickup code yet; the desk finds the order by its id.
    pickup_code: order.id,
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

const OPEN: ShopOrderStatus[] = ["placed", "ready_for_pickup"];

async function quietly<T>(request: Promise<T>, fallback: T) {
  try {
    return await request;
  } catch {
    return fallback;
  }
}

// ── Calls ─────────────────────────────────────────────────────────────────

/** GET /org/{slug}/locations: the box's branches, the pickup points. */
async function fetchPlaces(token: string, slug: string) {
  const data = await apiRequest<{ locations?: ApiLocation[] }>(`/org/${id(slug)}/locations`, { token });
  return (data.locations ?? []).filter((location) => !location.archived_at).map(toPlace);
}

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

/** GET /org/{slug}/me/shop/orders, as the open-order summaries. */
async function fetchOpenOrders(token: string, slug: string): Promise<ShopOrderSummary[]> {
  const data = await apiRequest<{ orders?: ApiOrder[] }>(shopPath(slug, "/orders"), { token });
  return (data.orders ?? [])
    .filter((order) => OPEN.includes(order.status))
    .map((order) => ({
      id: order.id,
      number: order.number,
      status: order.status,
      total_cents: order.total_cents,
      currency: order.currency ?? "EUR",
      placed_at: order.placed_at ?? new Date(0).toISOString(),
    }));
}

/**
 * What Box and the shop header need, built from the catalog, the branches
 * and the member's orders: the API has no storefront endpoint, and the
 * basket's payment modes and online flag come from the cart preview.
 */
export async function fetchStorefront(token: string, slug: string): Promise<ShopStorefront | null> {
  const [products, places, orders] = await Promise.all([
    fetchShopProducts(token, slug),
    quietly(fetchPlaces(token, slug), [] as ShopPickupLocation[]),
    quietly(fetchOpenOrders(token, slug), [] as ShopOrderSummary[]),
  ]);
  return {
    open: products.length > 0,
    published_count: products.length,
    new_count: products.filter((product) => product.is_new).length,
    preview: products.map((product) => ({ id: product.id, title: product.title, photo_url: product.photos[0]?.url ?? null })),
    currency: products[0]?.variants[0]?.currency ?? "EUR",
    // TODO(ADR-190): the member's package discount percent; the preview returns the discount in cents only.
    member_discount_percent: null,
    pickup_locations: places,
    payment_modes: { at_pickup: true, on_account: false },
    online_payment: { available: false, reason: null },
    open_orders: orders,
  };
}

/** POST /org/{slug}/me/shop/cart/preview: the server's price (with a promotion code), pickup branches, payment modes and online flag. */
export async function previewShopCart(
  token: string,
  slug: string,
  body: { lines: ShopCartItem[]; pickup_location_id?: string | null; promotion_code?: string | null },
): Promise<ShopQuote> {
  const data = await apiRequest<ApiPreview>(shopPath(slug, "/cart/preview"), { method: "POST", token, body });
  return {
    currency: data.currency ?? "EUR",
    subtotal_cents: data.subtotal_cents ?? data.total_cents,
    discount_cents: data.discount_cents ?? 0,
    total_cents: data.total_cents,
    pickup_location_ids: data.pickup_location_ids ?? [],
    payment_modes: data.payment_modes ?? ["at_pickup"],
    online_payment: { available: data.online_payment?.available ?? false, reason: data.online_payment?.reason ?? null },
    promotion_code: data.promotion_code?.applied ? data.promotion_code.code : null,
  };
}

/** POST /org/{slug}/me/shop/orders (idempotent per idempotency_key). */
export async function placeShopOrder(token: string, slug: string, body: ShopOrderCreate) {
  const data = await apiRequest<{ order: ApiOrder }>(shopPath(slug, "/orders"), { method: "POST", token, body });
  return toShopOrder(data.order);
}

/** GET /org/{slug}/me/shop/orders/{id}, with its pickup branch's name. */
export async function fetchShopOrder(token: string, slug: string, orderId: string) {
  const [data, places] = await Promise.all([
    apiRequest<{ order: ApiOrder }>(shopPath(slug, `/orders/${id(orderId)}`), { token }),
    quietly(fetchPlaces(token, slug), [] as ShopPickupLocation[]),
  ]);
  return toShopOrder(data.order, places);
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

/** «Ειδοποίησέ με»: a back-in-stock notice for one variant. */
// TODO(ADR-190): no endpoint yet ("later" in the proposal §5); until then the button says it did not save.
export async function requestBackInStock(token: string, slug: string, variantId: string) {
  await apiRequest<unknown>(shopPath(slug, `/variants/${id(variantId)}/notify`), { method: "POST", token });
}
