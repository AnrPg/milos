import { expect, test, type Page, type Request } from "./support/test";

// ADR-253 update 2026-10-29: «Στην οθόνη» on the class timer's remote. The
// class's coach pins its timer, leaderboard or WOD on a box screen and returns
// it to automatic, without the settings page. The API is stubbed; every route
// not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

async function signInAsCoach(page: Page) {
  const user = {
    id: "coach-1",
    nickname: "Nikos",
    role: "member",
    email: "coach@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "coach", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "coach",
    roles: ["coach"],
    capabilities: { run_classes: "all", manage_coaching: "own" },
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
  await page.route("**/api/org/box1/class-timers/c18", (route) =>
    route.fulfill(
      json({
        class: { id: "c18", name: "CrossFit 18:00", scheduled_at: new Date().toISOString(), duration_minutes: 60 },
        workout: { id: "fran", title: "Fran" },
        segments: [],
        timer: { status: "ready", current_segment_index: 0, segment_started_at_utc: null, paused_elapsed_ms: 0, duration_adjustments: {}, timer_preset: null, lock_version: 1 },
        server_now: new Date().toISOString(),
      }),
    ),
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

test.describe("Class timer remote › On screen", () => {
  test("the coach pins the class leaderboard on the room's screen and returns it to automatic", async ({ page }) => {
    await signInAsCoach(page);
    let screens = [screenRow()];
    let pinned: Record<string, unknown> | null = null;
    let unpinned = false;

    await page.route("**/api/org/box1/class-timers/c18/screens", (route) => route.fulfill(json({ screens, views: ["timer", "leaderboard", "wod"] })));
    await page.route("**/api/org/box1/class-timers/c18/screens/s1/override", (route) => {
      if (route.request().method() === "PUT") {
        const body = bodyOf(route.request());
        pinned = body;
        screens = [screenRow({ override: { view: body.view, slot_id: "c18", until: null }, focus_changed: { at: new Date().toISOString(), by: { id: "coach-1", name: "Nikos" } } })];
      } else {
        unpinned = true;
        screens = [screenRow()];
      }
      return route.fulfill(json({ screen: screens[0] }));
    });

    await page.goto("/class-timer/c18/control");
    await page.getByTestId("class-screen-open").click();
    const dialog = page.getByTestId("class-screen-dialog");
    await expect(dialog).toContainText("Show this class on a screen");
    const row = dialog.getByTestId("class-screen-s1");
    await expect(row.getByTestId("class-screen-shows")).toContainText("Automatic");

    await row.getByTestId("class-screen-view-leaderboard").click();
    await expect.poll(() => pinned).toEqual({ view: "leaderboard" });
    await expect(row.getByTestId("class-screen-shows")).toContainText("Pinned: Class leaderboard");

    await row.getByTestId("class-screen-auto").click();
    await expect.poll(() => unpinned).toBe(true);
    await expect(row.getByTestId("class-screen-shows")).toContainText("Automatic");
    await dialog.getByTestId("class-screen-done").click();
    await expect(dialog).toBeHidden();
  });

  test("a coach of another class sees no «On screen» action", async ({ page }) => {
    await signInAsCoach(page);
    await page.route("**/api/org/box1/class-timers/c18/screens", (route) => route.fulfill(json({ code: "forbidden", error: "Forbidden" }, 403)));

    await page.goto("/class-timer/c18/control");
    await expect(page.getByText("Fran").first()).toBeVisible();
    await expect(page.getByTestId("class-screen-open")).toHaveCount(0);
  });
});
