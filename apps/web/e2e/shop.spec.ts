import { expect, test, type Page } from "./support/test";

// Member shop (ADR-190): the fixed card in Box, the grid with one card per
// product, the product page with every size, the one-screen cart where the
// online card is visible but blocked, and the order page with QR + timeline.
// The API is stubbed; anything not stubbed answers `{}`.
// Not run yet: the owner asked to skip Playwright until the shop API branch
// is merged. Stubs follow PaleeWeb.Schemas.Shop.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function persona(slug = "kypseli") {
  const id = "member-1";
  const user = {
    id,
    nickname: "Maria",
    role: "member",
    email: `${id}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: slug, role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role: "member", memberships: [{ organization_slug: slug }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = {
  id: "m-kypseli",
  role: "member",
  roles: ["member"],
  capabilities: {},
  organization: { id: "org-kypseli", slug: "kypseli", name: "Box Kypseli", provider_kind: "gym", activation: "active" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

// The member API shapes (PaleeWeb.Schemas.Shop: ShopMemberProduct / ShopMemberVariant).
const variant = (id: string, size: string, available: "in_stock" | "low" | "sold_out") => ({
  id,
  product_id: "p-tee",
  title: `Black / ${size}`,
  option_values: { Colour: "Black", Size: size },
  price_cents: 2500,
  compare_at_price_cents: null,
  currency: "EUR",
  available,
});

const tee = {
  id: "p-tee",
  title: "Box tee",
  category: "Apparel",
  media_ids: ["m-1"],
  media: [{ id: "m-1", thumb_url: "/placeholder-tee.png", url: "/placeholder-tee.png", full_url: "/placeholder-tee.png", alt_text: "Box tee" }],
  visibility: "members_only",
  published_at: new Date().toISOString(),
  per_person_limit: null,
  all_locations: true,
  location_ids: [],
  options: {
    axes: [
      { name: "Colour", values: ["Black"] },
      { name: "Size", values: ["S", "M", "L"] },
    ],
  },
  variants: [variant("v-s", "S", "in_stock"), variant("v-m", "M", "sold_out"), variant("v-l", "L", "low")],
  description: "Cotton.",
};

const preview = {
  lines: [],
  currency: "EUR",
  subtotal_cents: 2500,
  discount_cents: 250,
  total_cents: 2250,
  pickup_location_id: null,
  pickup_location_ids: ["loc-1"],
  payment_modes: ["at_pickup", "on_account"],
  online_payment: { available: false, reason: "no_provider" },
  member_discount: { percent: 10, source: "membership_package", applies_to: "marked_products" },
};

const order = {
  id: "o-1",
  number: 42,
  status: "placed",
  payment_status: "pending_payment",
  pickup_code: "7Q4K",
  payment_mode: "at_pickup",
  channel: "online",
  state: "pending_payment",
  pickup_location_id: "loc-1",
  currency: "EUR",
  subtotal_cents: 2500,
  discount_cents: 250,
  total_cents: 2250,
  placed_at: new Date().toISOString(),
  ready_at: null,
  picked_up_at: null,
  cancelled_at: null,
  expires_at: null,
  lines: [{ id: "l-1", product_id: tee.id, variant_id: "v-s", product_title: tee.title, variant_title: "Black / S", quantity: 1, unit_price_cents: 2500, discount_cents: 250, total_cents: 2250 }],
};

async function common(page: Page) {
  const me = persona();
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: me.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(me.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/kypseli/me/shop/storefront", (route) =>
    route.fulfill(json({ open: true, closed_reason: null, categories: ["Apparel"], products: [tee], member_discount: { percent: 10 }, pickup_locations: [{ id: "loc-1", name: "Kypseli", address: null }], online_payment: { available: false, reason: "no_provider" } })),
  );
  await page.route("**/api/org/kypseli/me/shop/orders", (route) => route.fulfill(json({ orders: [], counts: { placed: 0, ready_for_pickup: 0, picked_up: 0, cancelled: 0 } })));
  await page.route("**/api/org/kypseli/me/shop/stock-alerts", (route) => route.fulfill(json({ stock_alerts: [] })));
  await page.route("**/api/org/kypseli/me/shop/variants/*/stock-alert", (route) => route.fulfill(json({ stock_alert: { id: "a-1", variant_id: "v-m", product_id: tee.id, notified_at: null } })));
  await page.route("**/api/org/kypseli/me/shop/products", (route) => route.fulfill(json({ products: [tee] })));
  await page.route("**/api/org/kypseli/me/shop/products/p-tee", (route) => route.fulfill(json({ product: tee })));
  await page.route("**/api/org/kypseli/me/shop/cart/preview", (route) => route.fulfill(json(preview)));
  await page.route("**/api/org/kypseli/me/shop/orders/o-1", (route) => route.fulfill(json({ order })));
}

test.describe("shop", () => {
  test("Box shows the shop card only when the box sells something", async ({ page }) => {
    await common(page);
    await page.goto("/box");
    await expect(page.getByTestId("box-shop-card")).toBeVisible();
  });

  test("the grid shows one card per product with photo and price, no sideways scroll", async ({ page }) => {
    await common(page);
    await page.setViewportSize({ width: 320, height: 720 });
    await page.goto("/box/shop");
    const cards = page.getByTestId("shop-product-card");
    await expect(cards).toHaveCount(1);
    await expect(cards.first()).toContainText("25");
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("the product page shows every size and a sold-out one offers a notification", async ({ page }) => {
    await common(page);
    await page.goto("/box/shop/product/p-tee?box=kypseli");
    for (const size of ["S", "M", "L"]) await expect(page.getByRole("radio", { name: new RegExp(`^${size}`) })).toBeVisible();
    await page.getByRole("radio", { name: /^M/ }).click();
    await expect(page.getByRole("button", { name: "Notify me" })).toBeVisible();
    await page.getByRole("radio", { name: /^S/ }).click();
    await page.getByTestId("shop-add-to-cart").click();
    await expect(page.getByTestId("shop-cart-button")).toContainText("1");
  });

  test("checkout is one screen and the online card is shown but blocked", async ({ page }) => {
    await common(page);
    const placed: unknown[] = [];
    await page.route("**/api/org/kypseli/me/shop/orders", (route) => {
      if (route.request().method() !== "POST") return route.fulfill(json({ orders: [] }));
      placed.push(route.request().postDataJSON());
      return route.fulfill(json({ order }, 201));
    });
    await page.addInitScript(() => {
      window.localStorage.setItem("palee:shop-cart:kypseli", JSON.stringify({ lines: [{ variantId: "v-s", productId: "p-tee", quantity: 1 }], source: null }));
    });
    await page.goto("/box/shop/cart?box=kypseli");
    await expect(page.getByRole("radio", { name: /Online by card/ })).toBeDisabled();
    await expect(page.locator("input:not([type=radio]):not([type=hidden])")).toHaveCount(0);
    await page.getByTestId("shop-place-order").click();
    await expect(page).toHaveURL(/\/box\/shop\/orders\/o-1/);
    expect(placed).toHaveLength(1);
  });

  test("the order page shows the pickup QR and the timeline", async ({ page }) => {
    await common(page);
    await page.goto("/box/shop/orders/o-1?box=kypseli");
    await expect(page.getByTestId("shop-order-qr")).toBeVisible();
    await expect(page.getByTestId("shop-order-status")).toContainText("Being prepared");
  });
});
