import { expect, test, type Page } from "./support/test";

// ADR-217: people are shown by their roles in the box, never by the
// account-wide role. Staff rows are tinted and carry no membership status;
// an owner's profile reads «Owner», with no Finance section. The API is
// stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const OWNER = {
  id: "owner-1",
  nickname: "Xristoforos",
  role: "member",
  email: "owner@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

const TOKEN = `stub.${Buffer.from(
  JSON.stringify({ sub: OWNER.id, role: OWNER.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
).toString("base64url")}.signature`;

const entry = (id: string, nickname: string, roles: string[], extra: Record<string, unknown> = {}) => ({
  id,
  nickname,
  avatar_url: null,
  role: roles[0],
  roles,
  coach_scope: null,
  staff: roles.some((role) => !["member", "athlete"].includes(role)),
  client: roles.some((role) => ["member", "athlete"].includes(role)),
  account_status: "active",
  joined_at: "2026-10-01T10:00:00Z",
  finance_status: null,
  attention_count: 0,
  ...extra,
});

const USERS = [
  entry("owner-1", "Xristoforos", ["owner"]),
  entry("coach-1", "Kostas", ["coach", "member"], { coach_scope: "all", finance_status: "active" }),
  entry("member-1", "Maria", ["member"], { finance_status: "active" }),
];

async function signedInOwner(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: TOKEN, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(OWNER)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/admin/users?**", (route) =>
    route.fulfill(json({ users: USERS, meta: { total: USERS.length, limit: 50, offset: 0, has_more: false } })),
  );
}

test.describe("box roles in Users (ADR-217)", () => {
  test("the list shows every role, tints staff and gives staff no membership status", async ({ page }) => {
    await signedInOwner(page);
    await page.goto("/admin/users");

    const list = page.getByRole("region", { name: "People" });
    const owner = list.getByRole("listitem").filter({ hasText: "Xristoforos" });
    const coach = list.getByRole("listitem").filter({ hasText: "Kostas" });
    const member = list.getByRole("listitem").filter({ hasText: "Maria" });

    await expect(owner).toContainText("Owner", { timeout: 60_000 });
    await expect(owner).toHaveAttribute("data-staff", "true");
    await expect(owner).not.toContainText("No finance profile");
    await expect(coach).toContainText("Head coach");
    await expect(coach).toHaveAttribute("data-staff", "true");
    await expect(member).not.toHaveAttribute("data-staff", "true");

    await page.getByRole("radio", { name: /Staff/ }).click();
    await expect(list.getByRole("listitem")).toHaveCount(2);
    await page.getByRole("radio", { name: /Box members/ }).click();
    await expect(list.getByRole("listitem")).toHaveCount(2);
  });

  test("an owner's profile reads Owner and has no Finance", async ({ page }) => {
    await signedInOwner(page);
    await page.route("**/api/org/*/admin/users/owner-1", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "owner-1", nickname: "Xristoforos", avatar_url: null, role: "owner", joined_at: "2026-10-27T10:00:00Z" },
            account_status: "active",
            membership: { roles: ["owner"], coach_scope: "own", location_scope: { all_locations: true, location_ids: [] } },
            available_sections: ["overview", "training_history", "prs", "scores", "class_participation", "messages", "admin_actions"],
            attention: [],
            operational_links: { messages: "/messages", user_id: "owner-1" },
          },
        }),
      ),
    );

    await page.goto("/admin/users/owner-1");
    await expect(page.getByRole("heading", { name: "Xristoforos" })).toBeVisible({ timeout: 60_000 });
    await expect(page.locator("main")).toContainText("Owner");
    await expect(page.locator("main")).not.toContainText("Box member");
    await expect(page.getByRole("tab", { name: "Finance" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: /Move to class/ })).toHaveCount(0);
  });
});
