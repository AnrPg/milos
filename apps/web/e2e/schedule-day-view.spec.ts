import { expect, test, type Page } from "./support/test";

// In the month view, a date or its "+N more" opens that day's view: only
// that day's classes, in full. The API is stubbed; every route not listed
// answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const staff = [{ user_id: "owner-1", nickname: "Olga", role: "owner", roles: ["owner", "coach"] }];

// The 14th and 15th of this month, on the gym's (UTC) clock.
const now = new Date();
const isoDay = (day: number) =>
  `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
const busyDay = isoDay(14);
const nextDay = isoDay(15);
// The label CalendarView gives a date (its local noon, so any zone agrees).
const dayLabel = (iso: string) => {
  const [year, month, day] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("en", { weekday: "long", month: "short", day: "numeric" }).format(new Date(year, month - 1, day, 12));
};

const slot = (id: string, at: string, typeName: string, title: string) => ({
  id,
  class_series_id: null,
  master_workout_id: null,
  name: title,
  duration_minutes: 60,
  scheduled_at: at,
  class_type_id: typeName.toLowerCase(),
  class_type: { id: typeName.toLowerCase(), name: typeName, slug: typeName.toLowerCase() },
  capacity: 12,
  auto_approve: true,
  booking_timeout_minutes: 30,
  approved_booking_count: 0,
  spots_remaining: 12,
  workout: { id: `w-${id}`, title },
  coach_user_id: null,
  location_id: null,
  bookings: [],
});

const slots = [
  ...["06", "08", "10", "17", "19"].map((hour, index) => slot(`s${index}`, `${busyDay}T${hour}:00:00.000Z`, "CrossFit", `WOD ${index + 1}`)),
  slot("yoga", `${nextDay}T09:00:00.000Z`, "Yoga", "Stretch"),
];

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
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
}

async function stubSchedule(page: Page, requests: URL[]) {
  await page.route("**/api/org/box1/schedule?**", (route) => {
    const url = new URL(route.request().url());
    requests.push(url);
    const from = url.searchParams.get("start_at") ?? "";
    const to = url.searchParams.get("end_at") ?? "\uffff";
    const inWindow = slots.filter((item) => item.scheduled_at >= from && item.scheduled_at < to);
    return route.fulfill(
      json({
        class_types: [
          { id: "crossfit", name: "CrossFit", archived_at: null },
          { id: "yoga", name: "Yoga", archived_at: null },
        ],
        locations: [],
        coaches: [],
        slots: inWindow,
      }),
    );
  });
}

test.describe("Schedule › day view from the month", () => {
  test("'+N more' opens that day with every class of it, and the month is one tap away", async ({ page }) => {
    await asOwner(page);
    const requests: URL[] = [];
    await stubSchedule(page, requests);

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: "Month view" }).click();

    const moreButton = page.getByRole("button", { name: `Day view: ${dayLabel(busyDay)}` }).filter({ hasText: "+2" });
    await expect(moreButton).toBeVisible();
    await moreButton.click();

    await expect(page.getByRole("button", { name: "Day view", exact: true })).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("heading", { name: dayLabel(busyDay) })).toBeVisible();
    for (let index = 1; index <= 5; index += 1) {
      await expect(page.getByText(`WOD ${index}`, { exact: true })).toBeVisible();
    }
    await expect(page.getByText("Stretch")).toHaveCount(0);
    await expect.poll(() => requests.at(-1)?.searchParams.get("days")).toBe("1");
    expect(requests.at(-1)?.searchParams.get("start_at")).toBe(`${busyDay}T00:00:00.000Z`);
    expect(requests.at(-1)?.searchParams.get("end_at")).toBe(`${nextDay}T00:00:00.000Z`);

    // "Next" moves one day at a time.
    await page.getByRole("button", { name: "Next", exact: true }).click();
    await expect(page.getByRole("heading", { name: dayLabel(nextDay) })).toBeVisible();
    await expect(page.getByText("Stretch")).toBeVisible();

    await page.getByRole("button", { name: "Month view" }).click();
    await expect(page.getByRole("button", { name: `Day view: ${dayLabel(busyDay)}` }).first()).toBeVisible();
  });

  test("tapping a date in the month opens that day", async ({ page }) => {
    await asOwner(page);
    await stubSchedule(page, []);

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: "Month view" }).click();
    await page.getByRole("button", { name: `Day view: ${dayLabel(nextDay)}` }).filter({ hasText: /^15$/ }).click();

    await expect(page.getByRole("heading", { name: dayLabel(nextDay) })).toBeVisible();
    await expect(page.getByText("Stretch")).toBeVisible();
    await expect(page.getByText("WOD 1", { exact: true })).toHaveCount(0);
  });
});
