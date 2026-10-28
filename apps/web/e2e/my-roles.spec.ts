import { expect, test, type Page, type Request } from "./support/test";

// ADR-219: Settings › «Οι ρόλοι μου». An owner adds the coach role to
// themselves and stays owner; a member, with nothing below them, has no such
// section. The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function persona(roles: string[]) {
  const user = {
    id: "owner-1",
    nickname: "Eleni",
    display_name: "Eleni",
    handle: "eleni",
    role: "member",
    email: "eleni@example.com",
    email_verified: true,
    profile_count: 1,
    profile_limit: 3,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: roles[0], settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const membership = (held: string[]) => ({
    role: held[0],
    roles: held,
    capabilities: {},
    location_scope: null,
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC", activation: "active" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  });
  return { user, token: `stub.${payload}.signature`, membership };
}

async function signedIn(page: Page, roles: string[]) {
  const { user, token, membership } = persona(roles);
  let held = roles;
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "client");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership(held)])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [], unread_count: 0 })));
  return {
    // The stub API keeps what was saved, as the real one does.
    save(next: string[]) {
      held = next;
    },
  };
}

test.describe("Settings › My roles", () => {
  test("an owner adds coach to themselves and stays owner", async ({ page }) => {
    const api = await signedIn(page, ["owner"]);
    const saved: unknown[] = [];
    await page.route("**/api/org/box1/me/roles", (route) => {
      const body = (route.request() as Request).postDataJSON() as { roles: string[] };
      saved.push(body);
      api.save(body.roles);
      return route.fulfill(json({ membership: { user_id: "owner-1", role: "owner", roles: body.roles } }));
    });

    await page.goto("/me/settings#my-roles");
    const group = page.getByRole("group", { name: "My roles in this box" });
    await expect(group.getByRole("button", { name: "Owner" })).toBeDisabled();
    await expect(group.getByRole("button", { name: "Owner" })).toHaveAttribute("aria-pressed", "true");

    await group.getByRole("button", { name: "Coach" }).click();
    await page.getByRole("button", { name: "Save roles" }).click();

    await expect.poll(() => saved).toEqual([{ roles: ["owner", "coach"] }]);
    await expect(group.getByRole("button", { name: "Coach" })).toHaveAttribute("aria-pressed", "true");
    await expect(group.getByRole("button", { name: "Owner" })).toHaveAttribute("aria-pressed", "true");
  });

  test("a member has no roles below them, so the section is hidden", async ({ page }) => {
    await signedIn(page, ["member"]);
    await page.goto("/me/settings");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.locator("#my-roles")).toHaveCount(0);
  });
});
