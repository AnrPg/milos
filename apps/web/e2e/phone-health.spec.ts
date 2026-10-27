import { expect, test, type Page, type Request } from "./support/test";

// Phase 3 M10 (ADR-172): Apple Health and Health Connect inside the store
// apps. The native shell is simulated with the bridge Capacitor injects plus
// a PaleeHealth plugin header whose calls answer from a fake; the API is
// stubbed and every route not listed answers {}.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const ALL_ON = { activities: true, sleep: true, weight: true, resting_hr: true, steps: true };
const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();

type Row = { provider: string; status: string; sync_prefs?: Record<string, boolean>; history_days?: number; connection?: unknown };

function connectedRow(provider: string, lastSync: string | null, prefs = ALL_ON): Row {
  return {
    provider,
    status: "connected",
    sync_prefs: prefs,
    history_days: 30,
    connection: { status: "active", connected_at: minutesAgo(5), last_synced_at: lastSync, read_from: minutesAgo(30 * 24 * 60), sync_prefs: prefs },
  };
}

async function devicesPage(page: Page, rows: () => Row[]) {
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
  await page.route("**/api/me/body/consents", (route) => route.fulfill(json({ consents: [{ scope: "health_data", active: false }] })));
  await page.route("**/api/me/devices", (route) =>
    route.fulfill(
      json({
        wallet: { passes: [], platforms: { apple: false, google: false } },
        calendar: { https_url: "https://example.com/cal.ics", webcal_url: "webcal://example.com/cal.ics", download_url: null },
        integrations: [{ provider: "garmin", status: "unavailable", configured: false, capability: "not_configured", connection: null }, ...rows()],
      }),
    ),
  );
}

// Capacitor's iOS/Android shell, with the PaleeHealth header and a fake
// behind `nativePromise`. Every call lands in window.__healthCalls.
function nativeBridge(platform: "ios" | "android", availability: Record<string, unknown> = { available: true }) {
  return `
${platform === "ios" ? "window.webkit = { messageHandlers: { bridge: { postMessage() {} } } };" : "window.androidBridge = { postMessage() {} };"}
window.__healthCalls = [];
const now = Date.now();
const iso = (minutes) => new Date(now - minutes * 60000).toISOString().replace(/\\.\\d{3}Z$/, "Z");
window.Capacitor = {
  isNativePlatform: () => true,
  getPlatform: () => "${platform}",
  isPluginAvailable: (name) => name === "PaleeHealth",
  Plugins: {},
  PluginHeaders: [{ name: "PaleeHealth", methods: [
    { name: "availability", rtype: "promise" },
    { name: "requestAuthorization", rtype: "promise" },
    { name: "read", rtype: "promise" },
    { name: "openInstaller", rtype: "promise" }
  ] }],
  nativePromise: (plugin, method, options) => {
    window.__healthCalls.push({ plugin, method, options });
    if (method === "availability") return Promise.resolve(${JSON.stringify(availability)});
    if (method === "requestAuthorization") return Promise.resolve({ asked: options.kinds, granted: ${platform === "ios" ? "null" : "options.kinds.filter((kind) => kind !== 'weight')"} });
    if (method === "read") return Promise.resolve({
      workouts: [{ id: "w-1", type: "RUNNING", start: iso(180), end: iso(140), offset_minutes: 180, distance_m: 8000, avg_hr: 150 }],
      sleep: [{ id: "s-1", start: iso(60 * 10), end: iso(60 * 3), offset_minutes: 180, stage: "asleep" }],
      steps: [{ date: new Date(now).toISOString().slice(0, 10), count: 4200 }],
    });
    return Promise.resolve({});
  },
};`;
}

test.describe("phone health in the store apps", () => {
  test("Apple Health connects with the consent, asks the phone, then syncs", async ({ page }) => {
    let rows: Row[] = [{ provider: "apple_health", status: "native_only", sync_prefs: ALL_ON, history_days: 30, connection: null }, { provider: "health_connect", status: "native_only" }];
    await page.addInitScript(nativeBridge("ios"));
    await devicesPage(page, () => rows);
    await page.route("**/api/me/devices/phone/apple_health/connect", (route) => {
      const prefs = bodyOf(route.request()).sync_prefs;
      rows = [connectedRow("apple_health", null, prefs), { provider: "health_connect", status: "native_only" }];
      return route.fulfill(json({ row: rows[0] }, 201));
    });
    await page.route("**/api/me/devices/phone/apple_health/ingest", (route) =>
      route.fulfill(json({ counts: { imported: 3 }, row: connectedRow("apple_health", minutesAgo(0), { ...ALL_ON, weight: false }) })),
    );

    await page.goto("/me/devices");
    const section = page.getByTestId("devices-integrations");
    await expect(section).not.toContainText("Health Connect");
    const row = page.getByTestId("phone-health-row-apple_health");
    await expect(row).toContainText("Workouts, sleep, weight, resting heart rate and steps from your phone.");
    await row.getByRole("button", { name: "Connect" }).click();

    const sheet = page.getByRole("dialog", { name: "Connect Apple Health" });
    await expect(sheet).toBeVisible();
    for (const name of ["Workouts", "Sleep", "Weight", "Resting heart rate", "Steps"]) {
      await expect(sheet.getByRole("switch", { name })).toHaveAttribute("aria-checked", "true");
    }
    await expect(sheet).toContainText("The last 30 days come in");
    await sheet.getByRole("switch", { name: "Weight" }).click();
    const proceed = sheet.getByRole("button", { name: "Continue" });
    await expect(proceed).toBeDisabled();
    await sheet.getByRole("checkbox").check();

    const connected = page.waitForRequest((request) => request.url().endsWith("/phone/apple_health/connect") && request.method() === "POST");
    const ingested = page.waitForRequest((request) => request.url().endsWith("/phone/apple_health/ingest"));
    await proceed.click();
    expect(bodyOf(await connected)).toEqual({ sync_prefs: { ...ALL_ON, weight: false }, health_data_consent: true });
    const batch = bodyOf(await ingested);
    expect(batch.activities).toHaveLength(1);
    expect(batch.activities[0].start).toMatch(/\+03:00$/);
    expect(batch.sleeps).toHaveLength(1);
    expect(batch.dailies[0].steps).toBe(4200);

    const calls = await page.evaluate(() => (window as unknown as { __healthCalls: Array<{ method: string; options: { kinds?: string[] } }> }).__healthCalls);
    expect(calls.find((call) => call.method === "requestAuthorization")?.options.kinds).toEqual(["activities", "sleep", "resting_hr", "steps"]);
    expect(calls.find((call) => call.method === "read")?.options.kinds).toEqual(["activities", "sleep", "resting_hr", "steps"]);

    await expect(page.getByText("Apple Health is connected. Your data is on its way.")).toBeVisible();
    await expect(row).toContainText("Active");
    await expect(row.getByTestId("phone-health-last-sync")).toContainText("Last synced just now");
    await expect(row).toContainText("Workouts, Sleep, Resting heart rate, Steps");
    await expect(page.getByTestId("device-data-export")).toBeVisible();
    await page.screenshot({ path: "test-results/phone-health/connected.png" });
  });

  test("a Health Connect connection refused on the phone stays unconnected", async ({ page }) => {
    await page.addInitScript(nativeBridge("android").replace("options.kinds.filter((kind) => kind !== 'weight')", "[]"));
    await devicesPage(page, () => [{ provider: "apple_health", status: "native_only" }, { provider: "health_connect", status: "native_only", sync_prefs: ALL_ON, history_days: 30, connection: null }]);
    let connectCalls = 0;
    await page.route("**/api/me/devices/phone/health_connect/connect", (route) => {
      connectCalls += 1;
      return route.fulfill(json({}, 500));
    });

    await page.goto("/me/devices");
    await expect(page.getByTestId("devices-integrations")).not.toContainText("Apple Health");
    await page.getByTestId("phone-health-row-health_connect").getByRole("button", { name: "Connect" }).click();
    const sheet = page.getByRole("dialog", { name: "Connect Health Connect" });
    await sheet.getByRole("checkbox").check();
    await sheet.getByRole("button", { name: "Continue" }).click();
    await expect(sheet).toContainText("No access was given.");
    expect(connectCalls).toBe(0);
  });

  test("without Health Connect installed the row offers the installer", async ({ page }) => {
    await page.addInitScript(nativeBridge("android", { available: false, reason: "not_installed" }));
    await devicesPage(page, () => [{ provider: "apple_health", status: "native_only" }, { provider: "health_connect", status: "native_only", sync_prefs: ALL_ON, history_days: 30, connection: null }]);
    await page.goto("/me/devices");
    const row = page.getByTestId("phone-health-row-health_connect");
    await expect(row).toContainText("The Health Connect app is needed.");
    await row.getByRole("button", { name: "Install" }).click();
    await expect
      .poll(() => page.evaluate(() => (window as unknown as { __healthCalls: Array<{ method: string }> }).__healthCalls.map((call) => call.method)))
      .toContain("openInstaller");
  });

  test("a connected row syncs on its own when the app opens and can disconnect", async ({ page }) => {
    let rows: Row[] = [connectedRow("apple_health", minutesAgo(120)), { provider: "health_connect", status: "native_only" }];
    await page.addInitScript(nativeBridge("ios"));
    await devicesPage(page, () => rows);
    await page.route("**/api/me/devices/phone/apple_health/ingest", (route) => route.fulfill(json({ counts: { imported: 1, duplicate: 2 }, row: connectedRow("apple_health", minutesAgo(0)) })));
    await page.route("**/api/me/devices/phone/apple_health?**", (route) => {
      rows = [{ provider: "apple_health", status: "native_only", sync_prefs: ALL_ON, history_days: 30, connection: null }, { provider: "health_connect", status: "native_only" }];
      return route.fulfill(json({ deleted: true, disconnected: true }));
    });

    const ingested = page.waitForRequest((request) => request.url().endsWith("/phone/apple_health/ingest"));
    await page.goto("/me/devices");
    await ingested;
    const row = page.getByTestId("phone-health-row-apple_health");
    await expect(row.getByTestId("phone-health-last-sync")).toContainText("Last synced just now");

    await row.getByRole("button", { name: "Disconnect" }).click();
    const sheet = page.getByRole("dialog", { name: "Disconnect Apple Health" });
    await expect(sheet.getByTestId("phone-health-disconnect-sheet")).toBeVisible();
    await sheet.getByRole("radio", { name: /Delete all Apple Health data/ }).click();
    await sheet.getByTestId("phone-health-disconnect-confirm").click();
    await expect(sheet).toContainText("delete everything it brought in?");
    const removed = page.waitForRequest((request) => request.method() === "DELETE");
    await sheet.getByRole("button", { name: "Yes, disconnect" }).click();
    expect((await removed).url()).toContain("/phone/apple_health?delete_data=true");
    await expect(page.getByText("Apple Health is disconnected and everything it brought in was deleted.")).toBeVisible();
    await expect(row.getByRole("button", { name: "Connect" })).toBeVisible();
  });

  test("seen in a browser, a connected phone row says it syncs from the app", async ({ page }) => {
    await devicesPage(page, () => [connectedRow("apple_health", minutesAgo(90)), { provider: "health_connect", status: "native_only" }]);
    await page.goto("/me/devices");
    const row = page.getByTestId("phone-health-row-apple_health");
    await expect(row).toContainText("syncs from the app on your phone");
    await expect(row.getByRole("button", { name: "Sync now" })).toHaveCount(0);
    await expect(page.getByTestId("devices-integrations").getByText("With the app")).toHaveCount(1);
  });
});
