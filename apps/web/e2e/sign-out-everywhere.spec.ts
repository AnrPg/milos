import { expect, test, type Page } from "./support/test";

// ADR-208: the page a security notice's "sign out everywhere" link opens.
// Signed out: the refresh and /auth/me stubs answer 401.
async function stubSignedOut(page: Page) {
  await page.route("**/api/auth/refresh", (route) =>
    route.fulfill({ status: 401, contentType: "application/json", body: "{}" }),
  );
  await page.route("**/api/auth/me", (route) =>
    route.fulfill({ status: 401, contentType: "application/json", body: "{}" }),
  );
  await page.route("**/api/theme", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "{}" }),
  );
}

async function stubSignOutLink(page: Page, answer: { status: number; body?: unknown }) {
  const posted: unknown[] = [];
  await page.route("**/api/auth/sign-out-everywhere", async (route) => {
    posted.push(route.request().postDataJSON());
    await route.fulfill({
      status: answer.status,
      contentType: "application/json",
      body: answer.body === undefined ? "" : JSON.stringify(answer.body),
    });
  });
  return posted;
}

test.describe("sign out everywhere link", () => {
  test("signs every device out with one tap, then offers a new password", async ({ page }) => {
    await stubSignedOut(page);
    const posted = await stubSignOutLink(page, { status: 204 });

    await page.goto("/sign-out-everywhere#token=tok_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG");
    await expect(page.getByRole("heading", { name: /sign out everywhere\?/i })).toBeVisible();
    // Nothing happens until the tap.
    expect(posted).toHaveLength(0);

    await page.getByRole("button", { name: /^sign out everywhere$/i }).click();

    await expect(page.getByRole("heading", { name: /signed out everywhere/i })).toBeVisible();
    expect(posted).toEqual([{ token: "tok_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG" }]);
    await expect(page.getByRole("link", { name: /choose a new password/i })).toHaveAttribute(
      "href",
      "/forgot-password",
    );
  });

  test("explains an expired link", async ({ page }) => {
    await stubSignedOut(page);
    await stubSignOutLink(page, {
      status: 410,
      body: { code: "expired_link", error: "This link has expired" },
    });

    await page.goto("/sign-out-everywhere#token=tok_expired");
    await page.getByRole("button", { name: /^sign out everywhere$/i }).click();

    await expect(page.getByRole("heading", { name: /this link can't be used/i })).toBeVisible();
    await expect(page.getByText(/this link has expired/i)).toBeVisible();
  });

  test("a link without a token says so without calling the API", async ({ page }) => {
    await stubSignedOut(page);
    const posted = await stubSignOutLink(page, { status: 204 });

    await page.goto("/sign-out-everywhere");

    await expect(page.getByRole("heading", { name: /this link can't be used/i })).toBeVisible();
    expect(posted).toHaveLength(0);
  });
});
