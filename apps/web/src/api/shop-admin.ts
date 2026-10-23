import { apiRequest } from "@/api/client";

/*
 * The shop for staff («Κατάστημα»): catalog, variants, the stock ledger,
 * orders, the desk sale (Ταμείο) and «Προώθηση» posts (ADR-190), and the
 * shop reports (ADR-192 §4). Calls go through the selected gym: the shop
 * under `/staff/shop`, its reports under `/admin/shop/reports`.
 *
 * The wire shapes follow `PaleeWeb.Schemas.Shop` and
 * `PaleeWeb.Schemas.ShopReports` (in `generated/schema.ts`); the functions
 * below map them to the console's types (stock per branch, option axes,
 * report totals).
 */

export type ShopProductStatus = "draft" | "published" | "archived";
export type ShopVisibility = "members_only" | "anyone";
export type ShopStockStatus = "ok" | "low" | "critical" | "out";
export type ShopOrderStatus = "placed" | "ready_for_pickup" | "picked_up" | "cancelled";
export type ShopPaymentStatus = "pending_payment" | "paid" | "partially_refunded" | "refunded" | "void";
export type ShopPaymentMode = "at_pickup" | "on_account" | "online" | "cash" | "card_manual" | "bank_transfer" | "other";
export type ShopChannel = "online" | "pos";
export type ShopOrderSource = "direct" | "club_post" | "promotion_code" | "desk" | "public_page" | "other";
export type ShopMovementKind = "receive" | "sale" | "refund_restock" | "adjustment" | "transfer" | "reserve" | "release";
export type ShopAdjustReason = "recount" | "damage" | "loss" | "return" | "other";
/** What staff record when the member pays at the desk (card at the terminal is recorded by hand). */
export type DeskPaymentMethod = "cash" | "card_manual";

export type ShopMedia = { id: string; thumb_url?: string | null; full_url?: string | null; alt_text?: string | null };
export type ShopOption = { name: string; values: string[] };

export type ShopStockLevel = { location_id: string | null; on_hand: number; reserved: number };

export type ShopVariant = {
  id: string;
  title?: string | null;
  option_values: Record<string, string>;
  sku?: string | null;
  barcode?: string | null;
  price_cents: number;
  compare_at_price_cents?: number | null;
  cost_price_cents?: number | null;
  low_stock_threshold?: number | null;
  track_inventory: boolean;
  stock_status: ShopStockStatus;
  /** Per branch; a business without branches has one row with `location_id: null`. */
  stock: ShopStockLevel[];
  on_hand: number;
  reserved: number;
  days_of_stock_left?: number | null;
  archived_at?: string | null;
};

export type ShopProduct = {
  id: string;
  title: string;
  description?: string | null;
  category?: string | null;
  media: ShopMedia[];
  options: ShopOption[];
  status: ShopProductStatus;
  visibility: ShopVisibility;
  sell_in_app: boolean;
  sell_at_desk: boolean;
  member_discount_applies: boolean;
  per_person_limit?: number | null;
  all_locations: boolean;
  location_ids: string[];
  published_at?: string | null;
  archived_at?: string | null;
  variants: ShopVariant[];
};

export type ShopProductCounts = { all: number; published: number; draft: number; archived: number; low_stock: number };

export type ShopVariantInput = {
  id?: string;
  option_values: Record<string, string>;
  sku?: string | null;
  price_cents: number;
  compare_at_price_cents?: number | null;
  cost_price_cents?: number | null;
  low_stock_threshold?: number | null;
  track_inventory?: boolean;
  /** Opening stock per branch, for new variants only; later changes go through the ledger. */
  initial_stock?: { location_id: string | null; quantity: number }[];
};

export type ShopProductInput = {
  title: string;
  description?: string | null;
  category?: string | null;
  media_ids: string[];
  options: ShopOption[];
  status: ShopProductStatus;
  visibility: ShopVisibility;
  sell_in_app: boolean;
  sell_at_desk: boolean;
  member_discount_applies: boolean;
  per_person_limit?: number | null;
  all_locations: boolean;
  location_ids: string[];
  variants: ShopVariantInput[];
};

export type ShopOrderLine = {
  id: string;
  product_id: string;
  variant_id: string;
  product_title: string;
  variant_title?: string | null;
  quantity: number;
  unit_price_cents: number;
  discount_cents: number;
  total_cents: number;
  refunded_quantity: number;
  refunded_cents: number;
  thumb_url?: string | null;
};

export type ShopOrder = {
  id: string;
  number: number;
  channel: ShopChannel;
  status: ShopOrderStatus;
  payment_status: ShopPaymentStatus;
  payment_mode: ShopPaymentMode;
  user_id?: string | null;
  customer_name?: string | null;
  pickup_location_id?: string | null;
  currency: string;
  subtotal_cents: number;
  discount_cents: number;
  total_cents: number;
  paid_cents: number;
  refunded_cents: number;
  source: ShopOrderSource;
  promotion_code?: string | null;
  finance_invoice_id?: string | null;
  invoice_number?: string | null;
  placed_at: string;
  expires_at?: string | null;
  ready_at?: string | null;
  picked_up_at?: string | null;
  cancelled_at?: string | null;
  cancel_reason?: string | null;
  lines: ShopOrderLine[];
};

export type ShopOrderCounts = Record<ShopOrderStatus, number>;

export type ShopStockItem = {
  variant_id: string;
  product_id: string;
  product_title: string;
  variant_title?: string | null;
  location_id: string | null;
  on_hand: number;
  reserved: number;
  stock_status: ShopStockStatus;
  days_of_stock_left?: number | null;
  velocity_per_week?: number | null;
  unit_cost_cents?: number | null;
  thumb_url?: string | null;
};

export type ShopStockMovement = {
  id: string;
  variant_id: string;
  product_title: string;
  variant_title?: string | null;
  location_id: string | null;
  kind: ShopMovementKind;
  quantity: number;
  reason?: ShopAdjustReason | null;
  note?: string | null;
  unit_cost_cents?: number | null;
  order_id?: string | null;
  order_number?: number | null;
  actor_name?: string | null;
  occurred_at: string;
};

export type ShopMovementInput = {
  variant_id: string;
  location_id: string | null;
  kind: "receive" | "adjustment" | "recount";
  /** Signed for an adjustment, positive for a delivery; a recount sends `counted` instead. */
  quantity?: number;
  counted?: number;
  reason?: ShopAdjustReason;
  unit_cost_cents?: number | null;
  note?: string | null;
};

export type PosSaleInput = {
  location_id: string | null;
  user_id: string | null;
  customer_name?: string | null;
  payment_method: DeskPaymentMethod;
  lines: { variant_id: string; quantity: number }[];
  idempotency_key: string;
};

/** «Προώθηση»: the club's announcements (default), a member group or PT squad (`channel_id`), or the public feed. */
export type PromoteTarget = "announcements" | "channel" | "feed";
export type PromoteInput = {
  target: PromoteTarget;
  channel_id?: string | null;
  body: string;
  /** An optional code for this product only (Οικονομικά › Προσφορές). */
  promotion_code?: { code: string; discount_percent: number; ends_at?: string | null } | null;
};

/** The payment port's ways to pay: cash, card_manual, bank_transfer, other at the desk; card_online stays unavailable. */
export type ShopPaymentMethodInfo = { id: string; channel?: "pos" | "online"; available: boolean; reason?: string | null };

export type ReportWindow = { days?: number; locationIds?: string };

// ADR-192 §4 report shapes (Palee.Shop.Domain.SalesReport / PricingIndicators).
export type SalesDay = { date: string; gross_cents: number; refunded_cents: number; net_cents: number; orders: number };
export type SalesTotals = { gross_cents: number; refunded_cents: number; net_cents: number; orders: number; average_order_value_cents: number | null };
export type SalesReport = { days: SalesDay[]; totals: SalesTotals; previous_totals?: SalesTotals | null };

export type ProductRow = {
  product_id: string;
  product_name: string;
  variant_id?: string;
  variant_name?: string | null;
  units: number;
  refunded_units: number;
  net_units: number;
  revenue_cents: number;
  refunded_cents: number;
  net_revenue_cents: number;
};
export type ProductsReport = { products_by_revenue: ProductRow[]; products_by_units: ProductRow[] };

export type MarginRow = {
  product_id: string;
  product_name: string;
  net_revenue_cents: number;
  costed_revenue_cents: number;
  uncosted_revenue_cents: number;
  cost_cents: number;
  margin_cents: number;
  margin_percent: number | null;
  cost_coverage_percent: number | null;
};
export type MarginReport = { totals: Omit<MarginRow, "product_id" | "product_name">; products: MarginRow[] };

export type GroupRow = { net_revenue_cents: number; orders: number; units?: number };
export type ChannelsReport = {
  by_channel: (GroupRow & { channel: ShopChannel })[];
  by_location: (GroupRow & { location_id: string | null })[];
};

export type InventoryItem = {
  variant_id: string;
  product_id: string;
  product_name: string;
  variant_name?: string | null;
  location_id: string | null;
  on_hand: number;
  reserved: number;
  available: number;
  unit_cost_cents: number | null;
  stock_value_cents: number | null;
  low_stock_threshold: number | null;
  low_stock: boolean;
  sold_units: number;
  sell_through_percent: number | null;
};
export type InventoryReport = {
  totals: {
    on_hand: number;
    reserved: number;
    stock_value_cents: number;
    uncosted_variants: number;
    low_stock_count: number;
    sold_units: number;
    sell_through_percent: number | null;
  };
  low_stock: InventoryItem[];
  items: InventoryItem[];
};

export type AttributionSource = "club_post" | "promotion_code" | "public_page" | "direct" | "desk" | "other";
export type AttributionReport = {
  by_promotion_code: (GroupRow & { promotion_code: string })[];
  by_campaign: (GroupRow & { campaign_id: string; name?: string | null })[];
  by_source: (GroupRow & { source: AttributionSource; source_ref_id?: string | null; label?: string | null })[];
  attributed: GroupRow;
  unattributed: GroupRow;
};

export type PriceChangeEffect = {
  changed_on: string;
  from_price_cents: number;
  to_price_cents: number;
  price_change_percent: number | null;
  velocity_before: number | null;
  velocity_after: number | null;
  velocity_change_percent: number | null;
  evidence: "sufficient" | "insufficient";
};
export type DiscountEffect = {
  discount_depth_percent: number | null;
  promo_units: number;
  full_price_units: number;
  promo_units_per_order: number | null;
  full_price_units_per_order: number | null;
  promo_unit_share_percent: number | null;
  volume_lift_percent: number | null;
} | null;
export type SuggestedPrice = {
  advisory: true;
  low_cents: number | null;
  high_cents: number | null;
  cost_plus_cents?: number | null;
  inputs: {
    cost_cents: number | null;
    current_price_cents: number;
    target_margin_bp: number;
    target_margin_source: "category_setting" | "default";
    velocity_per_week: number | null;
    category_median_velocity_per_week: number | null;
    elasticity: number | null;
    elasticity_confidence: "none" | "low" | "medium" | "high" | null;
  };
};
export type PricingRow = {
  variant_id: string;
  product_id: string;
  product_name: string;
  variant_name?: string | null;
  category: string;
  price_cents: number;
  cost_cents: number | null;
  margin_percent: number | null;
  markup_percent: number | null;
  on_hand: number | null;
  units_sold: number;
  velocity_per_week: number | null;
  sell_through_percent: number | null;
  days_on_sale: number;
  days_of_stock_left: number | null;
  price_changes: PriceChangeEffect[];
  discount: DiscountEffect;
  elasticity: { estimate: number | null; confidence: string; reading?: "elastic" | "inelastic" | "no_price_sensitivity_seen" } | null;
  suggested_price: SuggestedPrice;
};
export type PricingReport = { window_days: number; variants: PricingRow[] };

const BASE = "/staff/shop";
const REPORTS = "/admin/shop/reports";
const id = (value: string) => encodeURIComponent(value);

function query(params: Record<string, string | number | boolean | null | undefined>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === "") continue;
    search.set(key, String(value));
  }
  const text = search.toString();
  return text ? `?${text}` : "";
}

/** A fresh idempotency key for a sale or a refund (ADR-190: 8 to 120 characters). */
export function shopIdempotencyKey() {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) return crypto.randomUUID();
  return [Date.now().toString(36), Math.random().toString(36).slice(2), Math.random().toString(36).slice(2)].join("");
}

export const SHOP_KEY = ["admin", "shop"] as const;

// ---- wire shapes (PaleeWeb.Schemas.Shop) and their mapping to the console's types ----

type WireStockLevel = { location_id: string | null; on_hand: number; reserved: number; available?: number };
type WireVariant = Omit<ShopVariant, "stock" | "on_hand" | "reserved"> & {
  product_id?: string;
  stock?: { on_hand: number; reserved: number; available?: number; by_location?: WireStockLevel[] } | null;
};
type WireProduct = Omit<ShopProduct, "media" | "options" | "variants"> & {
  media?: ShopMedia[];
  media_ids?: string[];
  options?: { axes?: ShopOption[] } | ShopOption[] | null;
  variants?: WireVariant[];
};

export function variantFromWire(wire: WireVariant): ShopVariant {
  const stock = wire.stock ?? null;
  const levels = stock?.by_location?.map((level) => ({ location_id: level.location_id ?? null, on_hand: level.on_hand, reserved: level.reserved })) ?? [];
  return {
    ...wire,
    option_values: wire.option_values ?? {},
    track_inventory: wire.track_inventory ?? true,
    stock: levels,
    on_hand: stock?.on_hand ?? 0,
    reserved: stock?.reserved ?? 0,
    days_of_stock_left: wire.days_of_stock_left ?? null,
  };
}

export function productFromWire(wire: WireProduct): ShopProduct {
  const options = Array.isArray(wire.options) ? wire.options : (wire.options?.axes ?? []);
  const media = wire.media ?? (wire.media_ids ?? []).map((mediaId) => ({ id: mediaId }));
  return {
    ...wire,
    media,
    options,
    sell_in_app: wire.sell_in_app ?? true,
    sell_at_desk: wire.sell_at_desk ?? true,
    member_discount_applies: wire.member_discount_applies ?? false,
    all_locations: wire.all_locations ?? true,
    location_ids: wire.location_ids ?? [],
    variants: (wire.variants ?? []).map(variantFromWire),
  };
}

/** Stock rows of the console: one per variant and branch, from the catalog's stock. */
export function stockItemsFromCatalog(products: ShopProduct[], locationIds?: string): ShopStockItem[] {
  const locations = locationIds ? locationIds.split(",").filter(Boolean) : null;
  const items: ShopStockItem[] = [];
  for (const product of products) {
    if (product.status === "archived") continue;
    for (const variant of product.variants) {
      if (variant.archived_at || !variant.track_inventory) continue;
      const levels = variant.stock.length > 0 ? variant.stock : [{ location_id: null, on_hand: variant.on_hand, reserved: variant.reserved }];
      for (const level of levels) {
        if (locations && level.location_id && !locations.includes(level.location_id)) continue;
        items.push({
          variant_id: variant.id,
          product_id: product.id,
          product_title: product.title,
          variant_title: variant.title ?? (Object.values(variant.option_values).join(" / ") || null),
          location_id: level.location_id,
          on_hand: level.on_hand,
          reserved: level.reserved,
          stock_status: variant.stock_status,
          days_of_stock_left: variant.days_of_stock_left ?? null,
          velocity_per_week: null,
          unit_cost_cents: variant.cost_price_cents ?? null,
          thumb_url: product.media[0]?.thumb_url ?? null,
        });
      }
    }
  }
  return items;
}

// ---- catalog (ShopController) ----

async function listProducts(token: string, params: { status?: ShopProductStatus | "low_stock"; q?: string; locationIds?: string } = {}) {
  const data = await apiRequest<{ products: WireProduct[]; counts: ShopProductCounts }>(
    `${BASE}/products${query({ status: params.status, q: params.q, location_ids: params.locationIds })}`,
    { token },
  );
  return { products: (data.products ?? []).map(productFromWire), counts: data.counts };
}

/** One filter's products and the counts of every filter, within the branch and search filters. */
export function fetchShopProducts(token: string, params: { status?: ShopProductStatus | "low_stock"; q?: string; locationIds?: string } = {}) {
  return listProducts(token, params);
}

export async function fetchShopProduct(token: string, productId: string) {
  const data = await apiRequest<{ product: WireProduct }>(`${BASE}/products/${id(productId)}`, { token });
  return productFromWire(data.product);
}

function variantBody(variant: ShopVariantInput) {
  return {
    option_values: variant.option_values,
    sku: variant.sku ?? null,
    price_cents: variant.price_cents,
    compare_at_price_cents: variant.compare_at_price_cents ?? null,
    cost_price_cents: variant.cost_price_cents ?? null,
    low_stock_threshold: variant.low_stock_threshold ?? null,
    track_inventory: variant.track_inventory ?? true,
  };
}

function productBody(input: ShopProductInput) {
  return {
    title: input.title,
    description: input.description ?? null,
    category: input.category ?? null,
    media_ids: input.media_ids,
    options: input.options,
    visibility: input.visibility,
    sell_in_app: input.sell_in_app,
    sell_at_desk: input.sell_at_desk,
    member_discount_applies: input.member_discount_applies,
    per_person_limit: input.per_person_limit ?? null,
    all_locations: input.all_locations,
    location_ids: input.location_ids,
  };
}

const sameValues = (left: Record<string, string>, right: Record<string, string>) =>
  Object.keys(left).length === Object.keys(right).length && Object.entries(left).every(([key, value]) => right[key] === value);

/** Opening stock beyond the first branch arrives as deliveries, so every unit has its ledger row. */
async function receiveOpening(token: string, variantId: string, entries: { location_id: string | null; quantity: number }[]) {
  for (const entry of entries) {
    if (entry.quantity > 0) await recordShopMovement(token, { variant_id: variantId, location_id: entry.location_id, kind: "receive", quantity: entry.quantity });
  }
}

function variantRows(input: ShopProductInput) {
  return input.variants.map((variant) => {
    const first = variant.initial_stock?.[0];
    return {
      ...(variant.id ? { id: variant.id } : {}),
      ...variantBody(variant),
      ...(!variant.id && first ? { initial_quantity: first.quantity, location_id: first.location_id } : {}),
    };
  });
}

async function receiveExtraOpening(token: string, saved: ShopProduct, input: ShopProductInput) {
  const extra = input.variants.filter((variant) => !variant.id && (variant.initial_stock?.length ?? 0) > 1);
  for (const variant of extra) {
    const match = saved.variants.find((entry) => !entry.archived_at && sameValues(entry.option_values, variant.option_values));
    if (match) await receiveOpening(token, match.id, variant.initial_stock!.slice(1));
  }
  return extra.length > 0 ? fetchShopProduct(token, saved.id) : saved;
}

/** A new product starts as a draft (no status sent); the first branch's opening stock rides on the create. */
export async function createShopProduct(token: string, input: ShopProductInput) {
  const data = await apiRequest<{ product: WireProduct }>(`${BASE}/products`, {
    method: "POST",
    token,
    body: { ...productBody(input), variants: variantRows(input) },
  });
  return receiveExtraOpening(token, productFromWire(data.product), input);
}

/**
 * Saves the product with its full list of live variants in one
 * transaction: with an id edited, without one added, left out archived.
 * The status changes through `setShopProductStatus` only.
 */
export async function updateShopProduct(token: string, productId: string, input: ShopProductInput) {
  const data = await apiRequest<{ product: WireProduct }>(`${BASE}/products/${id(productId)}`, {
    method: "PATCH",
    token,
    body: { ...productBody(input), variants: variantRows(input) },
  });
  return receiveExtraOpening(token, productFromWire(data.product), input);
}

/** Draft → published needs an activated business (ADR-184 answers 403 `business_not_activated`). */
export async function setShopProductStatus(token: string, productId: string, status: ShopProductStatus) {
  const data = await apiRequest<{ product: WireProduct }>(`${BASE}/products/${id(productId)}/status`, { method: "PUT", token, body: { status } });
  return productFromWire(data.product);
}

/** «Προώθηση»: a club post with the product card, optionally with a new product code. */
export function promoteShopProduct(token: string, productId: string, body: PromoteInput) {
  return apiRequest<{ post_id: string; promotion_code_id?: string | null }>(`${BASE}/products/${id(productId)}/promote`, {
    method: "POST",
    token,
    body,
  });
}

// ---- orders (ShopController) ----

/** One status's orders with the counts of every status, within the branch and paid filters. */
export async function fetchShopOrders(token: string, params: { status?: ShopOrderStatus; locationIds?: string; limit?: number; paid?: boolean } = {}) {
  const data = await apiRequest<{ orders: ShopOrder[]; counts: ShopOrderCounts }>(
    `${BASE}/orders${query({ status: params.status, location_ids: params.locationIds, paid: params.paid, limit: params.limit })}`,
    { token },
  );
  return { orders: data.orders ?? [], counts: data.counts };
}

export async function fetchShopOrder(token: string, orderId: string) {
  const data = await apiRequest<{ order: ShopOrder }>(`${BASE}/orders/${id(orderId)}`, { token });
  return data.order;
}

export type OrderAction =
  | { action: "ready" }
  | { action: "pickup"; payment_method?: DeskPaymentMethod }
  | { action: "cancel"; reason?: string | null }
  | { action: "refund"; lines: { line_id: string; quantity: number }[]; restock: boolean; reason?: string | null };

/** The request of an order action: path and body as the API takes them. */
export function orderActionRequest(change: OrderAction, idempotencyKey: string = shopIdempotencyKey()): { path: string; body: Record<string, unknown> } {
  switch (change.action) {
    case "ready":
      return { path: "ready", body: {} };
    case "pickup":
      return { path: "pickup", body: change.payment_method ? { payment_method: change.payment_method } : {} };
    case "cancel":
      return { path: "cancel", body: { reason: change.reason ?? null } };
    case "refund":
      return {
        path: "refund",
        body: {
          lines: change.lines.filter((line) => line.quantity > 0).map((line) => ({ order_line_id: line.line_id, quantity: line.quantity, restock: change.restock })),
          reason: change.reason ?? null,
          idempotency_key: idempotencyKey,
        },
      };
  }
}

export async function actOnShopOrder(token: string, orderId: string, change: OrderAction) {
  const { path, body } = orderActionRequest(change);
  const data = await apiRequest<{ order: ShopOrder }>(`${BASE}/orders/${id(orderId)}/${path}`, { method: "POST", token, body });
  return data.order;
}

// ---- stock (ShopController) ----

/** Stock rows from the catalog; `attention` keeps the low, critical and sold-out ones. */
export async function fetchShopStock(token: string, params: { locationIds?: string; attention?: boolean } = {}) {
  const { products } = await listProducts(token, { locationIds: params.locationIds });
  const items = stockItemsFromCatalog(products, params.locationIds);
  return { items: params.attention ? items.filter((item) => item.stock_status !== "ok") : items };
}

/** The stock ledger, newest first: every variant, or one (`variantId`), within the branch filter. */
export async function fetchShopMovements(token: string, params: { variantId?: string; locationIds?: string; limit?: number } = {}) {
  const data = await apiRequest<{ movements: ShopStockMovement[]; next_cursor?: string | null }>(
    `${BASE}/movements${query({ variant_id: params.variantId, location_ids: params.locationIds, limit: params.limit })}`,
    { token },
  );
  return { movements: (data.movements ?? []).map((movement) => ({ ...movement, product_title: movement.product_title ?? "" })) };
}

export async function recordShopMovement(token: string, input: ShopMovementInput) {
  const { variant_id: variantId, ...body } = input;
  const data = await apiRequest<{ variant: WireVariant; movements: ShopStockMovement[] }>(`${BASE}/variants/${id(variantId)}/movements`, {
    method: "POST",
    token,
    body,
  });
  return data.movements?.[0] ?? null;
}

// ---- desk sale (ShopController) ----

export async function createPosSale(token: string, body: PosSaleInput) {
  const data = await apiRequest<{ order: ShopOrder }>(`${BASE}/desk-sales`, { method: "POST", token, body });
  return data.order;
}

/** Ways to pay, from the payment port. */
export async function fetchShopPaymentMethods(token: string): Promise<ShopPaymentMethodInfo[]> {
  const data = await apiRequest<{ payment_methods: ShopPaymentMethodInfo[] }>(`${BASE}/payment-methods`, { token });
  return data.payment_methods ?? [];
}

// ---- photos (shop_product_photo) ----

export type ShopPhotoUpload = { media_id: string; upload_url: string; required_headers?: Record<string, string> };

export function requestShopPhotoUpload(token: string, body: { content_type: string; byte_size: number }) {
  return apiRequest<ShopPhotoUpload>(`${BASE}/photos`, { method: "POST", token, body });
}

export async function completeShopPhoto(token: string, mediaId: string) {
  const data = await apiRequest<{ media: ShopMedia }>(`${BASE}/photos/${id(mediaId)}/complete`, { method: "POST", token });
  return data.media;
}

// ---- reports (AdminShopReportController, ADR-192 §4) ----

export type ShopReportName = "sales" | "products" | "margin" | "channels" | "inventory" | "attribution" | "pricing";
type ReportOf = {
  sales: SalesReport;
  products: ProductsReport;
  margin: MarginReport;
  channels: ChannelsReport;
  inventory: InventoryReport;
  attribution: AttributionReport;
  pricing: PricingReport;
};

/** The reports' widest window (`@max_days`). */
const MAX_REPORT_DAYS = 366;

type WireTotals = { gross_cents?: number; refunded_cents?: number; net_cents?: number; orders?: number; average_order_value_cents?: number | null };
const group = <Row extends WireTotals>(row: Row) => ({ ...row, net_revenue_cents: row.net_cents ?? 0, orders: row.orders ?? 0 });

/** The sales series for the window, and the window before it when both fit in one request. */
export function salesFromWire(wire: { series?: (WireTotals & { day: string })[] }, days: number): SalesReport {
  const series = (wire.series ?? []).map((row) => ({
    date: row.day,
    gross_cents: row.gross_cents ?? 0,
    refunded_cents: row.refunded_cents ?? 0,
    net_cents: row.net_cents ?? 0,
    orders: row.orders ?? 0,
  }));
  const current = series.slice(-days);
  const previous = series.length >= days * 2 ? series.slice(-days * 2, -days) : null;
  const sum = (rows: SalesDay[]): SalesTotals => {
    const gross = rows.reduce((total, row) => total + row.gross_cents, 0);
    const refunded = rows.reduce((total, row) => total + row.refunded_cents, 0);
    const orders = rows.reduce((total, row) => total + row.orders, 0);
    return { gross_cents: gross, refunded_cents: refunded, net_cents: gross - refunded, orders, average_order_value_cents: orders > 0 ? Math.round((gross - refunded) / orders) : null };
  };
  return { days: current, totals: sum(current), previous_totals: previous ? sum(previous) : null };
}

export async function fetchShopReport<Name extends ShopReportName>(token: string, name: Name, window: ReportWindow = {}): Promise<ReportOf[Name]> {
  const days = window.days ?? 30;
  const span = name === "sales" && days * 2 <= MAX_REPORT_DAYS ? days * 2 : days;
  const wire = await apiRequest<Record<string, unknown>>(`${REPORTS}/${name}${query({ days: span, location_ids: window.locationIds })}`, { token });
  switch (name) {
    case "sales":
      return salesFromWire(wire as { series?: (WireTotals & { day: string })[] }, days) as ReportOf[Name];
    case "channels": {
      const report = wire as { by_channel?: (WireTotals & { channel: ShopChannel })[]; by_location?: (WireTotals & { location_id: string | null })[] };
      return { by_channel: (report.by_channel ?? []).map(group), by_location: (report.by_location ?? []).map(group) } as ReportOf[Name];
    }
    case "attribution": {
      const report = wire as {
        by_promotion_code?: (WireTotals & { promotion_code: string })[];
        by_campaign?: (WireTotals & { campaign_id: string })[];
        by_source?: (WireTotals & { source: AttributionSource; source_ref_id?: string | null })[];
        attributed?: WireTotals;
        unattributed?: WireTotals;
      };
      return {
        by_promotion_code: (report.by_promotion_code ?? []).map(group),
        by_campaign: (report.by_campaign ?? []).map(group),
        by_source: (report.by_source ?? []).map(group),
        attributed: group(report.attributed ?? {}),
        unattributed: group(report.unattributed ?? {}),
      } as ReportOf[Name];
    }
    default:
      return wire as ReportOf[Name];
  }
}
