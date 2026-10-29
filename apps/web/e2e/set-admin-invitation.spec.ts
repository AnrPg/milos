import { expect, test, type Page } from "./support/test";

// ADR-187/204: the owner invitation page (/set-admin). An email that already
// has an account is told to use that account's password or to sign in, and a
// signed-in profile can accept the invitation itself. The API is stubbed;
// every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const TOKEN = "owner-invite-token-1234567890";

const INVITATION = {
  role: "owner",
  expires_at: "2026-11-03T09:00:00Z",
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
};

const VENDOR = {
  id: "vendor-1",
  nickname: "Palee",
  handle: "prod_owner_regas",
  role: "admin",
  email: "vendor@example.com",
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: true,
};

function tokenFor(sub: string, slugs: string[] = []) {
  const payload = Buffer.from(
    JSON.stringify({
      sub,
      role: "admin",
      memberships: slugs.map((organization_slug) => ({ organization_slug })),
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

async function stubInvitation(page: Page) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/invitations/inspect", (route) => route.fulfill(json(INVITATION)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

test.describe("Owner invitation page", () => {
  test("an email with an account is told to use its password or sign in", async ({ page }) => {
    await stubInvitation(page);
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
    await page.route("**/api/auth/register-admin", (route) =>
      route.fulfill(
        json(
          {
            code: "email_in_use",
            error: "This email already has accounts",
            errors: { email: ["already has accounts"] },
            profile_count: 1,
            profile_limit: 3,
          },
          409,
        ),
      ),
    );

    await page.goto(`/set-admin?token=${TOKEN}`);
    await expect(page.getByText("Box Kypseli")).toBeVisible();
    await expect(page.getByText("If this email already has a Palee account, type that account's password.")).toBeVisible();

    await page.getByLabel("Nickname").fill("test_admin");
    await page.getByLabel("Email address").fill("vendor@example.com");
    await page.getByLabel("Password").fill("1234");
    await page.getByLabel("I am 16 or older").check();
    await page.getByRole("button", { name: "Create admin account" }).click();

    await expect(page.getByText("This email's account already has 1 of 3 profiles.", { exact: false })).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in to accept" })).toHaveAttribute(
      "href",
      `/login?next=${encodeURIComponent(`/set-admin?token=${TOKEN}`)}`,
    );
    await expect(page.getByRole("link", { name: "Forgot the password?" })).toHaveAttribute("href", "/forgot-password");
    await expect(page).toHaveURL(/\/set-admin\?token=/);
  });

  test("a signed-in profile accepts the invitation and opens the box's admin", async ({ page }) => {
    await stubInvitation(page);
    const before = tokenFor(VENDOR.id);
    const after = tokenFor(VENDOR.id, ["kypseli"]);
    let accepted: unknown = null;

    await page.route("**/api/auth/refresh", (route) =>
      route.fulfill(json({ access_token: accepted ? after : before, user: VENDOR })),
    );
    await page.route("**/api/auth/me", (route) => route.fulfill(json(VENDOR)));
    await page.route("**/api/memberships", (route) =>
      route.fulfill(
        json(
          accepted
            ? [
                {
                  role: "owner",
                  roles: ["owner"],
                  capabilities: { manage_settings: "all", manage_members: "all" },
                  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active" },
                  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
                },
              ]
            : [],
        ),
      ),
    );
    await page.route("**/api/auth/accept-invitation", (route) => {
      accepted = route.request().postDataJSON();
      return route.fulfill(
        json({
          organization: INVITATION.organization,
          roles: ["owner"],
          access_token: null,
          user: null,
        }),
      );
    });

    await page.goto(`/set-admin?token=${TOKEN}`);
    await expect(page.getByText("You're signed in as @prod_owner_regas")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign out and continue" })).toBeVisible();

    await page.getByRole("button", { name: "Accept as @prod_owner_regas" }).click();

    await expect(page).toHaveURL(/\/org\/kypseli\/admin/);
    expect(accepted).toEqual({ invitation_token: TOKEN });
  });
});
