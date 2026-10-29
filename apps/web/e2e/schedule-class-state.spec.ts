import { expect, test, type Page, type Request } from "./support/test";
import { chooseOption } from "./support/select";

// ADR-200 §2–3: staff pause, resume, cancel, restore and delete a class, for
// one class or across its series (optionally every nth class), and a paused
// or cancelled class shows it. The API is stubbed; every route not listed
// answers an empty object.

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

/** Edit stays in view; the other class actions sit behind ⋯ (restore and resume live in the state notice). */
async function chooseClassAction(page: Page, name: string) {
  await page.getByTestId("class-more-actions").click();
  await page.getByRole("menu", { name: "More actions for this class" }).getByRole("menuitem", { name, exact: true }).click();
}


const result = (overrides: Record<string, unknown> = {}) => ({
  action: "pause",
  slots: [],
  deleted_ids: [],
  changed_count: 1,
  skipped_count: 0,
  skipped_with_bookings: 0,
  released_count: 0,
  ...overrides,
});

async function withClass(page: Page, slot: Record<string, unknown>) {
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [slot] })),
  );
}

test.describe("Schedule › pause, cancel and delete classes", () => {
  test("pausing every 2nd upcoming class of the series", async ({ page }) => {
    await asOwner(page);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/state", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json(result({ changed_count: 4 })));
    });

    await openClass(page);
    await chooseClassAction(page, "Pause bookings");
    const dialog = page.getByRole("dialog", { name: "Pause bookings?" });
    await dialog.getByRole("radio", { name: "All upcoming classes" }).click();
    await chooseOption(page, dialog.getByRole("combobox", { name: "Which of them" }), "2");
    await dialog.getByRole("button", { name: "Pause", exact: true }).click();

    await expect.poll(() => sent?.action).toBe("pause");
    expect(sent).toMatchObject({ series_scope: "all", every: 2 });
    await expect(page.getByText("4 classes changed.")).toBeVisible();
  });

  test("cancelling one class sends the reason and says how many bookings were released", async ({ page }) => {
    await asOwner(page);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/state", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json(result({ action: "cancel", released_count: 3 })));
    });

    await openClass(page);
    await chooseClassAction(page, "Cancel class");
    const dialog = page.getByRole("dialog", { name: "Cancel this class?" });
    await expect(dialog.getByRole("radio", { name: "Only this class" })).toHaveAttribute("aria-checked", "true");
    await dialog.getByLabel("Reason (box members see it)").fill("Water leak");
    await dialog.getByRole("button", { name: "Cancel class" }).click();

    await expect.poll(() => sent?.action).toBe("cancel");
    expect(sent).toMatchObject({ series_scope: "this", reason: "Water leak" });
    expect(sent).not.toHaveProperty("every");
    await expect(page.getByText("3 bookings released.")).toBeVisible();
  });

  test("a multi-class delete says which classes were kept for their bookings", async ({ page }) => {
    await asOwner(page);
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/state", (route) =>
      route.fulfill(json(result({ action: "delete", changed_count: 5, skipped_count: 2, skipped_with_bookings: 2, deleted_ids: ["slot-1"] }))),
    );

    await openClass(page);
    await chooseClassAction(page, "Delete");
    const dialog = page.getByRole("dialog", { name: "Delete this class?" });
    await dialog.getByRole("radio", { name: "All upcoming classes" }).click();
    await dialog.getByRole("button", { name: "Delete", exact: true }).click();

    await expect(page.getByText("2 classes have bookings and were kept. Cancel them instead.")).toBeVisible();
    await expect(page.getByRole("dialog")).toHaveCount(0);
  });

  test("a cancelled class shows its reason and offers restore", async ({ page }) => {
    await asOwner(page);
    await withClass(page, { ...seriesClass, cancelled_at: new Date().toISOString(), cancel_reason: "Coach is ill" });

    await page.goto("/admin/schedule");
    await expect(page.getByTestId("class-state-badge").first()).toHaveText("Cancelled");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await expect(page.getByTestId("class-state-notice")).toHaveText("This class is cancelled: Coach is ill");
    // The way back sits in the notice, next to what it fixes; nothing to add to a calendar.
    await expect(page.getByTestId("class-state").getByRole("button", { name: "Restore class" })).toBeVisible();
    const actions = page.getByTestId("class-actions");
    await expect(actions.getByRole("button", { name: "Restore class" })).toHaveCount(0);
    await page.getByTestId("class-more-actions").click();
    const menu = page.getByRole("menu", { name: "More actions for this class" });
    await expect(menu.getByRole("menuitem", { name: "Delete", exact: true })).toBeVisible();
    await expect(menu.getByRole("menuitem", { name: "Pause bookings" })).toHaveCount(0);
    await expect(menu.getByRole("menuitem", { name: "Restore class" })).toHaveCount(0);
    await expect(menu.getByRole("menuitem", { name: "Add to calendar" })).toHaveCount(0);
    await page.keyboard.press("Escape");
    await page.getByTestId("class-state").getByRole("button", { name: "Restore class" }).click();
    await expect(page.getByRole("dialog", { name: "Restore this class?" })).toBeVisible();
  });

  test("a paused class offers resume", async ({ page }) => {
    await asOwner(page);
    await withClass(page, { ...seriesClass, class_series_id: null, paused_at: new Date().toISOString() });

    await openClass(page);
    await expect(page.getByTestId("class-state-notice")).toContainText("Booking for this class is paused.");
    await page.getByTestId("class-more-actions").click();
    await expect(page.getByRole("menu").getByRole("menuitem", { name: "Resume bookings" })).toHaveCount(0);
    await page.keyboard.press("Escape");
    await page.getByTestId("class-state").getByRole("button", { name: "Resume bookings" }).click();
    // Not in a series: no scope choice.
    const dialog = page.getByRole("dialog", { name: "Resume bookings?" });
    await expect(dialog.getByRole("radiogroup")).toHaveCount(0);
  });

  test("the class is named by itself and a class without its WOD shows a red card with two ways to add one", async ({ page }) => {
    await asOwner(page);
    await withClass(page, { ...seriesClass, class_series_id: null, published: false, workout_status: "missing" });

    await openClass(page);
    await expect(page.getByRole("dialog").getByRole("heading", { level: 2 })).toHaveText("Morning WOD");
    const notice = page.getByTestId("class-wod-notice");
    await expect(notice).toHaveAttribute("role", "alert");
    await expect(notice).toContainText("Not published: no WOD");
    await expect(notice).toContainText("Clients can't see or book this class until you add a WOD.");
    await expect(notice.getByRole("button", { name: "Choose a WOD" })).toBeVisible();
    await expect(notice.getByRole("button", { name: "+ New WOD" })).toBeVisible();
  });

  test("a series class without its WOD raises no warning and offers the same two buttons on the WOD card", async ({ page }) => {
    await asOwner(page);
    await withClass(page, { ...seriesClass, published: true, workout_status: "awaiting" });

    await openClass(page);
    await expect(page.getByTestId("class-wod-notice")).toHaveCount(0);
    await expect(page.getByRole("dialog").getByRole("alert")).toHaveCount(0);
    const add = page.getByTestId("class-wod-add");
    await expect(add.getByRole("button", { name: "Choose a WOD" })).toBeVisible();
    await expect(add.getByRole("button", { name: "+ New WOD" })).toBeVisible();
  });

  test("on a phone, the class and workout action rows stay inside the card", async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    await asOwner(page);

    await openClass(page);
    const actions = page.getByTestId("class-actions");
    await expect(actions.getByRole("button", { name: "Edit class" })).toBeVisible();
    await expect(actions.getByTestId("class-more-actions")).toBeVisible();

    // No action button sticks out of its card or breaks its label onto two lines.
    const problems = await page.getByRole("dialog").evaluate((dialog) =>
      Array.from(dialog.querySelectorAll<HTMLElement>("[data-testid=class-actions] button, [data-testid=workout-actions] button")).flatMap(
        (button) => {
          const box = button.getBoundingClientRect();
          const card = button.closest("section, [data-testid=class-actions]")!.getBoundingClientRect();
          const tops = new Set<number>();
          const texts = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
          for (let node = texts.nextNode(); node; node = texts.nextNode()) {
            const range = document.createRange();
            range.selectNodeContents(node);
            for (const rect of range.getClientRects()) tops.add(Math.round(rect.top));
          }
          const lines = tops.size;
          return box.left < card.left - 1 || box.right > card.right + 1 || lines > 1 ? [button.textContent!.trim()] : [];
        },
      ),
    );
    expect(problems).toEqual([]);
  });
});
