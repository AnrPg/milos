import { expect, test, type Page, type Route } from "./support/test";

// In-app walkthroughs (ADR-193): the shop guide over the real shop console,
// started from the header, driven by the person's own taps, resumed through
// the server's progress and finished; the first-visit offer once. The API is
// stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const NOW = "2026-10-24T09:00:00Z";
const OWNER = { id: "owner-1", nickname: "Apostolos", role: "admin" };

function user() {
  return {
    ...OWNER,
    email: "owner-1@example.com",
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
  };
}

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: OWNER.id, role: OWNER.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const membership = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: "all", manage_members: "all", manage_shop: "all", take_payments: "all", view_business_analytics: "all" },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const variant = { id: "var-1", title: null, option_values: {}, sku: null, barcode: null, price_cents: 2500, compare_at_price_cents: null, cost_price_cents: 1100, low_stock_threshold: null, track_inventory: true, stock_status: "ok", stock: { on_hand: 12, reserved: 0, available: 12, by_location: [] }, archived_at: null };
const product = { id: "prod-1", title: "Box T-shirt", description: null, category: "Apparel", media_ids: [], options: { axes: [] }, status: "published", visibility: "members_only", sell_in_app: true, sell_at_desk: true, member_discount_applies: false, per_person_limit: null, all_locations: true, location_ids: [], published_at: NOW, archived_at: null, variants: [variant] };

type Progress = { guide_id: string; version: number; status: string; step: number; runs: number; started_at: string; completed_at: string | null; updated_at: string };

async function setUp(page: Page, stored: Progress[] = []) {
  const rows = [...stored];
  const puts: Array<{ guide: string; body: Record<string, unknown> }> = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh", user: user() })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user())));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/event-hosts", (route) => route.fulfill(json([])));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/guides**", (route: Route) => {
    const request = route.request();
    if (request.method() === "GET") return route.fulfill(json({ guides: rows }));
    const guide = new URL(request.url()).pathname.split("/").pop()!;
    const body = request.postDataJSON() as Record<string, unknown>;
    puts.push({ guide, body });
    const row = { guide_id: guide, version: Number(body.version ?? 1), status: String(body.status), step: Number(body.step ?? 0), runs: 1, started_at: NOW, completed_at: body.status === "completed" ? NOW : null, updated_at: NOW };
    rows.splice(0, rows.length, ...rows.filter((entry) => entry.guide_id !== guide), row);
    return route.fulfill(json(row));
  });
  await page.route("**/api/admin/locations", (route) => route.fulfill(json([])));
  // The reports are not this spec's concern: they answer an error, which the Analytics tab shows.
  await page.route("**/admin/shop/reports/**", (route) => route.fulfill(json({ error: "unavailable" }, 503)));
  await page.route("**/api/org/kypseli/staff/shop/**", (route: Route) => {
    const path = new URL(route.request().url()).pathname.replace(/^.*\/staff\/shop/, "");
    if (path === "/products") return route.fulfill(json({ products: [product], counts: { all: 1, published: 1, draft: 0, archived: 0, low_stock: 0 } }));
    if (path === "/orders") return route.fulfill(json({ orders: [], counts: { placed: 0, ready_for_pickup: 0, picked_up: 0, cancelled: 0 } }));
    if (path === "/movements") return route.fulfill(json({ movements: [], next_cursor: null }));
    return route.fulfill(json({}));
  });
  return puts;
}

const card = (page: Page) => page.getByTestId("guide-card");

test("the shop guide walks the real console, tap by tap, and is recorded as done", async ({ page }) => {
  const puts = await setUp(page, [
    { guide_id: "shop_staff", version: 1, status: "dismissed", step: 0, runs: 1, started_at: NOW, completed_at: null, updated_at: NOW },
  ]);
  await page.goto("/org/kypseli/admin/shop");
  // Turned down before: no offer, the header button still starts it.
  await expect(page.getByTestId("guide-offer")).toHaveCount(0);
  await page.getByTestId("guide-button-shop_staff").click();

  await expect(card(page)).toContainText("Your box's shop");
  await page.getByTestId("guide-next").click();

  // The person taps the real button; the guide follows into the editor.
  await expect(card(page)).toContainText("Tap «New product»");
  await expect(card(page)).toHaveAttribute("data-guide-step", "shop_staff.newProduct");
  await page.locator('[data-guide="shop.newProduct"]').click();
  await expect(page).toHaveURL(/\/admin\/shop\/products\/new/);
  await expect(card(page)).toHaveAttribute("data-guide-step", "shop_staff.photos");

  for (const step of ["price", "selling", "save", "ordersTab"]) {
    await page.getByTestId("guide-next").click();
    await expect(card(page)).toHaveAttribute("data-guide-step", `shop_staff.${step}`);
  }
  // Back on the console; «Do it for me» taps the Orders tab.
  await expect(page).toHaveURL(/\/admin\/shop$/);
  await page.getByTestId("guide-next").click();
  await expect(card(page)).toHaveAttribute("data-guide-step", "shop_staff.orders");
  await expect(page).toHaveURL(/tab=orders/);

  for (const step of ["pos", "stock", "analytics", "done"]) {
    await page.getByTestId("guide-next").click();
    await expect(card(page)).toHaveAttribute("data-guide-step", `shop_staff.${step}`);
  }
  await expect(page).toHaveURL(/tab=analytics/);
  await page.getByTestId("guide-next").click();
  await expect(card(page)).toHaveCount(0);
  expect(puts.at(-1)).toEqual({ guide: "shop_staff", body: { status: "completed", step: 11, version: 1 } });
});

test("a first visit offers the guide once; «Not now» is kept", async ({ page }) => {
  const puts = await setUp(page);
  await page.goto("/org/kypseli/admin/shop");
  const offer = page.getByTestId("guide-offer");
  await expect(offer).toContainText("Run your shop");
  await offer.getByRole("button", { name: "Not now" }).click();
  await expect(offer).toHaveCount(0);
  await expect.poll(() => puts.at(-1)?.body.status).toBe("dismissed");
  await page.reload();
  await expect(page.getByTestId("guide-button-shop_staff")).toBeVisible();
  await expect(offer).toHaveCount(0);
});

test("Escape ends a guide and a phone gets the card as a sheet", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const puts = await setUp(page);
  await page.goto("/org/kypseli/admin/shop");
  await page.getByTestId("guide-offer-start").click();
  await page.getByTestId("guide-next").click();
  const box = await card(page).boundingBox();
  const width = page.viewportSize()!.width;
  // A sheet across the screen, not a floating card.
  expect(box!.width).toBeGreaterThan(width - 40);
  await page.keyboard.press("Escape");
  await expect(card(page)).toHaveCount(0);
  await expect.poll(() => puts.at(-1)?.body).toEqual({ status: "dismissed", step: 1, version: 1 });
});
