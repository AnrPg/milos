import { expect, test, type Page, type Request } from "./support/test";
import { chooseOption } from "./support/select";

// ADR-201: from the class popup, staff give several attendees their own
// version of the class at once. Each person is programmed as if alone; the
// outcome says who got it and why the others did not. The API is stubbed;
// every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const staff = [{ user_id: "owner-1", nickname: "Olga", role: "owner", roles: ["owner", "coach"] }];

// In two hours: inside today's window in any zone except right before midnight.
const startsAt = new Date(Date.now() + 2 * 3600_000);
startsAt.setUTCMinutes(0, 0, 0);

const booking = (id: string, userId: string, nickname: string, status: string, extra: Record<string, unknown> = {}) => ({
  id,
  user_id: userId,
  user_nickname: nickname,
  status,
  inserted_at: new Date().toISOString(),
  ...extra,
});

const bookedClass = {
  id: "slot-1",
  class_series_id: null,
  master_workout_id: null,
  name: "Morning WOD",
  duration_minutes: 60,
  scheduled_at: startsAt.toISOString(),
  class_type_id: "ct",
  class_type: { id: "ct", name: "CrossFit", slug: "crossfit" },
  capacity: 12,
  auto_approve: true,
  booking_timeout_minutes: 30,
  approved_booking_count: 3,
  spots_remaining: 9,
  workout: null,
  coach_user_id: null,
  location_id: null,
  bookings: [
    booking("b-1", "u-anna", "Anna", "approved"),
    booking("b-2", "u-zoe", "Zoe", "pending"),
    booking("b-3", "u-babis", "Babis", "approved"),
    booking("b-4", "u-anna", "Anna", "approved", { guest_name: "Anna's friend" }),
    booking("b-5", "u-carl", "Carl", "cancelled"),
  ],
  member_versions: [
    { assignment_id: "a-1", user_id: "u-babis", user_nickname: "Babis", master_workout_id: "w-old", workout_title: "Old" },
  ],
};

async function asOwner(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Olga",
    role: "member",
    email: "owner@example.com",
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
    capabilities: { manage_schedule: "all", run_classes: "all", manage_coaching: "all" },
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
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [bookedClass] })),
  );
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
  await page.route("**/api/org/box1/admin/workouts", (route) =>
    route.fulfill(
      json({
        workouts: [
          { id: "w-scaled", title: "Scaled Fran", status: "published" },
          { id: "w-draft", title: "Draft idea", status: "draft" },
        ],
      }),
    ),
  );
}

test.describe("Schedule › variation for several people", () => {
  test("staff pick attendees and a WOD; each gets their own version and the outcome is shown", async ({ page }) => {
    await asOwner(page);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/users/programming", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(
        json({
          results: [
            { user_id: "u-anna", status: "ok", mode: "class_variant", workout: { id: "copy-1" }, association: { id: "as-1" } },
            {
              user_id: "u-zoe",
              status: "error",
              code: "member_programming_not_entitled",
              params: { user_id: "u-zoe", nickname: "Zoe", reason: "finance_channel_not_included" },
            },
          ],
        }),
      );
    });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("button", { name: "Variation for…" }).click();

    const dialog = page.getByRole("dialog", { name: "Variation for several people" });
    await expect(dialog).toBeVisible();

    // Attendees once each, guests and cancelled bookings left out.
    const people = dialog.getByRole("checkbox");
    await expect(people).toHaveCount(3);
    await expect(dialog.getByText("Carl")).toHaveCount(0);
    await expect(dialog.getByText("Already has a version")).toBeVisible();

    // The class has no WOD yet, so one must be chosen first.
    const submit = dialog.getByRole("button", { name: /Create for selected/ });
    await dialog.getByRole("checkbox", { name: /Anna/ }).check();
    await dialog.getByRole("checkbox", { name: /Zoe/ }).check();
    await expect(submit).toHaveText("Create for selected (2)");
    await expect(submit).toBeDisabled();

    await chooseOption(page, dialog.getByRole("combobox", { name: /Start from/ }), "w-scaled");
    await expect(page.locator('[role="option"][data-value="w-draft"]')).toHaveCount(0);
    await submit.click();

    await expect.poll(() => sent?.mode).toBe("class_variant");
    expect(sent).toMatchObject({
      user_ids: ["u-anna", "u-zoe"],
      master_workout_id: "w-scaled",
      slot_id: "slot-1",
      scheduled_for: startsAt.toISOString().slice(0, 10),
      copy_source: true,
    });

    const outcome = dialog.getByTestId("group-outcome");
    await expect(outcome).toContainText("Done for 1 of 2.");
    await expect(outcome.locator('[data-outcome="ok"]')).toContainText("Anna");
    await expect(outcome.locator('[data-outcome="error"]')).toContainText("Zoe's package does not include personal programming");
  });

  test("select all picks every attendee", async ({ page }) => {
    await asOwner(page);
    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("button", { name: "Variation for…" }).click();

    const dialog = page.getByRole("dialog", { name: "Variation for several people" });
    await dialog.getByRole("button", { name: "Select all" }).click();
    await expect(dialog.getByRole("button", { name: /Create for selected/ })).toHaveText("Create for selected (3)");
    await dialog.getByRole("button", { name: "Clear" }).click();
    await expect(dialog.getByRole("button", { name: /Create for selected/ })).toHaveText("Create for selected (0)");
  });
});
