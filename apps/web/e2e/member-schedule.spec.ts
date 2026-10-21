import { expect, test, type Page } from "@playwright/test";

// Redesign Phase 2 M1: the member Πρόγραμμα is a day view with filter chips,
// a filter page and a location picker over a street map. The API is stubbed;
// every route not listed here answers an empty object.

const SHOTS = process.env.SCHEDULE_SCREENSHOTS_DIR;

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(
    JSON.stringify({
      sub: user.id,
      role: user.role,
      memberships: [{ organization_slug: "kypseli" }],
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

function at(hour: number, minute = 0, days = 0) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
}

function localDate(days = 0) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

const crossfit = { id: "ct-1", name: "CrossFit", kind: "class", level: "all_levels", audiences: [] };
const oly = { id: "ct-2", name: "Olympic lifting", kind: "class", level: "advanced", audiences: [] };
const openGym = { id: "ct-3", name: "Open gym", kind: "event", level: "all_levels", audiences: [] };

function slot(id: string, type: typeof crossfit, hour: number, extra: Record<string, unknown> = {}) {
  return {
    id,
    name: type.name,
    duration_minutes: 60,
    scheduled_at: at(hour),
    class_type_id: type.id,
    class_type: type,
    capacity: 12,
    auto_approve: true,
    booking_timeout_minutes: 30,
    approved_booking_count: 4,
    spots_remaining: 8,
    coach_user_id: "coach-1",
    location_id: "loc-1",
    covered_by_package: true,
    workout: null,
    current_user_booking: null,
    bookings: [],
    ...extra,
  };
}

const places = [
  {
    id: "loc-1",
    name: "Kypseli",
    address: "Fokionos Negri 12",
    city: "Athens",
    neighbourhood: "Kypseli",
    latitude: 37.999,
    longitude: 23.739,
    distance_km: 0.4,
    home: true,
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  },
  {
    id: "loc-2",
    name: "Pangrati",
    address: "Ymittou 40",
    city: "Athens",
    neighbourhood: "Pangrati",
    latitude: 37.968,
    longitude: 23.744,
    distance_km: 3.6,
    home: false,
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  },
];

async function stubApi(page: Page) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          home_location_id: "loc-1",
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
  await page.route("**/api/me/places**", (route) => route.fulfill(json({ places })));
  await page.route("**/api/me/filters/box_schedule", (route) =>
    route.fulfill(json({ surface: "box_schedule", last_used: null, saved: [] })),
  );
  await page.route("**/api/org/*/schedule?**", (route) =>
    route.fulfill(
      json({
        start_date: localDate(),
        end_date: localDate(13),
        days: 14,
        class_types: [crossfit, oly, openGym],
        coaches: [{ id: "coach-1", nickname: "Nikos", avatar_url: null }],
        slots: [
          slot("s-1", crossfit, 7, {
            cancel_free_until: at(1),
            waitlist_count: 0,
            workout: {
              id: "wod-1",
              title: "Fran",
              type: "for_time",
              authoring_mode: "structured",
              focus: ["strength", "legs"],
              sections: [
                {
                  id: "sec-1",
                  name: "Warm-up",
                  order: 1,
                  exercises: [
                    { id: "e-1", name: "Row", order: 1 },
                    { id: "e-2", name: "Air squat", order: 2 },
                  ],
                },
                {
                  id: "sec-2",
                  name: "Metcon",
                  order: 2,
                  exercises: [
                    { id: "e-3", name: "Thruster", order: 1 },
                    { id: "e-4", name: "Pull-up", order: 2 },
                  ],
                },
              ],
            },
          }),
          slot("s-2", oly, 9, {
            spots_remaining: 0,
            approved_booking_count: 12,
            friends_going: [
              { id: "friend-1", nickname: "Μαρία", avatar_url: null },
              { id: "friend-2", nickname: "Κώστας", avatar_url: null },
            ],
          }),
          slot("s-3", crossfit, 18, {
            current_user_booking: { id: "b-1", user_id: user.id, status: "approved", inserted_at: at(8) },
          }),
          slot("s-4", openGym, 20, { covered_by_package: false, duration_minutes: 90 }),
        ],
      }),
    ),
  );
}

async function shot(page: Page, name: string) {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${test.info().project.name}-${name}.png` });
}

test.describe("member schedule", () => {
  test.beforeEach(async ({ page, context, baseURL }) => {
    await stubApi(page);
    await context.addCookies([{ name: "milos_locale", value: "el", url: baseURL! }]);
    // Early morning, so every class of the day is still ahead.
    await page.clock.setFixedTime(new Date(at(6)));
  });

  test("lists the day's classes and filters them from the chips", async ({ page }) => {
    await page.goto("/box/schedule");
    await expect(page.getByRole("heading", { name: "Πρόγραμμα" })).toBeVisible();
    const list = page.getByRole("main");
    await expect(list.getByText("Olympic lifting")).toBeVisible();
    await expect(list.getByText("Εκτός πακέτου")).toBeVisible();
    await shot(page, "day");

    await page.getByRole("button", { name: "Στο πακέτο μου" }).click();
    await expect(list.getByText("Open gym")).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Φίλτρα (1)" })).toBeVisible();

    await page.getByRole("button", { name: "Καθαρισμός όλων των φίλτρων" }).click();
    await expect(list.getByText("Open gym")).toBeVisible();
  });

  test("«Φίλοι» keeps the classes people you follow are going to (ADR-142 decision 12)", async ({ page }) => {
    await page.goto("/box/schedule");
    const list = page.getByRole("main");
    await expect(list.getByText("Πάνε: Μαρία και 1 ακόμα")).toBeVisible();
    await page.getByRole("button", { name: "Φίλοι" }).click();
    await expect(list.getByText("Open gym")).toHaveCount(0);
    await expect(list.getByText("Olympic lifting")).toBeVisible();
    await list.getByRole("button", { name: /Olympic lifting/ }).click();
    await expect(page.getByRole("dialog", { name: "Olympic lifting" }).getByText("Μαρία, Κώστας")).toBeVisible();
  });

  test("opens the full filter page", async ({ page }) => {
    await page.goto("/box/schedule");
    await page.getByRole("button", { name: "Φίλτρα", exact: true }).click();
    const dialog = page.getByRole("dialog");
    await expect(dialog.getByText("Εστίαση προπόνησης")).toBeVisible();
    await shot(page, "filters");
    await dialog.getByRole("button", { name: "Προχωρημένοι" }).click();
    await dialog.getByRole("button", { name: /Δείξε 1/ }).click();
    await expect(page.getByRole("main").getByText("CrossFit")).toHaveCount(0);
  });

  test("switches to the month grid from the month name and back to a day", async ({ page }) => {
    await page.goto("/box/schedule");
    await page.getByRole("button", { name: /δείξε τον μήνα/ }).click();
    const grid = page.getByRole("grid", { name: "Μήνας" });
    await expect(grid.getByRole("gridcell", { name: /4 μαθήματα/ })).toBeVisible();
    await shot(page, "month");
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    await grid.getByRole("gridcell", { name: new RegExp(`^\\S+ ${tomorrow.getDate()} `) }).first().click();
    await expect(page.getByText("Δεν υπάρχουν μαθήματα")).toBeVisible();
  });

  test("opens a class as a sheet with its facts, the WOD names and Κράτηση at the bottom", async ({ page }) => {
    await page.goto("/box/schedule");
    await page.getByRole("main").getByRole("button", { name: /CrossFit/ }).first().click();
    const sheet = page.getByRole("dialog", { name: "CrossFit" });
    await expect(sheet.getByText("Thruster · Pull-up")).toBeVisible();
    await expect(sheet.getByText("Δύναμη · Πόδια")).toBeVisible();
    await expect(sheet.getByText(/Χωρίς χρέωση έως/)).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Κράτηση" })).toBeVisible();
    await shot(page, "class-sheet");
    await sheet.getByRole("button", { name: "Κλείσιμο ✕" }).click();
    await expect(sheet).toHaveCount(0);
  });

  test("picks a location from the list over the map", async ({ page }) => {
    await page.goto("/box/schedule/location");
    await expect(page.getByRole("heading", { name: "Τοποθεσία" })).toBeVisible();
    await expect(page.getByText("Όλες οι τοποθεσίες του Box Kypseli")).toBeVisible();
    await expect(page.getByText("Η βάση σου")).toBeVisible();
    await shot(page, "location");
  });
});
