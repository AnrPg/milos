import { expect, test, type Page } from "@playwright/test";

// Phase 3 M9 (ADR-171): the store apps wrap this same web app. In a browser
// nothing changes; inside the app (simulated here with the bridge the native
// shell injects) the page is marked for safe-area padding and «Συνδεδεμένες
// συσκευές» shows only this phone's health row, as «Σύντομα» until the health
// plugin ships. The API is stubbed; every route not listed answers {}.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    completed_tours: ["admin", "member", "athlete"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

async function devicesPage(page: Page) {
  const { user, token } = persona();
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
  await page.route("**/api/me/devices", (route) =>
    route.fulfill(
      json({
        wallet: { passes: [], platforms: { apple: false, google: false } },
        calendar: { https_url: "https://example.com/cal.ics", webcal_url: "webcal://example.com/cal.ics", download_url: null },
        integrations: [
          { provider: "garmin", status: "unavailable", configured: false, capability: "not_configured", connection: null },
          { provider: "apple_health", status: "native_only" },
          { provider: "health_connect", status: "native_only" },
        ],
      }),
    ),
  );
}

// What Capacitor's iOS shell injects before the page runs: the bridge object
// and the WebKit message handler @capacitor/core detects iOS by (no plugins).
const IOS_BRIDGE = `window.webkit = { messageHandlers: { bridge: { postMessage() {} } } };
window.Capacitor = {
  isNativePlatform: () => true,
  getPlatform: () => "ios",
  isPluginAvailable: () => false,
  Plugins: {},
  PluginHeaders: [],
};`;

test.describe("store app wrapper", () => {
  test("app-link files are not served until the store ids are configured", async ({ request }) => {
    expect((await request.get("/.well-known/apple-app-site-association")).status()).toBe(404);
    expect((await request.get("/.well-known/assetlinks.json")).status()).toBe(404);
  });

  test("in a browser both phone-health rows keep «With the app»", async ({ page }) => {
    await devicesPage(page);
    await page.goto("/me/devices");
    const section = page.getByTestId("devices-integrations");
    await expect(section).toContainText("Apple Health");
    await expect(section).toContainText("Health Connect");
    await expect(section.getByText("With the app")).toHaveCount(2);
    await expect(page.locator("html")).not.toHaveAttribute("data-platform", /.+/);
  });

  test("inside the iOS app only Apple Health shows, as Soon", async ({ page }) => {
    await page.addInitScript(IOS_BRIDGE);
    await devicesPage(page);
    await page.goto("/me/devices");
    await expect(page.locator("html")).toHaveAttribute("data-platform", "ios");
    const section = page.getByTestId("devices-integrations");
    await expect(section).toContainText("Apple Health");
    await expect(section).not.toContainText("Health Connect");
    const appleHealth = section.locator("li", { hasText: "Apple Health" });
    await expect(appleHealth).toContainText("Soon");
    await expect(appleHealth).toContainText("Coming in a later version of the app.");
  });
});
