import { expect, test, type Page, type Route } from "./support/test";

// Shop console (shop proposal §2, option A; ADR-190, `ShopController`): the «Shop» section with
// its empty-state checklist, a new product saved as a draft, publishing
// blocked for a demo business (ADR-184), an order marked ready, and a sale at
// the till. The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const NOW = "2026-10-23T09:00:00Z";
const OWNER = { id: "owner-1", nickname: "Apostolos", role: "admin" };

function userFor() {
  return {
    ...OWNER,
    email: "owner-1@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
  };
}

function tokenFor() {
  const payload = Buffer.from(
    JSON.stringify({ sub: OWNER.id, role: OWNER.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

function membership(activation: "demo" | "active" = "active") {
  return {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_settings: "all", manage_members: "all", manage_shop: "all", take_payments: "all", view_business_analytics: "all" },
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation },
    settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
  };
}

async function signedIn(page: Page, activation: "demo" | "active" = "active") {
  const user = userFor();
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh", user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership(activation)])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

const variant = (extra: Record<string, unknown> = {}) => ({
  id: "var-1",
  title: null,
  option_values: {},
  sku: null,
  barcode: null,
  price_cents: 2500,
  compare_at_price_cents: null,
  cost_price_cents: 1100,
  low_stock_threshold: null,
  track_inventory: true,
  stock_status: "ok",
  stock: { on_hand: 12, reserved: 0, available: 12, by_location: [{ location_id: null, on_hand: 12, reserved: 0, available: 12 }] },
  archived_at: null,
  ...extra,
});

const product = (extra: Record<string, unknown> = {}) => ({
  id: "prod-1",
  title: "Box T-shirt",
  description: null,
  category: "Apparel",
  media_ids: [],
  options: { axes: [] },
  status: "published",
  visibility: "members_only",
  sell_in_app: true,
  sell_at_desk: true,
  member_discount_applies: false,
  per_person_limit: null,
  all_locations: true,
  location_ids: [],
  published_at: NOW,
  archived_at: null,
  variants: [variant()],
  ...extra,
});

const order = (extra: Record<string, unknown> = {}) => ({
  id: "ord-1",
  number: 1042,
  channel: "online",
  status: "placed",
  payment_status: "pending_payment",
  payment_mode: "at_pickup",
  user_id: "member-1",
  customer_name: "Eleni",
  pickup_location_id: null,
  currency: "EUR",
  subtotal_cents: 2500,
  discount_cents: 0,
  total_cents: 2500,
  paid_cents: 0,
  refunded_cents: 0,
  source: "direct",
  promotion_code: null,
  finance_invoice_id: null,
  invoice_number: null,
  placed_at: NOW,
  expires_at: "2026-10-30T09:00:00Z",
  ready_at: null,
  picked_up_at: null,
  cancelled_at: null,
  cancel_reason: null,
  lines: [
    { id: "line-1", product_id: "prod-1", variant_id: "var-1", product_title: "Box T-shirt", variant_title: null, quantity: 1, unit_price_cents: 2500, discount_cents: 0, total_cents: 2500, refunded_quantity: 0, refunded_cents: 0, thumb_url: null },
  ],
  ...extra,
});

type Calls = { created: unknown[]; statusChanges: unknown[]; actions: string[]; sales: unknown[] };

/** The shop endpoints of Box Kypseli, with the server's state kept here. */
async function shopApi(page: Page, initial: { products?: ReturnType<typeof product>[]; orders?: ReturnType<typeof order>[] } = {}) {
  const calls: Calls = { created: [], statusChanges: [], actions: [], sales: [] };
  const products = [...(initial.products ?? [])];
  const orders = [...(initial.orders ?? [])];
  const productCounts = () => ({
    all: products.filter((entry) => entry.status !== "archived").length,
    published: products.filter((entry) => entry.status === "published").length,
    draft: products.filter((entry) => entry.status === "draft").length,
    archived: products.filter((entry) => entry.status === "archived").length,
    low_stock: 0,
  });
  const orderCounts = () => ({
    placed: orders.filter((entry) => entry.status === "placed").length,
    ready_for_pickup: orders.filter((entry) => entry.status === "ready_for_pickup").length,
    picked_up: orders.filter((entry) => entry.status === "picked_up").length,
    cancelled: orders.filter((entry) => entry.status === "cancelled").length,
  });

  await page.route("**/api/org/kypseli/staff/shop/**", (route: Route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^.*\/staff\/shop/, "");
    const method = request.method();

    if (path === "/products" && method === "GET") {
      // As on the server: archived products only on request.
      const status = url.searchParams.get("status");
      return route.fulfill(json({ products: products.filter((entry) => (status ? entry.status === status : entry.status !== "archived")), counts: productCounts() }));
    }
    if (path === "/products" && method === "POST") {
      const body = request.postDataJSON() as Record<string, unknown>;
      calls.created.push(body);
      const created = product({ id: "prod-new", title: body.title, status: "draft", published_at: null, variants: [variant({ id: "var-new", price_cents: 1800 })] });
      products.push(created);
      return route.fulfill(json({ product: created }, 201));
    }
    const productMatch = path.match(/^\/products\/([^/]+)(\/status)?$/);
    if (productMatch) {
      const found = products.find((entry) => entry.id === productMatch[1]);
      if (!found) return route.fulfill(json({ error: "not found" }, 404));
      if (productMatch[2] && method === "PUT") calls.statusChanges.push(request.postDataJSON());
      return route.fulfill(json({ product: found }));
    }
    if (path === "/orders" && method === "GET") {
      const status = url.searchParams.get("status");
      return route.fulfill(json({ orders: orders.filter((entry) => !status || entry.status === status), counts: orderCounts() }));
    }
    const orderMatch = path.match(/^\/orders\/([^/]+)(?:\/(ready|pickup|cancel|refund))?$/);
    if (orderMatch) {
      const index = orders.findIndex((entry) => entry.id === orderMatch[1]);
      if (index < 0) return route.fulfill(json({ error: "not found" }, 404));
      if (orderMatch[2]) {
        calls.actions.push(orderMatch[2]);
        if (orderMatch[2] === "ready") orders[index] = order({ ...orders[index], status: "ready_for_pickup", ready_at: NOW });
      }
      return route.fulfill(json({ order: orders[index] }));
    }
    if (path === "/desk-sales" && method === "POST") {
      const body = request.postDataJSON();
      calls.sales.push(body);
      return route.fulfill(json({ order: order({ id: "ord-pos", number: 1043, channel: "pos", status: "picked_up", payment_status: "paid", payment_mode: "cash", paid_cents: 2500, user_id: null, customer_name: null }) }, 201));
    }
    if (path === "/payment-methods") {
      return route.fulfill(
        json({
          payment_methods: [
            { id: "cash", channel: "pos", available: true },
            { id: "card_manual", channel: "pos", available: true },
            { id: "card_online", channel: "online", available: false, reason: "no_provider" },
          ],
        }),
      );
    }
    if (path === "/movements") return route.fulfill(json({ movements: [], next_cursor: null }));
    return route.fulfill(json({}));
  });
  return calls;
}

test.describe("shop console", () => {
  test("an empty catalog shows the three-step checklist, and a new product saves as a draft", async ({ page }) => {
    await signedIn(page);
    const calls = await shopApi(page);

    await page.goto("/admin/shop");
    await expect(page.getByRole("heading", { name: "Sell to your box members from the app" })).toBeVisible();
    await expect(page.getByText("Add your first product")).toBeVisible();
    await expect(page.getByText("Check the pickup point")).toBeVisible();
    await expect(page.getByText("Publish to open the shop")).toBeVisible();
    await expect(page.getByTestId("shop-open-state")).toHaveText("Closed to box members");
    // No till before there is anything to sell.
    await expect(page.getByRole("link", { name: "Till" })).toHaveCount(0);

    // The header and the checklist both offer it; the checklist is the first step.
    await page.getByTestId("shop-empty").getByRole("link", { name: "+ New product" }).click();
    await expect(page).toHaveURL(/\/admin\/shop\/products\/new$/);
    await expect(page.getByText("New products start as drafts. Publish after saving.")).toBeVisible();
    await page.getByLabel("Name", { exact: true }).fill("Box hoodie");
    await page.getByLabel("Price incl. VAT (€)").fill("18");
    await page.getByLabel(/Opening stock of One kind/).fill("5");
    await page.getByRole("button", { name: "Create draft" }).click();

    await expect(page).toHaveURL(/\/admin\/shop\/products\/prod-new$/);
    // The create body has no status: a new product is always a draft.
    expect(calls.created[0]).not.toHaveProperty("status");
    expect(calls.created).toEqual([
      expect.objectContaining({
        title: "Box hoodie",
        sell_in_app: true,
        sell_at_desk: true,
        visibility: "members_only",
        variants: [expect.objectContaining({ price_cents: 1800, initial_quantity: 5, location_id: null })],
      }),
    ]);
  });

  test("a demo business builds the catalog, but publishing opens the activation notice", async ({ page }) => {
    await signedIn(page, "demo");
    const calls = await shopApi(page, { products: [product({ status: "draft", published_at: null })] });

    await page.goto("/admin/shop/products/prod-1");
    await page.getByRole("radiogroup", { name: "Status" }).getByRole("radio", { name: "Active" }).click();

    await expect(page.getByRole("dialog", { name: "Activation by the Palee team" })).toBeVisible();
    expect(calls.statusChanges).toEqual([]);
  });

  test("an order to prepare is marked ready for pickup from its drawer", async ({ page }) => {
    await signedIn(page);
    const calls = await shopApi(page, { products: [product()], orders: [order()] });

    await page.goto("/admin/shop?tab=orders");
    await expect(page.getByTestId("shop-open-state")).toHaveText("Open · 1 product");
    await page.getByTestId("shop-orders").getByRole("button", { name: /K-1042 · Eleni/ }).click();
    await page.getByRole("button", { name: "Ready for pickup" }).click();

    await expect.poll(() => calls.actions).toEqual(["ready"]);
  });

  test("the till sells to a walk-in customer for cash", async ({ page }) => {
    await signedIn(page);
    const calls = await shopApi(page, { products: [product()] });

    await page.goto("/admin/shop/pos");
    await expect(page.getByRole("heading", { name: "Till" })).toBeVisible();
    await page.getByRole("region", { name: "Products" }).getByRole("button", { name: /Box T-shirt/ }).click();
    await page.getByRole("switch", { name: "Customer without an account" }).click();
    await page.getByRole("button", { name: /^Charge/ }).click();

    await expect(page.getByText("Charged · K-1043.", { exact: false })).toBeVisible();
    expect(calls.sales).toEqual([
      expect.objectContaining({
        user_id: null,
        payment_method: "cash",
        lines: [{ variant_id: "var-1", quantity: 1 }],
        idempotency_key: expect.any(String),
      }),
    ]);
  });
});
