import { expect, test, type Page, type Request } from "./support/test";

// ADR-222: the class booking rules say what they do. A request for a class
// without automatic confirmation waits a set time (or until the class starts)
// for staff; late cancellation is entered as hours plus minutes and stored in
// minutes. The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

async function signIn(page: Page, role: string, capabilities: Record<string, string>) {
  const user = {
    id: "user-1",
    nickname: "Olga",
    role: "member",
    email: "staff@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role,
    roles: [role],
    capabilities,
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
    route.fulfill(json({ locations: [{ id: "loc-1", name: "Kifisia", address: null, archived_at: null }] })),
  );
}

const OWNER = { manage_settings: "all", manage_schedule: "all", run_classes: "all" };

const scheduling = {
  default_capacity: 12,
  default_auto_approve: false,
  default_booking_timeout_minutes: 60,
  default_booking_window_days: null,
  default_cancellation_cutoff_minutes: 720,
};

test.describe("Settings › class booking defaults", () => {
  test("every rule explains itself; late cancellation takes hours and minutes; requests may wait without a limit", async ({ page }) => {
    await signIn(page, "owner", OWNER);
    const sent: Array<Record<string, unknown>> = [];
    let current = { ...scheduling };
    await page.route("**/api/org/box1/admin/settings", (route) => {
      if (route.request().method() === "PATCH") {
        const body = bodyOf(route.request()) as { scheduling: Record<string, unknown> };
        sent.push(body.scheduling);
        current = { ...current, ...body.scheduling } as typeof current;
      }
      return route.fulfill(json({ notifications: { enabled: false }, gamification: {}, finance: {}, workouts: {}, scheduling: current }));
    });

    await page.goto("/admin/settings");
    const section = page.getByTestId("class-booking-defaults");
    await expect(section).toBeVisible();
    await expect(section.getByText("Time to answer a booking request")).toBeVisible();
    await expect(section.getByText(/If nobody on staff answers a request within this time/)).toBeVisible();
    await expect(section.getByText("Bookings open (days before the class)")).toBeVisible();
    await expect(section.getByText(/A member who cancels later than this still uses the visit/)).toBeVisible();

    // 720 stored minutes read as 12 hours 0 minutes.
    await expect(page.getByTestId("class-default-late-cancellation-hours")).toHaveValue("12");
    await expect(page.getByTestId("class-default-late-cancellation-minutes")).toHaveValue("0");
    await page.getByTestId("class-default-late-cancellation-hours").fill("1");
    await page.getByTestId("class-default-late-cancellation-minutes").fill("30");
    await page.getByTestId("class-default-late-cancellation-minutes").blur();

    await page.getByTestId("class-default-approval-wait-no-limit").check();
    await expect(page.getByTestId("class-default-approval-wait-hours")).toBeDisabled();

    await section.getByRole("button", { name: "Save" }).click();
    await expect.poll(() => sent.at(-1)).toMatchObject({
      default_booking_timeout_minutes: null,
      default_cancellation_cutoff_minutes: 90,
    });
  });
});

const startsAt = new Date(Date.now() + 2 * 86_400_000);
startsAt.setUTCMinutes(0, 0, 0);

const morningClass = {
  id: "slot-1",
  class_series_id: null,
  master_workout_id: null,
  name: "Morning WOD",
  duration_minutes: 60,
  scheduled_at: startsAt.toISOString(),
  class_type_id: "ct",
  class_type: { id: "ct", name: "CrossFit", slug: "crossfit" },
  capacity: 12,
  auto_approve: false,
  booking_timeout_minutes: 90,
  approved_booking_count: 0,
  spots_remaining: 12,
  workout: null,
  coach_user_id: null,
  location_id: null,
  space_id: null,
  space: null,
  bookings: [],
};

async function withSchedule(page: Page, slot: Record<string, unknown>) {
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [slot] })),
  );
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff: [] })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
}

test.describe("Schedule › how long a request waits", () => {
  test("the class popup says how long staff have to answer, not a booking deadline", async ({ page }) => {
    await signIn(page, "owner", OWNER);
    await withSchedule(page, morningClass);

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await expect(page.getByTestId("slot-approval-wait")).toHaveText("1 hour 30 minutes");
    await expect(page.getByText(/before start/)).toHaveCount(0);
  });

  test("the class editor lets a request wait until the class starts", async ({ page }) => {
    await signIn(page, "owner", OWNER);
    await withSchedule(page, morningClass);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json({ slot: { ...morningClass, booking_timeout_minutes: null }, updated_count: 1 }));
    });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("button", { name: "Edit slot" }).click();
    const dialog = page.getByRole("dialog", { name: "Edit scheduled class" });
    await expect(dialog.getByTestId("slot-approval-wait-hours")).toHaveValue("1");
    await expect(dialog.getByTestId("slot-approval-wait-minutes")).toHaveValue("30");
    await dialog.getByTestId("slot-approval-wait-no-limit").check();
    await dialog.getByRole("button", { name: "Save changes" }).click();

    await expect.poll(() => sent && "booking_timeout_minutes" in sent ? sent.booking_timeout_minutes : "unsent").toBeNull();
  });
});
