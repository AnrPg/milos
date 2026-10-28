import { expect, test, type Page } from "./support/test";

// The app shell (top bar, bell, badges, onboarding, guides) must not repeat
// its requests on every screen or every return to the tab: each piece of
// shell data is fetched once and then kept current by realtime events. The
// notifications list loads only when the bell opens. The API is stubbed.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({
      sub: user.id,
      role: user.role,
      memberships: [{ organization_id: "org-1", organization_slug: "kypseli" }],
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

const notification = {
  id: "n-1",
  user_id: user.id,
  organization_id: null,
  type: "password_reset_completed",
  payload: { url: "/me/settings#security" },
  read_at: null,
  inserted_at: new Date().toISOString(),
};

async function stub(page: Page) {
  const calls: string[] = [];
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.pathname.startsWith("/api/")) calls.push(url.pathname);
  });
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([{ role: "member", roles: ["member"], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }]),
    ),
  );
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/notifications/unread-count", (route) => route.fulfill(json({ unread_count: 1 })));
  await page.route("**/api/notifications?**", (route) =>
    route.fulfill(json({ notifications: [notification], next_cursor: null, unread_count: 1 })),
  );
  return { count: (path: string) => calls.filter((call) => call === path).length };
}

/** What the browser does when the person comes back to the tab. */
async function returnToTab(page: Page) {
  await page.evaluate(() => {
    document.dispatchEvent(new Event("visibilitychange"));
    window.dispatchEvent(new Event("focus"));
  });
}

test.describe("shell requests", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("the shell fetches its data once, and the bell's list only when it opens", async ({ page }) => {
    const api = await stub(page);
    await page.goto("/me/settings");
    const bell = page.getByTestId("member-top-bar").getByRole("button", { name: "1 unread notification" });
    await expect(bell).toBeVisible();

    // One request per piece of shell data; the list waits for the bell.
    expect(api.count("/api/memberships")).toBe(1);
    expect(api.count("/api/notifications/unread-count")).toBe(1);
    expect(api.count("/api/notifications")).toBe(0);
    // Clubs are read where they show (or a guide runs), not by the shell.
    expect(api.count("/api/me/clubs")).toBe(0);

    // Coming back to the tab serves the fresh cache instead of refetching it.
    await returnToTab(page);
    await returnToTab(page);
    await page.waitForTimeout(1_000);
    expect(api.count("/api/memberships")).toBe(1);
    expect(api.count("/api/notifications/unread-count")).toBe(1);
    expect(api.count("/api/notifications")).toBe(0);

    await bell.click();
    await expect(page.getByText("Your password was reset")).toBeVisible();
    expect(api.count("/api/notifications")).toBe(1);
  });
});
