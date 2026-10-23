import { apiRequest } from "@/api/client";

/*
 * The shop for staff («Κατάστημα»): catalog, variants, the stock ledger,
 * orders, the desk sale (Ταμείο) and «Προώθηση» posts (ADR-190), and the
 * shop reports (ADR-192 §4). Calls go through the selected gym (`/admin`).
 *
 * TODO(ADR-190): the shop controllers are not in the OpenAPI document yet
 * (origin/…-shop-api has the schema only). These types follow the shop
 * migration (`20261211100000_create_shop.exs`) and the proposal's contract;
 * once `npm run generate:api` carries `PaleeWeb.Admin.ShopController`, derive
 * them from `operations` like `api/inventory.ts` does and drop this note.
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
  kind: "receive" | "adjustment";
  /** Signed for an adjustment, positive for a delivery. */
  quantity: number;
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

export type PromoteTarget = "announcements" | "group" | "feed";
export type PromoteInput = {
  target: PromoteTarget;
  group_id?: string | null;
  body: string;
  /** An optional product-scoped code in Οικονομικά › Προσφορές. */
  promotion_code?: { code: string; percent_off: number; ends_on?: string | null } | null;
};

/** The mock payment adapter (ADR-190) says which ways to pay exist; online card is `available: false` for now. */
export type ShopPaymentMethodInfo = { id: string; available: boolean };

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

const BASE = "/admin/shop";
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

export const SHOP_KEY = ["admin", "shop"] as const;

// ---- catalog (TODO(ADR-190): /admin/shop/products) ----

export function fetchShopProducts(token: string, params: { status?: ShopProductStatus | "low_stock"; q?: string; locationIds?: string } = {}) {
  return apiRequest<{ products: ShopProduct[]; counts: ShopProductCounts }>(
    `${BASE}/products${query({ status: params.status, q: params.q, location_ids: params.locationIds })}`,
    { token },
  );
}

export async function fetchShopProduct(token: string, productId: string) {
  const data = await apiRequest<{ product: ShopProduct }>(`${BASE}/products/${id(productId)}`, { token });
  return data.product;
}

export async function createShopProduct(token: string, body: ShopProductInput) {
  const data = await apiRequest<{ product: ShopProduct }>(`${BASE}/products`, { method: "POST", token, body });
  return data.product;
}

export async function updateShopProduct(token: string, productId: string, body: Partial<ShopProductInput>) {
  const data = await apiRequest<{ product: ShopProduct }>(`${BASE}/products/${id(productId)}`, { method: "PATCH", token, body });
  return data.product;
}

/** Draft → published needs an activated business (ADR-184 answers 403 `business_not_activated`). */
export async function setShopProductStatus(token: string, productId: string, status: ShopProductStatus) {
  const data = await apiRequest<{ product: ShopProduct }>(`${BASE}/products/${id(productId)}/status`, {
    method: "POST",
    token,
    body: { status },
  });
  return data.product;
}

/** TODO(ADR-190): «Προώθηση» posts (`POST /admin/shop/products/:id/promote`). */
export function promoteShopProduct(token: string, productId: string, body: PromoteInput) {
  return apiRequest<{ post_id: string; promotion_code_id?: string | null }>(`${BASE}/products/${id(productId)}/promote`, {
    method: "POST",
    token,
    body,
  });
}

// ---- orders (TODO(ADR-190): /admin/shop/orders) ----

export function fetchShopOrders(token: string, params: { status?: ShopOrderStatus; locationIds?: string; limit?: number; paid?: boolean } = {}) {
  return apiRequest<{ orders: ShopOrder[]; counts: ShopOrderCounts }>(
    `${BASE}/orders${query({ status: params.status, location_ids: params.locationIds, limit: params.limit, paid: params.paid })}`,
    { token },
  );
}

export async function fetchShopOrder(token: string, orderId: string) {
  const data = await apiRequest<{ order: ShopOrder }>(`${BASE}/orders/${id(orderId)}`, { token });
  return data.order;
}

export type OrderAction =
  | { action: "ready" }
  | { action: "pickup"; payment_method?: DeskPaymentMethod }
  | { action: "cancel"; reason?: string | null }
  | { action: "refund"; lines: { line_id: string; quantity: number }[]; restock: boolean };

export async function actOnShopOrder(token: string, orderId: string, change: OrderAction) {
  const { action, ...body } = change;
  const data = await apiRequest<{ order: ShopOrder }>(`${BASE}/orders/${id(orderId)}/${action}`, { method: "POST", token, body });
  return data.order;
}

// ---- stock (TODO(ADR-190): /admin/shop/stock) ----

export function fetchShopStock(token: string, params: { locationIds?: string; attention?: boolean } = {}) {
  return apiRequest<{ items: ShopStockItem[] }>(
    `${BASE}/stock${query({ location_ids: params.locationIds, attention: params.attention })}`,
    { token },
  );
}

export function fetchShopMovements(token: string, params: { variantId?: string; locationIds?: string; limit?: number } = {}) {
  return apiRequest<{ movements: ShopStockMovement[] }>(
    `${BASE}/stock/movements${query({ variant_id: params.variantId, location_ids: params.locationIds, limit: params.limit })}`,
    { token },
  );
}

export async function recordShopMovement(token: string, body: ShopMovementInput) {
  const data = await apiRequest<{ movement: ShopStockMovement }>(`${BASE}/stock/movements`, { method: "POST", token, body });
  return data.movement;
}

// ---- desk sale (TODO(ADR-190): /admin/shop/pos/sales, /admin/shop/payment-methods) ----

export async function createPosSale(token: string, body: PosSaleInput) {
  const data = await apiRequest<{ order: ShopOrder }>(`${BASE}/pos/sales`, { method: "POST", token, body });
  return data.order;
}

export async function fetchShopPaymentMethods(token: string) {
  const data = await apiRequest<{ methods: ShopPaymentMethodInfo[] }>(`${BASE}/payment-methods`, { token });
  return data.methods;
}

// ---- reports (ADR-192 §4; TODO(ADR-192): endpoints pending on …-shop-analytics) ----

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

export function fetchShopReport<Name extends ShopReportName>(token: string, name: Name, window: ReportWindow = {}) {
  return apiRequest<ReportOf[Name]>(`${BASE}/reports/${name}${query({ days: window.days, location_ids: window.locationIds })}`, { token });
}
