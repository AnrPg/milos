import { expect, test, type Page } from "./support/test";

// The gym owner's setup checklist: every step opens its page, also from
// "My training", and the popup comes back at each login until setup is done.
// The API is stubbed.

const user = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: [],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const STEPS = ["settings", "classes", "packages", "workout", "page", "invite", "tour"];
const checklist = {
  audience: "gym",
  steps: STEPS.map((id) => ({ id, done: false, auto: false, skipped: false })),
  completed_count: 0,
  total: STEPS.length,
  finished: false,
  dismissed: false,
  tour_completed: false,
};

async function stubApi(page: Page, roles: string[] = ["owner"]) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles,
          capabilities: { manage_settings: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/settings", (route) => route.fulfill(json({ notifications: { enabled: false }, gamification: null, finance: null, scheduling: null })));
  await page.route("**/api/org/*/admin/onboarding", (route) => route.fulfill(json(checklist)));
}

async function openChecklist(page: Page, start: string) {
  await page.goto(start);
  const dialog = page.getByRole("dialog", { name: "Welcome! Let’s get your box ready" });
  await expect(dialog).toBeVisible();
  return dialog;
}

test.describe("admin setup checklist", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
  });

  test("every step links to a page under the gym", async ({ page }) => {
    await stubApi(page);
    const dialog = await openChecklist(page, "/org/kypseli/admin");
    const expected: Record<string, string> = {
      "Open settings": "/org/kypseli/admin/settings",
      "Set up classes": "/org/kypseli/admin/class-schedule",
      "Create a package": "/org/kypseli/admin/finance?tab=packages",
      "Write a workout": "/org/kypseli/admin/workouts/new",
      // ADR-221: until the page is published nobody finds the box.
      "Open the public page": "/org/kypseli/admin/public-page",
    };
    for (const [name, href] of Object.entries(expected)) {
      await expect(dialog.getByRole("link", { name })).toHaveAttribute("href", href);
    }
    await expect(dialog.getByRole("button", { name: "Don’t show again" })).toHaveCount(0);

    await dialog.getByRole("link", { name: "Open settings" }).click();
    await expect(page).toHaveURL(/\/org\/kypseli\/admin\/settings$/);
    await expect(dialog).toBeHidden();
  });

  test("open settings works from My training", async ({ page }) => {
    await stubApi(page, ["owner", "member"]);
    await page.route("**/api/me/clubs", (route) => route.fulfill(json([])));
    await page.addInitScript(() => {
      if (!window.sessionStorage.getItem("seeded")) {
        window.sessionStorage.setItem("seeded", "1");
        window.localStorage.setItem("palee.view", "client");
      }
    });
    const dialog = await openChecklist(page, "/me/clubs");
    await dialog.getByRole("link", { name: "Open settings" }).click();
    await expect(page).toHaveURL(/\/org\/kypseli\/admin\/settings$/);
    await page.waitForTimeout(1500);
    await expect(page).toHaveURL(/\/org\/kypseli\/admin\/settings$/);
    expect(await page.evaluate(() => window.localStorage.getItem("palee.view"))).toBe("staff");
  });

  test("the settings checklist starts collapsed and stands out until setup is done", async ({ page }) => {
    await stubApi(page);
    const dialog = await openChecklist(page, "/org/kypseli/admin");
    await dialog.getByRole("link", { name: "Open settings" }).click();
    await expect(page).toHaveURL(/\/org\/kypseli\/admin\/settings$/);

    // Collapsed, so the settings themselves are what the owner lands on.
    const panel = page.locator("#setup-checklist");
    await expect(panel).toBeVisible();
    await expect(panel).toHaveAttribute("data-pending", "true");
    await expect(panel).toContainText("0 of 7 done");
    await expect(panel.getByRole("link", { name: "Set up classes" })).toHaveCount(0);
    const toggle = panel.getByRole("button", { name: "Show steps" });
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    const box = await panel.boundingBox();
    expect(box!.height).toBeLessThan(page.viewportSize()!.height / 2);

    await toggle.click();
    await expect(panel.getByRole("link", { name: "Set up classes" })).toBeVisible();
    await expect(panel.getByRole("button", { name: "Hide steps" })).toHaveAttribute("aria-expanded", "true");
  });

  test("«Open settings» while on Settings folds the steps and shows the settings", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await stubApi(page);
    const popup = await openChecklist(page, "/org/kypseli/admin/settings");
    await popup.getByRole("button", { name: "Remind me later" }).click();
    await expect(popup).toBeHidden();

    const panel = page.locator("#setup-checklist");
    await panel.getByRole("button", { name: "Show steps" }).click();
    await expect(panel.getByRole("link", { name: "Set up classes" })).toBeVisible();

    await panel.getByRole("link", { name: "Open settings" }).click();
    await expect(page).toHaveURL(/\/org\/kypseli\/admin\/settings$/);
    await expect(panel.getByRole("button", { name: "Show steps" })).toHaveAttribute("aria-expanded", "false");
    await expect(panel.getByRole("link", { name: "Set up classes" })).toHaveCount(0);
    // The phone now shows the settings below the checklist, not its steps.
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);
    const next = page.locator("#setup-checklist + *");
    await expect(next).toBeInViewport();
    const top = await next.evaluate((element) => element.getBoundingClientRect().top);
    expect(Math.abs(top)).toBeLessThan(5);
  });

  test("a finished checklist stays collapsed without the highlight", async ({ page }) => {
    await stubApi(page);
    await page.route("**/api/org/*/admin/onboarding", (route) =>
      route.fulfill(
        json({
          ...checklist,
          steps: STEPS.map((id) => ({ id, done: true, auto: false, skipped: false })),
          completed_count: STEPS.length,
          finished: true,
          tour_completed: true,
        }),
      ),
    );
    await page.goto("/org/kypseli/admin/settings");
    const panel = page.locator("#setup-checklist");
    await expect(panel).toBeVisible();
    await expect(panel).not.toHaveAttribute("data-pending", "true");
    await expect(panel.getByRole("button", { name: "Show steps" })).toBeVisible();
  });

  test("remind me later lasts until the next login", async ({ page }) => {
    await stubApi(page);
    const dialog = await openChecklist(page, "/org/kypseli/admin");
    await dialog.getByRole("button", { name: "Remind me later" }).click();
    await expect(dialog).toBeHidden();

    await page.reload();
    await page.waitForTimeout(2500);
    await expect(dialog).toBeHidden();

    // Signing out ends the login; the next one starts without the snooze.
    await page.evaluate(() => window.localStorage.removeItem("palee:login-session"));
    await openChecklist(page, "/org/kypseli/admin");
  });
});
