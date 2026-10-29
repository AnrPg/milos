import { expect, test, type Page, type Route } from "./support/test";

// First setup and «Προχωρημένα» (ADR-255, mockup s10 option A): the owner
// picks a kind of box, sees what will be set up, changes a price and
// applies; in Ρυθμίσεις the settings with a good default sit in one closed
// «Προχωρημένα» card with a search. The API is stubbed.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

function tokenFor(id: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

const membership = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, manage_users: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const recipe = (key: string, en: string, summary: string) => ({
  key,
  version: 1,
  name: en,
  names: { en, el: en },
  summary,
  summaries: { en: summary, el: summary },
  provider_kind: "gym",
  settings: [],
  class_types: [],
  packages: [
    { code: "setup_unlimited", name: "Unlimited", package_type: "subscription", billing_period: "monthly", base_price_cents: 7500 },
    { code: "setup_trial", name: "Trial", package_type: "trial", billing_period: "none", base_price_cents: 1000 },
  ],
  role_grants: {},
  documents: [],
});

const change = (area: string, key: string, to: unknown, name: string | null = null) => ({
  area,
  key,
  action: area === "setting" ? "set" : "create",
  from: null,
  to,
  name,
  advanced: false,
  owner_changed: false,
});

const plan = {
  recipe: "crossfit_box",
  version: 1,
  name: "CrossFit box",
  changes: [
    change("package", "package.setup_unlimited", 7500, "Unlimited"),
    change("package", "package.setup_trial", 1000, "Trial"),
    change("class_type", "class_type.crossfit", "CrossFit", "CrossFit"),
    change("setting", "scheduling.default_auto_approve", true),
    change("setting", "scheduling.default_cancellation_cutoff_minutes", 120),
    change("setting", "gamification.streak_shields", 2),
    // The owner already set 20 places per class: applying asks (product decision 2026-10-29).
    { ...change("setting", "scheduling.default_capacity", 16), from: 20, owner_changed: true },
  ],
  manual: [],
  unchanged: [],
  kept: [] as string[],
  change_count: 7,
};

const catalog = {
  settings: [
    { key: "scheduling.default_capacity", section: "scheduling", field: "default_capacity", verdict: "basic", advanced: false, default: 12, set_by_recipe: true },
    { key: "scheduling.default_auto_approve", section: "scheduling", field: "default_auto_approve", verdict: "basic", advanced: false, default: false, set_by_recipe: true },
    { key: "scheduling.default_cancellation_cutoff_minutes", section: "scheduling", field: "default_cancellation_cutoff_minutes", verdict: "basic", advanced: false, default: null, set_by_recipe: true },
    { key: "scheduling.default_booking_window_days", section: "scheduling", field: "default_booking_window_days", verdict: "advanced", advanced: true, default: null, set_by_recipe: true },
    { key: "gamification.leaderboard_enabled", section: "gamification", field: "leaderboard_enabled", verdict: "basic", advanced: false, default: true, set_by_recipe: true },
    { key: "gamification.streak_shields", section: "gamification", field: "streak_shields", verdict: "advanced", advanced: true, default: 1, set_by_recipe: true },
    { key: "gamification.streak_shield_reset_day", section: "gamification", field: "streak_shield_reset_day", verdict: "advanced", advanced: true, default: null, set_by_recipe: false },
    { key: "provider.kind", section: "provider", field: "kind", verdict: "derive", advanced: false, default: "gym", set_by_recipe: true },
  ],
  counts: { basic: 4, advanced: 3, derive: 1, remove: 0 },
  advanced_settings: ["scheduling.default_booking_window_days", "gamification.streak_shields", "gamification.streak_shield_reset_day"],
};

type Write = { path: string; body: unknown };

async function stub(page: Page, writes: Write[]) {
  let applications: unknown[] = [];
  await page.route("**/api/**", async (route) => {
    const request = route.request();
    const path = tenantless(new URL(request.url()).pathname);
    const method = request.method();
    if (method !== "GET") writes.push({ path, body: request.postDataJSON() });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner.id), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [membership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/setup/recipes") {
      return json(route, {
        recipes: [recipe("crossfit_box", "CrossFit box", "Classes with a WOD of the day"), recipe("independent_coach", "Independent coach", "Online programming")],
        applications,
        can_apply: true,
        currency: "EUR",
      });
    }
    if (path === "/api/admin/setup/recipes/crossfit_box/preview") return json(route, plan);
    if (path === "/api/admin/setup/recipes/crossfit_box/apply") {
      const keep = (request.postDataJSON() as { mode?: string }).mode === "defaults_only";
      const changes = plan.changes.filter((entry) => !(keep && entry.owner_changed));
      const kept = keep ? plan.changes.filter((entry) => entry.owner_changed).map((entry) => entry.key) : [];
      const application = { id: "app-1", recipe_key: "crossfit_box", recipe_version: 1, applied_by_id: owner.id, applied_at: "2026-10-29T10:00:00Z", changes, manual: [], change_count: changes.length };
      applications = [application];
      return json(route, { plan: { ...plan, changes, kept, change_count: changes.length }, application });
    }
    if (path === "/api/admin/setup/settings") return json(route, catalog);
    if (path === "/api/admin/settings") {
      return json(route, {
        advanced_settings: catalog.advanced_settings,
        time_zone: { timezone: "Europe/Athens", source: "confirmed", confirmed: true },
        gamification: { streak_shields: 1, streak_shield_reset_day: null, leaderboard_enabled: true },
        finance: { payment_reminder_interval_days: 7, subscription_expiry_reminder_days: 5, subscription_grace_days: 3, document_mode: "invoice", package_modules: [] },
        scheduling: { default_capacity: 12, default_auto_approve: false, default_booking_timeout_minutes: 60, default_booking_window_days: null, default_cancellation_cutoff_minutes: 720 },
        provider: { kind: "gym", editable: true },
        workouts: { wod_goals_visible_by_default: false, wod_assistant_enabled: true },
      });
    }
    if (path.endsWith("/join-link")) return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    return json(route, {});
  });
}

test("the owner picks a kind of box, changes a price and applies the recipe", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/setup");

  await expect(page.getByRole("heading", { name: "What kind of box do you run?" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Continue" })).toBeDisabled();
  await page.getByTestId("recipe-crossfit_box").click();
  await page.getByRole("button", { name: "Continue" }).click();

  await expect(page.getByRole("heading", { name: "CrossFit box: what will be set up" })).toBeVisible();
  await expect(page.getByLabel("Unlimited")).toHaveValue("75");
  await expect(page.getByText("Bookings confirmed automatically")).toBeVisible();
  await expect(page.getByText("Late cancellation: 2 hours")).toBeVisible();
  await expect(page.getByText(/Plus 1 setting with a good default/)).toBeVisible();

  const owned = page.getByTestId("recipe-owner-values");
  await expect(owned).toContainText("1 setting you already changed");
  await expect(page.getByTestId("owner-value-scheduling.default_capacity")).toContainText("Places per class");

  await page.getByLabel("Unlimited").fill("80");
  await page.getByTestId("recipe-apply").click();
  await expect(owned.getByText("Choose what happens to the settings you changed.")).toBeVisible();
  expect(writes.some((write) => write.path.endsWith("/apply"))).toBe(false);
  await owned.getByRole("radio", { name: /Keep mine/ }).check();
  await page.getByTestId("recipe-apply").click();

  await expect(page.getByTestId("recipe-applied")).toContainText("Your box is set up as CrossFit box");
  await expect(page.getByTestId("recipe-applied")).toContainText("2 subscription packages · 1 class type · 3 rules");
  await expect(page.getByTestId("recipe-kept")).toContainText("1 setting kept as you set it");
  expect(writes.find((write) => write.path.endsWith("/apply"))?.body).toEqual({ prices: { setup_unlimited: 8000 }, mode: "defaults_only" });
  await expect(page.getByRole("link", { name: /Bring your members/ })).toHaveAttribute("href", /\/admin\/users\/import$/);
});

test("Settings keep the settings with a good default in one closed «Advanced» card", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/settings");

  const basic = page.getByTestId("class-booking-defaults");
  await expect(basic).toBeVisible();
  await expect(basic.getByText("Bookings open (days before the class)")).toHaveCount(0);
  // Derived and confirmed settings are not inputs.
  await expect(page.locator("#time-zone")).toHaveCount(0);
  await expect(page.locator("#provider-kind")).toHaveCount(0);

  const card = page.getByTestId("advanced-settings");
  const toggle = card.getByRole("button", { name: /Advanced/ });
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await expect(toggle).toContainText("3 settings with a good default. People rarely change them.");
  await toggle.click();

  await expect(page.getByTestId("advanced-group-bookings")).toContainText("Bookings open (days before the class)");
  await card.getByRole("searchbox", { name: "Search settings" }).fill("shield");
  await expect(page.getByTestId("advanced-group-motivation")).toBeVisible();
  await expect(page.getByTestId("advanced-group-bookings")).toHaveCount(0);

  await page.getByTestId("advanced-group-motivation").getByRole("spinbutton", { name: /Streak shields per renewal/ }).fill("2");
  await page.getByTestId("advanced-group-motivation").getByRole("button", { name: "Save", exact: true }).first().click();
  await expect.poll(() => writes.find((write) => write.path === "/api/admin/settings")?.body).toEqual({ gamification: { streak_shields: 2, streak_shield_reset_day: null } });
});
