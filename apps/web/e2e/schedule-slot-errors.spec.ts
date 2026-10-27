import { expect, test, type Page, type Request } from "./support/test";

// ADR-214: the class form never proposes a start that has passed, and what
// the API refuses shows inside the form, on the field it concerns. The box
// runs on Athens time; the clock is pinned at 2026-10-27 21:33 UTC (23:33 in
// Athens), the evening the 422 was reported.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");
const NOW = new Date("2026-10-27T21:33:00Z");

async function asBoxAdmin(page: Page) {
  const user = {
    id: "admin-1",
    nickname: "Alex",
    role: "member",
    email: "admin@example.com",
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "admin", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(NOW.getTime() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "admin",
    roles: ["admin"],
    capabilities: { manage_schedule: "all" },
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "Europe/Athens" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  };

  await page.clock.setFixedTime(NOW);
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
    route.fulfill(json({ class_types: [{ id: "ct", name: "Hybrid beginners", archived_at: null }], locations: [], coaches: [], slots: [] })),
  );
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff: [] })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
}

test.describe("Schedule › class form errors", () => {
  test("a class added late in the evening starts at the next open half hour, not at 09:00 that has passed", async ({ page }) => {
    await asBoxAdmin(page);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json({ id: "slot-1", ...sent, master_workout_id: null, class_series_id: null }, 201));
    });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: "+ Slot" }).first().click();
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await dialog.getByRole("button", { name: "Create slot" }).click();

    // 00:00 on the 28th in Athens.
    await expect.poll(() => sent?.scheduled_at).toBe("2026-10-27T22:00:00.000Z");
  });

  test("the API's reason shows inside the form, on the field, and nowhere on the page behind it", async ({ page }) => {
    await asBoxAdmin(page);
    await page.route("**/api/org/box1/admin/schedule/slots", (route) =>
      route.fulfill(json({ code: "validation_failed", errors: { capacity: ["must be greater than 0"] } }, 422)),
    );

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: "+ Slot" }).first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: "Create slot" }).click();

    const capacity = dialog.getByRole("spinbutton", { name: "Capacity" });
    await expect(capacity).toHaveAttribute("aria-invalid", "true");
    await expect(dialog.getByText("Enter a number above 0.")).toBeVisible();
    await expect(dialog.getByRole("alert").filter({ hasText: "Look for the fields marked in red." })).toBeVisible();
    // The schedule page behind the form shows no error of its own.
    await expect(page.locator("main").getByText("Look for the fields marked in red.")).toHaveCount(0);
    await expect(page.getByText("Check the highlighted values")).toHaveCount(0);

    // Changing the value clears the mark at once.
    await capacity.fill("10");
    await capacity.blur();
    await expect(capacity).not.toHaveAttribute("aria-invalid", "true");
  });

  test("past days offer no + Slot, since a class cannot start in the past", async ({ page }) => {
    await asBoxAdmin(page);

    await page.goto("/admin/schedule");
    await expect(page.getByRole("button", { name: "+ Slot" }).first()).toBeVisible();
    await page.getByRole("button", { name: "Prev" }).click();
    await expect(page.getByRole("button", { name: "Today" })).toBeVisible();
    await expect(page.getByRole("button", { name: "+ Slot" })).toHaveCount(0);
  });
});
