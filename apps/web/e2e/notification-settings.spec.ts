import { expect, test, type Page } from "./support/test";

// ADR-199: Εγώ › Ρυθμίσεις › Ειδοποιήσεις. One row per category with a
// switch per channel, account and payments locked on, the staff row only for
// staff, and a bell notification that opens a section of Settings. The API
// is stubbed.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

const CATEGORIES = ["bookings", "messages", "community", "coach", "partners", "journal", "staff", "account"] as const;

type Row = { category: string; locked: boolean; audience: string; channels: { in_app: boolean; push: boolean } };

async function stub(page: Page, { staff = false, notifications = [] as unknown[] } = {}) {
  const rows: Row[] = CATEGORIES.map((category) => ({
    category,
    locked: category === "account",
    audience: category === "staff" ? "staff" : "everyone",
    channels: { in_app: true, push: true },
  }));
  const updates: { category: string; body: Record<string, boolean> }[] = [];
  const role = staff ? "coach" : "member";

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role, roles: [role], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) =>
    route.fulfill(json({ notifications, next_cursor: null, unread_count: notifications.length })),
  );
  // The bell's badge reads the count alone; the list loads when the panel opens.
  await page.route("**/api/notifications/unread-count", (route) => route.fulfill(json({ unread_count: notifications.length })));
  await page.route("**/api/notifications/preferences", (route) => route.fulfill(json({ preferences: rows })));
  await page.route("**/api/notifications/preferences/*", (route) => {
    const category = route.request().url().split("/").pop()!;
    const body = route.request().postDataJSON() as Record<string, boolean>;
    updates.push({ category, body });
    const row = rows.find((r) => r.category === category)!;
    row.channels = { ...row.channels, ...body };
    if (!row.channels.in_app) row.channels.push = false;
    return route.fulfill(json({ preferences: rows }));
  });
  return updates;
}

test.describe("notification settings", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("a member switches categories per channel; account stays locked, staff row hidden", async ({ page }) => {
    const updates = await stub(page);
    await page.goto("/me/settings#notifications");

    const section = page.locator("section#notifications");
    await expect(section.getByText("Notifications", { exact: true })).toBeVisible();
    const list = section.getByTestId("notification-categories");
    await expect(list.locator("[data-category]")).toHaveCount(7);
    await expect(list.locator('[data-category="staff"]')).toHaveCount(0);
    await expect(list.locator('[data-category="account"]')).toContainText("Always on");
    await expect(list.locator('[data-category="account"]').getByRole("switch")).toHaveCount(0);
    await expect(list.locator('[data-category="community"]').getByRole("link", { name: /Per club/ })).toHaveAttribute("href", "/me/clubs");

    const communityPush = list.getByRole("switch", { name: "Clubs & community · Push" });
    await expect(communityPush).toHaveAttribute("aria-checked", "true");
    await communityPush.click();
    await expect(communityPush).toHaveAttribute("aria-checked", "false");
    expect(updates).toContainEqual({ category: "community", body: { push: false } });

    // Push is made from the bell's notification: with the bell off, push is off and locked.
    await list.getByRole("switch", { name: "Journal reminders · In app" }).click();
    const journalPush = list.getByRole("switch", { name: "Journal reminders · Push" });
    await expect(journalPush).toHaveAttribute("aria-checked", "false");
    await expect(journalPush).toBeDisabled();
    expect(updates).toContainEqual({ category: "journal", body: { in_app: false } });

    // No horizontal scroll at phone width.
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("staff also see the box-operations row", async ({ page }) => {
    await stub(page, { staff: true });
    await page.goto("/me/settings#notifications");
    await expect(page.locator('section#notifications [data-category="staff"]')).toContainText("Running the box");
  });

  test("a bell notification opens its section of Settings", async ({ page }) => {
    await stub(page, {
      notifications: [
        {
          id: "n-1",
          user_id: user.id,
          organization_id: null,
          type: "password_reset_completed",
          payload: { url: "/me/settings#security" },
          read_at: null,
          inserted_at: new Date().toISOString(),
        },
      ],
    });
    await page.goto("/me/settings");
    await page.getByTestId("member-top-bar").getByRole("button", { name: "1 unread notification" }).click();
    await page.getByText("Your password was reset").click();

    await expect(page).toHaveURL(/\/me\/settings#security$/);
    await expect(page.getByRole("button", { name: "Sign out all devices" })).toBeVisible();
  });
});
