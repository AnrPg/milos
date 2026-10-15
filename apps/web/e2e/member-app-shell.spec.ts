import { expect, test, type Page } from "@playwright/test";

// Redesign Phase 1 (ADR-137): the member app is four fixed tabs, and Box
// opens on today's workout. The API is stubbed; every route not listed here
// answers an empty object so unrelated widgets stay quiet.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete"],
  preferred_locale: "en",
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

function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

function localToday() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

async function stubMemberApi(page: Page) {
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
          organization: { id: "org-1", slug: "kypseli", name: "Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/threads/unread-count", (route) => route.fulfill(json({ unread_count: 0 })));
  await page.route("**/api/org/*/schedule?**", (route) =>
    route.fulfill(
      json({
        start_date: localToday(),
        end_date: localToday(),
        days: 7,
        class_types: [],
        slots: [
          {
            id: "slot-1",
            master_workout_id: "wod-1",
            name: "CrossFit",
            duration_minutes: 60,
            scheduled_at: todayAt(18),
            class_type_id: "ct-1",
            class_type: { id: "ct-1", name: "CrossFit" },
            capacity: 12,
            auto_approve: true,
            booking_timeout_minutes: 30,
            approved_booking_count: 4,
            spots_remaining: 8,
            workout: {
              id: "wod-1",
              title: "Fran",
              type: "for_time",
              authoring_mode: "free_text",
              free_text_body: "21-15-9\nThrusters 43/30 kg\nPull-ups",
              sections: [],
            },
            current_user_booking: { id: "booking-1", user_id: user.id, status: "approved", inserted_at: todayAt(8) },
            bookings: [],
          },
        ],
      }),
    ),
  );
  await page.route("**/api/org/*/my-workouts**", (route) =>
    route.fulfill(
      json({
        start_date: localToday(),
        end_date: localToday(),
        assignments: [
          {
            id: "assignment-1",
            master_workout_id: "strength-a",
            scheduled_for: localToday(),
            workout: { id: "strength-a", title: "Strength A", type: "strength", sections: [] },
          },
        ],
      }),
    ),
  );
  await page.route("**/api/org/*/executions", (route) => route.fulfill(json({ executions: [] })));
  await page.route("**/api/org/*/me/training-log/sources", (route) =>
    route.fulfill(json({ classes: [], assignments: [], library_workouts: [] })),
  );
  await page.route("**/api/org/*/me/workouts/*/injury-warnings**", (route) =>
    route.fulfill(json({ level: "none", warnings: [], warning_count: 0 })),
  );
  await page.route("**/api/org/*/me/entitlement", (route) =>
    route.fulfill(
      json({
        entitlement: {
          status: "active",
          enforcement_mode: "enforce",
          plan: { entitlement_version: 1, channels: [], capabilities: ["watch_on_demand", "request_form_reviews"] },
          allowances: {},
        },
      }),
    ),
  );
}

test.describe("member app shell", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("Box opens on today's class WOD, with the coach programme as a second source", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/box");

    const tabs = page.getByRole("navigation", { name: "Main sections" });
    await expect(tabs.getByRole("link")).toHaveText(["Home", "Box", "Journal", "Me"]);
    await expect(tabs.getByRole("link", { name: "Box" })).toHaveAttribute("aria-current", "page");

    await expect(page.getByRole("heading", { name: "Box Kypseli" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    await expect(page.getByRole("tab", { name: /Strength A/ })).toBeVisible();
    await expect(page.getByRole("button", { name: /Start/ })).toBeEnabled();
    await expect(page.getByRole("link", { name: "Videos" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Coach" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Appointments" })).toHaveCount(0);
    await page.screenshot({ path: "test-results/member-app/box.png", fullPage: true });

    await page.getByRole("tab", { name: /Strength A/ }).click();
    await expect(page.getByRole("heading", { name: "Strength A" })).toBeVisible();
  });

  test("Journal's one write action lists the entry kinds that exist", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/journal");

    await expect(page.getByRole("heading", { name: "Journal", exact: true })).toBeVisible();
    await page.getByRole("button", { name: "New entry" }).click();
    const sheet = page.getByRole("dialog", { name: "New entry" });
    await expect(sheet.getByRole("button")).toContainText(["Workout", "PR", "Injury", "Technique video", "Review", "Cancel"]);
    await page.screenshot({ path: "test-results/member-app/journal-new-entry.png" });
  });

  test("Me holds every secondary link, and old URLs land on the new pages", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/me");
    await expect(page.getByRole("main").getByText("Maria L")).toBeVisible();
    await expect(page.getByRole("link", { name: /Payments & receipts/ })).toHaveAttribute("href", "/me/payments");
    await page.screenshot({ path: "test-results/member-app/me.png", fullPage: true });

    await page.goto("/profile");
    await expect(page).toHaveURL(/\/me\/settings$/);
  });
});
