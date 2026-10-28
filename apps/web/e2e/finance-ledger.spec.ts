import { expect, test, type Page } from "./support/test";

import { chooseOption } from "./support/select";

// Finance › Ledger (the members tab). Staff assign a πακέτο συνδρομής from a
// member's row: the package list opens in its own layer, and picking from it
// must not close the «Assign» menu before the choice lands. The API is
// stubbed; anything not stubbed answers `{}`.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const MEMBER_ID = "a11ce000-0000-4000-8000-000000000001";
const PACKAGE_ID = "9ac4a9e0-0000-4000-8000-000000000001";

function owner() {
  const user = {
    id: "owner-1",
    nickname: "Apostolos",
    role: "admin",
    email: "owner-1@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

async function ledger(page: Page, assign: (body: unknown) => { status: number; body: unknown }) {
  const persona = owner();
  const assigned: unknown[] = [];
  let member: Record<string, unknown> = {
    id: MEMBER_ID,
    nickname: "Maria",
    identity_role: "member",
    user_type: "member",
    membership: { status: "active" },
    active_package_subscription: null,
  };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { take_payments: "all", manage_memberships: "all", manage_packages: "all", view_package_catalog: "all" },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/kypseli/admin/finance/package-catalog", (route) => route.fulfill(json({ types: [], modules: [] })));
  await page.route("**/api/org/kypseli/admin/finance/packages**", (route) =>
    route.fulfill(json({ packages: [{ id: PACKAGE_ID, name: "Unlimited monthly", code: "unlimited", active: true }] })),
  );
  await page.route("**/api/org/kypseli/admin/finance/members?**", (route) => route.fulfill(json({ members: [member], meta: {} })));
  await page.route("**/api/org/kypseli/admin/finance/members", (route) => route.fulfill(json({ members: [member], meta: {} })));
  await page.route(`**/api/org/kypseli/admin/finance/members/${MEMBER_ID}/packages`, (route) => {
    const body = route.request().postDataJSON();
    assigned.push(body);
    const reply = assign(body);
    if (reply.status < 300) {
      member = {
        ...member,
        active_package_subscription: { id: "sub-1", status: "active", membership_package_id: PACKAGE_ID, package_name: "Unlimited monthly" },
      };
    }
    return route.fulfill(json(reply.body, reply.status));
  });
  await page.goto("/org/kypseli/admin/finance?tab=members");
  return assigned;
}

test.describe("finance ledger", () => {
  test("staff assign a subscription package from a member's row", async ({ page }) => {
    const assigned = await ledger(page, () => ({ status: 201, body: { package_subscription: { id: "sub-1" } } }));

    await page.getByRole("button", { name: "+ Assign" }).click();
    const menu = page.getByRole("dialog", { name: "Assign" });
    await chooseOption(page, menu.getByRole("combobox"), PACKAGE_ID);
    // The menu is still open after the pick, with the package chosen.
    await expect(menu).toBeVisible();
    await menu.getByRole("button", { name: "Assign", exact: true }).click();

    await expect.poll(() => assigned).toEqual([{ membership_package_id: PACKAGE_ID }]);
    await expect(menu).toBeHidden();
    await expect(page.getByRole("button", { name: /Unlimited monthly/ })).toBeVisible();
  });

  test("a refused assignment stays in the menu with the reason", async ({ page }) => {
    await ledger(page, () => ({
      status: 422,
      body: { error: { code: "package_not_eligible", message: "This package cannot be combined with the member's current one." } },
    }));

    await page.getByRole("button", { name: "+ Assign" }).click();
    const menu = page.getByRole("dialog", { name: "Assign" });
    await chooseOption(page, menu.getByRole("combobox"), PACKAGE_ID);
    await menu.getByRole("button", { name: "Assign", exact: true }).click();

    await expect(menu).toBeVisible();
    await expect(menu.getByRole("alert")).toBeVisible();
  });
});
