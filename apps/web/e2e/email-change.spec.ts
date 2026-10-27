import { expect, test, type Page, type Route } from "./support/test";

// ADR-207: Εγώ › Ρυθμίσεις › Personal info › Email. The email changes only
// once the new address opens the mailed link; the old address can undo it
// ("this wasn't me"). The API is stubbed.

const user = {
  id: "member-1",
  nickname: "Maria L",
  display_name: "Maria L",
  handle: "maria",
  role: "member",
  email: "maria@example.com",
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  profile_count: 1,
  profile_limit: 3,
  memberships: [],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

type Pending = { email: string; requested_at: string; expires_at: string } | null;

async function stubSignedIn(page: Page, { locked = false } = {}) {
  let pending: Pending = null;
  const requests: { method: string; url: string; body: unknown }[] = [];
  const lockedUntil = locked ? "2027-01-03T10:00:00Z" : null;

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/auth/profiles", (route) =>
    route.fulfill(json({ profiles: [{ ...user, user_id: user.id, current: true }], profile_limit: 3 })),
  );
  await page.route("**/api/me/email-change**", async (route: Route) => {
    const request = route.request();
    const body = request.postData() ? request.postDataJSON() : null;
    requests.push({ method: request.method(), url: request.url(), body });

    if (request.method() === "POST" && request.url().endsWith("/email-change")) {
      if (body.current_password !== "secret") {
        return route.fulfill(json({ code: "invalid_current_password", error: "Current password is incorrect" }, 422));
      }
      pending = {
        email: body.email.trim().toLowerCase(),
        requested_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      };
      return route.fulfill(json({ pending, locked_until: null }, 202));
    }
    if (request.method() === "POST" && request.url().endsWith("/resend")) {
      return route.fulfill(json({ pending, locked_until: null }));
    }
    if (request.method() === "DELETE") {
      pending = null;
      return route.fulfill(json({ pending, locked_until: null }));
    }
    return route.fulfill(json({ pending, locked_until: lockedUntil }));
  });
  return requests;
}

test.describe("email change", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("asking for a new email waits for its link; resend and cancel", async ({ page }) => {
    const requests = await stubSignedIn(page);
    await page.goto("/me/settings#personal");

    const field = page.getByTestId("email-change");
    await expect(field).toContainText("maria@example.com");
    await field.getByRole("button", { name: "Change email" }).click();

    await field.getByLabel("New email").fill("new@example.com");
    await field.getByLabel("Current password").fill("wrong");
    await field.getByRole("button", { name: "Send link" }).click();
    await expect(field.getByRole("alert")).toContainText("That current password isn't right.");

    await field.getByLabel("Current password").fill("secret");
    await field.getByRole("button", { name: "Send link" }).click();

    const pending = page.getByTestId("email-change-pending");
    await expect(pending).toContainText("Waiting for confirmation at new@example.com");
    await expect(pending).toContainText("Until then you sign in with maria@example.com.");
    // The account's email itself has not changed.
    await expect(field).toContainText("maria@example.com");

    await pending.getByRole("button", { name: "Send again" }).click();
    await expect(pending).toContainText("Link sent.");
    await pending.getByRole("button", { name: "Cancel change" }).click();
    await expect(pending).toHaveCount(0);

    expect(requests.map((r) => `${r.method} ${new URL(r.url).pathname}`)).toEqual(
      expect.arrayContaining(["POST /api/me/email-change", "POST /api/me/email-change/resend", "DELETE /api/me/email-change"]),
    );

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("after a revert, changes are paused", async ({ page }) => {
    await stubSignedIn(page, { locked: true });
    await page.goto("/me/settings#personal");
    await expect(page.getByTestId("email-change-locked")).toContainText("Email changes are paused until");
    await expect(page.getByTestId("email-change").getByRole("button", { name: "Change email" })).toHaveCount(0);
  });

  test("the link to the new address changes the email only on a press", async ({ page }) => {
    let confirmed: unknown = null;
    await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill({ status: 204, body: "" }));
    await page.route("**/api/auth/email-change/confirm", (route) => {
      confirmed = route.request().postDataJSON();
      return route.fulfill(json({ email: "new@example.com", access_token: null }));
    });

    await page.goto("/confirm-email-change#token=tok_123");
    await expect(page.getByRole("heading", { name: "Confirm your new email" })).toBeVisible();
    expect(confirmed).toBeNull();

    await page.getByRole("button", { name: "Confirm new email" }).click();
    await expect(page.getByRole("status")).toContainText("Your account's email is now new@example.com.");
    expect(confirmed).toEqual({ token: "tok_123" });
    await expect(page.getByRole("link", { name: "Sign in" })).toHaveAttribute("href", "/login");
  });

  test("an address taken meanwhile is reported plainly", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill({ status: 204, body: "" }));
    await page.route("**/api/auth/email-change/confirm", (route) =>
      route.fulfill(json({ code: "email_change_unavailable", error: "unavailable" }, 409)),
    );
    await page.goto("/confirm-email-change#token=tok_123");
    await page.getByRole("button", { name: "Confirm new email" }).click();
    await expect(page.getByRole("alert")).toContainText("This address can't be used for your account.");
  });

  test("\"this wasn't me\" restores the old email and points to a password reset", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill({ status: 204, body: "" }));
    await page.route("**/api/auth/email-change/revert", (route) => route.fulfill(json({ email: "maria@example.com" })));

    await page.goto("/revert-email-change#token=tok_456");
    await page.getByRole("button", { name: "Restore my email" }).click();
    await expect(page.getByRole("status")).toContainText("Your account's email is maria@example.com again");
    await expect(page.getByRole("link", { name: "Reset password" })).toHaveAttribute("href", "/forgot-password");
  });

  test("an expired revert link says so", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill({ status: 204, body: "" }));
    await page.route("**/api/auth/email-change/revert", (route) =>
      route.fulfill(json({ code: "expired_email_change_link", error: "expired" }, 410)),
    );
    await page.goto("/revert-email-change#token=old");
    await page.getByRole("button", { name: "Restore my email" }).click();
    await expect(page.getByRole("alert")).toContainText("This link has expired.");
  });
});
