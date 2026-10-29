import { expect, test, type Page, type Request } from "./support/test";

// ADR-253, mockup s8 option A with the owner's override: the TV at /tv pairs
// with a code and follows the class by itself; staff manage screens and pin a
// view in Ρυθμίσεις › Οθόνες box. The API is stubbed; every route not listed
// answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");
const inMinutes = (minutes: number) => new Date(Date.now() + minutes * 60_000).toISOString();

function today(view: string, source = "auto") {
  return {
    box: { id: "org-1", name: "Box Kypseli" },
    screen: { id: "s1", name: "Room 1", branch: null },
    date: new Date().toISOString().slice(0, 10),
    time_zone: "UTC",
    server_now: new Date().toISOString(),
    classes: [
      {
        id: "c1",
        name: "CrossFit",
        class_type: "CrossFit",
        coach_name: "Nikos",
        scheduled_at: inMinutes(8),
        ends_at: inMinutes(68),
        duration_minutes: 60,
        cancelled: false,
        location_id: null,
        workout_id: "fran",
        bookings: { names: ["Maria", "Eleni", "Nikos"], count: 3, capacity: 14, unnamed: 0, waitlist: 0 },
      },
    ],
    workouts: [{ id: "fran", title: "Fran", type: "for_time", body: { kind: "free_text", text: "21-15-9 Thrusters, Pull-ups", document: null, timer: null, structured: false } }],
    leaderboards: [{ workout_id: "fran", score: null, entries: [{ name: "Eleni", rank: 1, value: "3:42", unit: null, scale_level_slug: "rx" }] }],
    focus: { view, source, slot_id: "c1", until: null },
  };
}

async function openTv(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "no session" }, 401)));
}

test.describe("Box screen on the TV", () => {
  test("pairs with a code, then follows the class; staff pins show at once", async ({ page }) => {
    await openTv(page);
    let paired: Record<string, unknown> | null = null;
    let view = "preview";
    await page.route("**/api/box-screen/pair", (route) => {
      paired = bodyOf(route.request());
      return route.fulfill(json({ token: "display-token", expires_at: inMinutes(90 * 1440), screen: { id: "s1", name: "Room 1" }, box: { id: "org-1", name: "Box Kypseli" } }, 201));
    });
    await page.route("**/api/box-screen/today", (route) => {
      expect(route.request().headers().authorization).toBe("Bearer display-token");
      return route.fulfill(json(today(view, view === "preview" ? "auto" : "staff")));
    });

    await page.goto("/tv");
    await expect(page.getByRole("heading", { name: "Connect this screen" })).toBeVisible();
    await page.getByTestId("tv-code").fill("acef 3467");
    await expect(page.getByTestId("tv-code")).toHaveValue("ACEF-3467");
    await page.getByTestId("tv-pair").click();

    await expect.poll(() => paired?.code).toBe("ACEF3467");
    await expect(page.getByTestId("tv-screen")).toHaveAttribute("data-scene", "preview");
    await expect(page.getByTestId("tv-bar-sub")).toContainText(/In (7|8)′/);
    await expect(page.getByTestId("tv-wod")).toContainText("Fran");
    await expect(page.getByTestId("tv-bookings")).toContainText("Maria");
    await expect(page.getByTestId("tv-bookings")).toContainText("11 spots left · book in the app");

    // Staff pin the leaderboard: the TV reads /today again (here after a reload; live it is the override push).
    view = "leaderboard";
    await page.reload();
    await expect(page.getByTestId("tv-screen")).toHaveAttribute("data-scene", "leaderboard");
    await expect(page.getByTestId("tv-leaderboard")).toContainText("Eleni");
  });

  test("a removed screen goes back to the pairing code", async ({ page }) => {
    await openTv(page);
    await page.addInitScript(() => {
      window.localStorage.setItem(
        "palee:box-screen",
        JSON.stringify({ token: "old-token", expires_at: "2999-01-01T00:00:00Z", screen: { id: "s1", name: "Room 1" }, box: { id: "org-1", name: "Box" } }),
      );
    });
    await page.route("**/api/box-screen/today", (route) => route.fulfill(json({ code: "invalid_screen_token", error: "Pair this screen again" }, 401)));

    await page.goto("/tv");
    await expect(page.getByTestId("tv-lost")).toBeVisible();
    await expect(page.getByTestId("tv-code")).toBeVisible();
  });
});

async function signIn(page: Page) {
  const user = {
    id: "user-1",
    nickname: "Olga",
    role: "member",
    email: "staff@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_settings: "all", manage_locations: "all", manage_schedule: "all", run_classes: "all" },
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  };

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "staff");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/box1/admin/locations", (route) =>
    route.fulfill(json({ locations: [{ id: "kyp", name: "Kypseli", address: null, archived_at: null }] })),
  );
}

const screenRow = (extra: Record<string, unknown> = {}) => ({
  id: "s1",
  name: "Room 1",
  location_id: "kyp",
  paired: true,
  paired_at: "2026-10-29T08:00:00Z",
  pairing_expires_at: null,
  last_seen_at: null,
  inserted_at: "2026-10-28T08:00:00Z",
  override: null,
  focus_changed: null,
  ...extra,
});

test.describe("Settings › Box screens", () => {
  test("adds a screen, shows its pairing code, pins a view and returns to automatic", async ({ page }) => {
    await signIn(page);
    let screens: Array<Record<string, unknown>> = [];
    let created: Record<string, unknown> | null = null;
    let pinned: Record<string, unknown> | null = null;
    let unpinned = false;

    await page.route("**/api/org/box1/admin/box-screens", (route) => {
      if (route.request().method() === "POST") {
        created = bodyOf(route.request());
        const screen = screenRow({ name: created.name, paired: false, paired_at: null, pairing_expires_at: inMinutes(15) });
        screens = [screen];
        return route.fulfill(json({ screen, pairing_code: { code: "ACEF-3467", expires_at: inMinutes(15) } }, 201));
      }
      return route.fulfill(json({ screens, max_screens: 20, override_views: ["wod", "timer", "leaderboard", "bookings", "class"] }));
    });
    await page.route("**/api/org/box1/admin/box-screens/s1/override", (route) => {
      if (route.request().method() === "PUT") {
        pinned = bodyOf(route.request());
        screens = [screenRow({ override: { view: pinned.view, slot_id: null, until: null }, focus_changed: { at: new Date().toISOString(), by: { id: "user-1", name: "Olga" } } })];
      } else {
        unpinned = true;
        screens = [screenRow()];
      }
      return route.fulfill(json({ screen: screens[0] }));
    });

    await page.goto("/admin/settings/box-screens");
    await expect(page.getByRole("heading", { name: "Box screens" })).toBeVisible();

    await page.getByTestId("box-screen-add").click();
    const add = page.getByTestId("box-screen-add-dialog");
    await add.getByTestId("box-screen-name").fill("Room 1");
    await add.getByTestId("box-screen-branch-kyp").check();
    await add.getByTestId("box-screen-create").click();
    await expect.poll(() => created).toEqual({ name: "Room 1", location_id: "kyp" });
    await expect(page.getByTestId("box-screen-code")).toHaveText("ACEF-3467");
    await page.getByTestId("box-screen-code-done").click();

    const card = page.getByTestId("box-screen-s1");
    await expect(card).toContainText("Waiting to pair");
    screens = [screenRow()];
    await expect(card).toContainText("Connected", { timeout: 15_000 });
    await expect(card.getByTestId("box-screen-focus")).toContainText("Shows: Automatic");

    await card.getByTestId("box-screen-choose").click();
    const choose = page.getByTestId("box-screen-choose-dialog");
    await choose.getByTestId("box-screen-view-leaderboard").check();
    await choose.getByTestId("box-screen-pin").click();
    await expect.poll(() => pinned).toEqual({ view: "leaderboard", slot_id: null, until: null });
    await expect(card.getByTestId("box-screen-focus")).toContainText("Pinned: Leaderboard");
    await expect(card.getByTestId("box-screen-focus")).toContainText("Changed by Olga");

    await card.getByTestId("box-screen-auto").click();
    await expect.poll(() => unpinned).toBe(true);
    await expect(card.getByTestId("box-screen-focus")).toContainText("Shows: Automatic");
  });
});
