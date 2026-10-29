import { expect, test, type Page } from "./support/test";

// ADR-211: sign-up never tells whether an email already has an account (a
// known email gets the same "check your inbox" step, with no session), and
// self-service deletion: Settings › Delete profile or account (password,
// emailed link or typed email, 7-day grace), the emailed confirm and undo
// pages, and "undo the deletion" on the sign-in form. The API is stubbed;
// every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const SCHEDULED_FOR = "2026-11-09T10:00:00Z";
const LINK_TOKEN = "t".repeat(43);

const user = {
  id: "member-1",
  nickname: "Maria L",
  display_name: "Maria L",
  handle: "maria",
  role: "member",
  email: "maria@example.com",
  email_verified: true,
  profile_count: 2,
  profile_limit: 3,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

async function signedOut(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
  await page.route("**/api/auth/handle-suggestion?**", (route) => route.fulfill(json({ handle: "maria" })));
  await page.route("**/api/auth/handle-available?**", (route) =>
    route.fulfill(json({ available: true, handle: "maria", suggestions: [] })),
  );
}

async function signedIn(page: Page, me: Record<string, unknown> = user) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), user: me })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(me)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [], unread_count: 0 })));
}

async function fillSignUp(page: Page) {
  await page.goto("/register");
  await page.getByLabel("Your name", { exact: true }).fill("Maria");
  await page.getByLabel("Handle", { exact: true }).fill("maria");
  await page.getByLabel("Email address", { exact: true }).fill("maria@example.com");
  await page.getByLabel("Password", { exact: true }).fill("secret-pass");
  await page.getByLabel("I am 16 or older").check();
  await page.getByRole("button", { name: "Create account" }).click();
}

test.describe("sign-up without an account-existence leak", () => {
  test("a known email sees the same check-your-inbox step, then lands on sign-in", async ({ page }) => {
    await signedOut(page);
    await page.route("**/api/auth/register", (route) =>
      route.fulfill(json({ confirmation: "email_sent", email: "maria@example.com" }, 201)),
    );
    await fillSignUp(page);

    await expect(page.getByRole("heading", { name: "Check your inbox" })).toBeVisible();
    await expect(page.getByText("We sent a link to maria@example.com.")).toBeVisible();
    await expect(page.locator("[data-error-notice]")).toHaveCount(0);
    await page.getByRole("button", { name: "Continue" }).click();

    await expect(page.getByLabel("Email or @handle", { exact: true })).toHaveValue("maria@example.com");
    await expect(page.getByLabel("Password", { exact: true })).toHaveValue("");
  });

  test("a new email sees the same step, then goes on with its session", async ({ page }) => {
    await signedOut(page);
    const fresh = { ...user, profile_count: 1, email_verified: false };
    await page.route("**/api/auth/register", (route) =>
      route.fulfill(json({ access_token: token(), confirmation: "email_sent", email: "maria@example.com" }, 201)),
    );
    await page.route("**/api/auth/me", (route) => route.fulfill(json(fresh)));
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));
    await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [], unread_count: 0 })));
    await fillSignUp(page);

    await expect(page.getByRole("heading", { name: "Check your inbox" })).toBeVisible();
    await expect(page.getByText("We sent a link to maria@example.com.")).toBeVisible();
    await page.getByRole("button", { name: "Continue" }).click();
    await expect(page.getByRole("heading", { name: "Your account is ready" })).toBeVisible();
    await expect(page.getByText("Save recovery codes?")).toBeVisible();
  });
});

test.describe("account deletion", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("Settings asks for the password and sends the confirmation link", async ({ page }) => {
    await signedIn(page);
    const requests: unknown[] = [];
    let state: Record<string, unknown> = { status: "none", scope: null, scheduled_for: null };
    await page.route("**/api/auth/account-deletion", (route) => {
      const method = route.request().method();
      if (method === "POST") {
        requests.push(route.request().postDataJSON());
        state = { status: "awaiting_confirmation", scope: "profile", scheduled_for: null };
        return route.fulfill(json({ ...state, email: user.email }, 202));
      }
      if (method === "DELETE") {
        state = { status: "none", scope: null, scheduled_for: null };
        return route.fulfill({ status: 204, body: "" });
      }
      return route.fulfill(json(state));
    });
    await page.goto("/me/settings#delete-account");

    const section = page.locator("section#delete-account");
    await expect(section.getByText("Delete profile or account", { exact: true })).toBeVisible();
    await section.getByRole("button", { name: "Delete this profile" }).click();

    const dialog = page.getByRole("dialog", { name: "Delete the profile @maria?" });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByLabel("Type your email address to confirm")).toHaveCount(0);
    await dialog.getByLabel("Your password").fill("secret-pass");
    await dialog.getByRole("button", { name: "Delete", exact: true }).click();

    await expect(section.getByText("We sent a confirmation link to maria@example.com.", { exact: false })).toBeVisible();
    expect(requests).toEqual([{ scope: "profile", password: "secret-pass" }]);

    await section.getByRole("button", { name: "Cancel the request" }).click();
    await expect(section.getByRole("button", { name: "Delete account and all profiles" })).toBeVisible();
  });

  test("an unconfirmed email types the address; a sole owner is told which business", async ({ page }) => {
    await signedIn(page, { ...user, email_verified: false, profile_count: 1 });
    await page.route("**/api/auth/account-deletion", (route) => {
      if (route.request().method() === "POST") {
        return route.fulfill(
          json({ code: "sole_owner", error: "owner", organizations: ["Box Kypseli"] }, 409),
        );
      }
      return route.fulfill(json({ status: "none", scope: null, scheduled_for: null }));
    });
    await page.goto("/me/settings#delete-account");

    const section = page.locator("section#delete-account");
    await expect(section.getByRole("button", { name: "Delete this profile" })).toHaveCount(0);
    await section.getByRole("button", { name: "Delete account and all profiles" }).click();

    const dialog = page.getByRole("dialog", { name: "Delete your account and all its profiles?" });
    await dialog.getByLabel("Your password").fill("secret-pass");
    await dialog.getByLabel("Type your email address to confirm").fill("maria@example.com");
    await dialog.getByRole("button", { name: "Delete", exact: true }).click();
    await expect(dialog.getByText("You are the only owner of «Box Kypseli».", { exact: false })).toBeVisible();
  });

  test("the emailed link schedules the deletion only when pressed", async ({ page }) => {
    await signedOut(page);
    const confirmed: unknown[] = [];
    await page.route("**/api/auth/account-deletion/confirm", (route) => {
      confirmed.push(route.request().postDataJSON());
      return route.fulfill(json({ status: "scheduled", scope: "login", scheduled_for: SCHEDULED_FOR }));
    });
    await page.goto(`/account-deletion/confirm#token=${LINK_TOKEN}`);

    await expect(page.getByRole("heading", { name: "Confirm deletion" })).toBeVisible();
    expect(confirmed).toEqual([]);
    await page.getByRole("button", { name: "Schedule the deletion" }).click();
    await expect(page.getByText("Your account will be deleted on November 9, 2026.", { exact: false })).toBeVisible();
    expect(confirmed).toEqual([{ token: LINK_TOKEN }]);
  });

  test("the undo link keeps the account; a used one says so", async ({ page }) => {
    await signedOut(page);
    let calls = 0;
    await page.route("**/api/auth/account-deletion/undo", (route) => {
      calls += 1;
      return calls === 1
        ? route.fulfill(json({ status: "none", scope: null, scheduled_for: null }))
        : route.fulfill(json({ code: "invalid_deletion_link", error: "used" }, 422));
    });

    await page.goto(`/account-deletion/undo#token=${LINK_TOKEN}`);
    await page.getByRole("button", { name: "Keep my account" }).click();
    await expect(page.getByText("The deletion is cancelled. You can sign in as before.")).toBeVisible();

    // Opening the link again is a fresh load (the same URL would only change the hash).
    await page.goto("about:blank");
    await page.goto(`/account-deletion/undo#token=${LINK_TOKEN}`);
    await page.getByRole("button", { name: "Keep my account" }).click();
    await expect(page.getByText("This link doesn't work. It may have been used already.")).toBeVisible();
  });

  test("signing in to a scheduled account offers to undo it", async ({ page }) => {
    await signedOut(page);
    const undone: unknown[] = [];
    await page.route("**/api/auth/login", (route) =>
      route.fulfill(
        json({ code: "account_deletion_scheduled", error: "scheduled", scheduled_for: SCHEDULED_FOR }, 403),
      ),
    );
    await page.route("**/api/auth/account-deletion/undo-sign-in", (route) => {
      undone.push(route.request().postDataJSON());
      return route.fulfill(json({ access_token: token(), user }));
    });
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));

    await page.goto("/login");
    await page.getByLabel("Email or @handle", { exact: true }).fill("maria@example.com");
    await page.getByLabel("Password", { exact: true }).fill("secret-pass");
    await page.getByRole("button", { name: "Sign in", exact: true }).click();

    await expect(page.getByText("This account is scheduled for deletion on November 9, 2026.")).toBeVisible();
    await page.getByRole("button", { name: "Undo the deletion and sign in" }).click();
    await expect(page).not.toHaveURL(/\/login/);
    expect(undone).toEqual([{ identifier: "maria@example.com", password: "secret-pass" }]);
  });
});
