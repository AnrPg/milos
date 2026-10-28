import { expect, test, type Page, type Route } from "./support/test";

// ADR-206: "Forgot password" and the page a reset link opens. A confirmed
// email gets a link automatically; "I can't access my email" goes to the
// handlers; the link page only checks the token and spends it on submit.
// The API is stubbed; the public answer is always { status: "sent" }.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

type Requests = { resetRequests: Record<string, unknown>[]; inspected: string[]; completed: Record<string, unknown>[] };

async function stubApi(page: Page, links: Record<string, { status: number; body: unknown }> = {}) {
  const seen: Requests = { resetRequests: [], inspected: [], completed: [] };

  await page.route("**/api/**", (route: Route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({}, 401)));
  await page.route("**/api/auth/me", (route) => route.fulfill(json({}, 401)));
  await page.route("**/api/auth/password-reset-requests", (route) => {
    seen.resetRequests.push(route.request().postDataJSON());
    return route.fulfill(json({ status: "sent" }, 202));
  });
  await page.route("**/api/auth/password-reset/inspect", (route) => {
    const { token } = route.request().postDataJSON() as { token: string };
    seen.inspected.push(token);
    const answer = links[token] ?? { status: 422, body: { code: "invalid_reset_link" } };
    return route.fulfill(json(answer.body, answer.status));
  });
  await page.route("**/api/auth/password-reset", (route) => {
    seen.completed.push(route.request().postDataJSON());
    return route.fulfill({ status: 204, body: "" });
  });

  return seen;
}

const usable = { status: 200, body: { expires_at: "2026-12-24T13:00:00Z" } };

test("asks for an emailed link and answers the same way whatever the account", async ({ page }) => {
  const seen = await stubApi(page);
  await page.goto("/forgot-password");

  await page.getByLabel("Email or @handle").fill("@maria");
  await page.getByRole("button", { name: "Send reset link" }).click();

  await expect(page.getByRole("heading", { name: "Check your email" })).toBeVisible();
  await expect(page.getByRole("status")).toContainText("If an account matches what you entered");
  expect(seen.resetRequests).toEqual([{ identifier: "@maria", locale: "en" }]);
});

test("'I can't access my email' asks the people who know the person", async ({ page }) => {
  const seen = await stubApi(page);
  await page.goto("/forgot-password");

  await page.getByRole("button", { name: "I can't access my email" }).click();
  await expect(page.getByRole("heading", { name: "Can't open your email?" })).toBeVisible();
  await page.getByLabel("Email or @handle").fill("maria@example.com");
  await page.getByRole("button", { name: "Ask for help" }).click();

  await expect(page.getByRole("heading", { name: "Request sent" })).toBeVisible();
  expect(seen.resetRequests).toEqual([{ identifier: "maria@example.com", cant_access_email: true, locale: "en" }]);
});

test("a reset link is checked on open and spent only when the password is saved", async ({ page }) => {
  const seen = await stubApi(page, { good: usable });
  await page.goto("/reset-password#token=good");

  await expect(page.getByLabel("New password", { exact: true })).toBeVisible();
  expect(seen.inspected).toEqual(["good"]);
  expect(seen.completed).toEqual([]);
  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe("");

  await page.getByLabel("New password", { exact: true }).fill("new pass");
  await page.getByLabel("Repeat new password").fill("new pass");
  await page.getByRole("button", { name: "Set new password" }).click();

  await expect(page.getByRole("heading", { name: "Password changed" })).toBeVisible();
  expect(seen.completed).toEqual([{ token: "good", password: "new pass" }]);
});

test("old ?token= links from handlers still open the form", async ({ page }) => {
  const seen = await stubApi(page, { legacy: usable });
  await page.goto("/reset-password?token=legacy");

  await expect(page.getByLabel("New password", { exact: true })).toBeVisible();
  expect(seen.inspected).toEqual(["legacy"]);
});

for (const [token, status, code, message] of [
  ["old", 410, "expired_reset_link", "This reset link has expired."],
  ["spent", 410, "used_reset_link", "This reset link was already used"],
  ["bogus", 422, "invalid_reset_link", "This reset link isn't valid."],
] as const) {
  test(`a ${code} link says so before any password is typed`, async ({ page }) => {
    await stubApi(page, { [token]: { status, body: { code } } });
    await page.goto(`/reset-password#token=${token}`);

    await expect(page.getByText(message)).toBeVisible();
    await expect(page.getByRole("link", { name: "Ask for a new link" })).toHaveAttribute("href", "/forgot-password");
    await expect(page.getByLabel("New password", { exact: true })).toHaveCount(0);
  });
}
