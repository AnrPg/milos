import { expect, test, type Page } from "./support/test";

// ADR-213: the "confirm your email" banner for a signed-in, unverified login,
// and the /verify-email page the emailed link opens (token in the fragment).
// The API is stubbed; every route not listed answers an empty object.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "maria@example.com",
  email_verified: false,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
};

function tokenFor() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

async function stubSignedIn(page: Page, me: () => Record<string, unknown>) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor() })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(me())));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

async function stubSignedOut(page: Page) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill({ status: 204, body: "" }));
  await page.route("**/api/auth/me", (route) => route.fulfill(json({ error: "Unauthorized" }, 401)));
}

test.describe("email verification banner", () => {
  test("offers resend and change email, says when to retry, and hides for the session", async ({ page }) => {
    await stubSignedIn(page, () => user);
    let resends = 0;
    await page.route("**/api/auth/verification-email", (route) => {
      resends += 1;
      return resends === 1
        ? route.fulfill(json({ status: "sent" }))
        : route.fulfill(json({ code: "throttled", error: "Try later", retry_after_seconds: 42 }, 429));
    });

    await page.goto("/me");
    const banner = page.getByTestId("email-verification-banner");
    await expect(banner).toContainText("maria@example.com");
    await expect(banner.getByRole("link", { name: "Change email" })).toHaveAttribute("href", "/me/settings#personal");

    await banner.getByRole("button", { name: "Resend" }).click();
    await expect(banner.getByRole("status")).toHaveText("Sent. Check your inbox.");

    await page.reload();
    await page.getByTestId("email-verification-banner").getByRole("button", { name: "Resend" }).click();
    await expect(page.getByTestId("email-verification-banner").getByRole("status")).toContainText("42");

    await page.getByTestId("email-verification-banner").getByRole("button", { name: "Hide for now" }).click();
    await expect(page.getByTestId("email-verification-banner")).toHaveCount(0);
    await page.reload();
    await expect(page.getByTestId("email-verification-banner")).toHaveCount(0);
  });

  test("does not show for a verified login", async ({ page }) => {
    await stubSignedIn(page, () => ({ ...user, email_verified: true }));
    await page.goto("/me");
    await expect(page.getByTestId("email-verification-banner")).toHaveCount(0);
  });
});

test.describe("/verify-email", () => {
  test("signed out: posts the fragment's token once and confirms", async ({ page }) => {
    await stubSignedOut(page);
    const posted: string[] = [];
    await page.route("**/api/auth/verify-email", (route) => {
      posted.push(route.request().postDataJSON().token);
      return route.fulfill(json({ email_verified: true }));
    });

    await page.goto("/verify-email#token=abc123");
    await expect(page.getByRole("heading", { name: "Email confirmed" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in" })).toHaveAttribute("href", "/login");
    expect(posted).toEqual(["abc123"]);
    // The token does not stay in the address bar.
    expect(new URL(page.url()).hash).toBe("");
  });

  test("signed out: an expired link sends people to sign in for a new one", async ({ page }) => {
    await stubSignedOut(page);
    await page.route("**/api/auth/verify-email", (route) =>
      route.fulfill(json({ code: "expired_verification_link", error: "This link has expired" }, 410)),
    );

    await page.goto("/verify-email#token=old");
    await expect(page.getByRole("alert")).toContainText("This link has expired.");
    await expect(page.getByRole("link", { name: "Sign in to get a new link" })).toBeVisible();
  });

  test("signed in: a used link offers a new one", async ({ page }) => {
    await stubSignedIn(page, () => user);
    await page.route("**/api/auth/verify-email", (route) =>
      route.fulfill(json({ code: "used_verification_link", error: "Used" }, 409)),
    );
    await page.route("**/api/auth/verification-email", (route) => route.fulfill(json({ status: "sent" })));

    await page.goto("/verify-email#token=spent");
    await expect(page.getByRole("alert")).toContainText("This link was already used.");
    await page.getByRole("button", { name: "Send a new link" }).click();
    await expect(page.getByText("A new link is on its way to maria@example.com.")).toBeVisible();
  });

  test("without a token the link is invalid", async ({ page }) => {
    await stubSignedOut(page);
    await page.goto("/verify-email");
    await expect(page.getByRole("alert")).toContainText("This link isn't valid.");
  });
});
