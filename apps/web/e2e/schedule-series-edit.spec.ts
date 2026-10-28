import { expect, test, type Page, type Request } from "./support/test";
import { chooseDate } from "./support/select";

// ADR-200: a class can be duplicated, and an edit to a class of a series goes
// to this class only, every upcoming class, or the classes between two dates.
// The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const staff = [{ user_id: "owner-1", nickname: "Olga", role: "owner", roles: ["owner", "coach"] }];

// In two hours: inside today's window in any zone except right before midnight.
const startsAt = new Date(Date.now() + 2 * 3600_000);
startsAt.setUTCMinutes(0, 0, 0);

const seriesClass = {
  id: "slot-1",
  class_series_id: "series-1",
  master_workout_id: null,
  name: "Morning WOD",
  duration_minutes: 60,
  scheduled_at: startsAt.toISOString(),
  class_type_id: "ct",
  class_type: { id: "ct", name: "CrossFit", slug: "crossfit" },
  capacity: 12,
  auto_approve: true,
  booking_timeout_minutes: 30,
  approved_booking_count: 0,
  spots_remaining: 12,
  workout: null,
  coach_user_id: null,
  location_id: null,
  bookings: [],
};

async function asOwner(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Olga",
    role: "member",
    email: "owner@example.com",
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
    roles: ["owner", "coach"],
    capabilities: { manage_schedule: "all", run_classes: "all" },
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
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [seriesClass] })),
  );
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
}

async function openClass(page: Page) {
  await page.goto("/admin/schedule");
  await page.getByRole("button", { name: /CrossFit/ }).first().click();
}

test.describe("Schedule › duplicate and series edits", () => {
  test("an edit can go to every upcoming class of the series", async ({ page }) => {
    await asOwner(page);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json({ slot: { ...seriesClass, capacity: 16 }, updated_count: 8 }));
    });

    await openClass(page);
    await page.getByRole("button", { name: "Edit slot" }).click();
    const dialog = page.getByRole("dialog", { name: "Edit scheduled class" });
    const scope = dialog.getByRole("radiogroup", { name: "Apply changes to" });
    await expect(scope.getByRole("radio", { name: "Only this class" })).toHaveAttribute("aria-checked", "true");

    await scope.getByRole("radio", { name: "All upcoming classes" }).click();
    await expect(dialog).toContainText("Each keeps its own date and WOD.");
    await dialog.getByRole("button", { name: "Save changes" }).click();

    await expect.poll(() => sent?.series_scope).toBe("all");
    expect(sent).not.toHaveProperty("range_from");
    await expect(page.getByText("8 classes updated.")).toBeVisible();
  });

  test("an edit can go to the classes between two dates", async ({ page }) => {
    await asOwner(page);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json({ slot: seriesClass, updated_count: 3 }));
    });
    const until = new Date(startsAt.getTime() + 14 * 86_400_000).toISOString().slice(0, 10);

    await openClass(page);
    await page.getByRole("button", { name: "Edit slot" }).click();
    const dialog = page.getByRole("dialog", { name: "Edit scheduled class" });
    await dialog.getByRole("radio", { name: "Classes between dates" }).click();
    const to = dialog.getByRole("button", { name: "To", exact: true });
    await chooseDate(page, to, until);
    await dialog.getByRole("button", { name: "Save changes" }).click();

    await expect.poll(() => sent?.series_scope).toBe("range");
    const body = sent as Record<string, unknown> | null;
    expect(body?.range_to).toBe(until);
    expect(typeof body?.range_from).toBe("string");
  });

  test("a class that is not in a series has no scope choice", async ({ page }) => {
    await asOwner(page);
    await page.route("**/api/org/box1/schedule?**", (route) =>
      route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [{ ...seriesClass, class_series_id: null }] })),
    );

    await openClass(page);
    await page.getByRole("button", { name: "Edit slot" }).click();
    await expect(page.getByRole("dialog", { name: "Edit scheduled class" })).toBeVisible();
    await expect(page.getByRole("radiogroup", { name: "Apply changes to" })).toHaveCount(0);
  });

  test("duplicating a class opens a new class with its settings", async ({ page }) => {
    await asOwner(page);
    let created: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots", (route) => {
      created = bodyOf(route.request());
      return route.fulfill(json({ slot: { ...seriesClass, id: "slot-2", class_series_id: null }, slots: [] }, 201));
    });

    await openClass(page);
    await page.getByTestId("class-more-actions").click();
    await page.getByRole("menuitem", { name: "Duplicate" }).click();
    const dialog = page.getByRole("dialog", { name: "Create scheduled class" });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole("radiogroup", { name: "Apply changes to" })).toHaveCount(0);
    await dialog.getByRole("button", { name: "Create slot" }).click();

    await expect.poll(() => created?.name).toBe("Morning WOD");
    expect(created).toMatchObject({ capacity: 12, duration_minutes: 60, class_type_id: "ct" });
    expect(created).not.toHaveProperty("class_series_id");
  });
});
