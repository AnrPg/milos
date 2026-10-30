import { expect, test, type Page, type Request } from "./support/test";
import { chooseDate } from "./support/select";

// ADR-276: on a box member's profile (Finance tab) staff edits stay a draft
// until «Save». The save bar shows only while something changed, with undo,
// redo, cancel and save; leaving the tab with unsaved edits asks first; a
// save sends only the changed fields. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const isoDay = (days: number) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
};

async function asOwner(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Olga",
    role: "member",
    email: "owner@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_billing: "all", take_payments: "all", manage_memberships: "all" },
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  };

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "staff");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

test.describe("admin profile save bar", () => {
  test("staff edit the membership as a draft, undo and redo, are asked before leaving the tab, and save only what changed", async ({ page }) => {
    const server = { status: "trial", starts_on: isoDay(-2), expires_on: null as string | null };
    const patches: Array<Record<string, unknown>> = [];
    await asOwner(page);
    await page.route("**/api/org/box1/admin/users/u-2", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "u-2", nickname: "Tolaras", avatar_url: null, role: "member", joined_at: "2026-01-10T00:00:00Z" },
            account_status: "active",
            membership: { roles: ["member"], coach_scope: "own" },
            available_sections: ["overview", "finance"],
            attention: [],
            operational_links: {},
          },
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/users/u-2/finance", (route) =>
      route.fulfill(
        json({
          user_id: "u-2",
          available: true,
          summary: { credit_balance: 0, current_status: { state: server.status }, package_relationship: {}, outstanding_items: [], effective_entitlement: null },
          details: {
            membership: { id: "m-2", ...server, leaving_on: null },
            package_subscriptions: [],
            referral_claims: [],
            referred_members: [],
            referral_rewards: [],
          },
          drill_down: null,
          operational_links: {},
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/finance/members/u-2", (route) => {
      const body = bodyOf(route.request());
      patches.push(body);
      Object.assign(server, body);
      return route.fulfill(json({ membership: server }));
    });

    await page.goto("/admin/users/u-2?tab=finance");
    // ADR-274: the status is worked out from payments, so the draft edits the dates.
    const starts = page.getByTestId("membership-starts_on");
    const expires = page.getByTestId("membership-expires_on");
    const bar = page.getByTestId("profile-save-bar");
    const count = page.getByTestId("profile-save-bar-count");
    await expect(starts).toHaveAttribute("data-value", isoDay(-2));
    await expect(bar).toHaveCount(0);

    await chooseDate(page, starts, isoDay(-1));
    await expect(count).toHaveText("1 unsaved change");
    await expect(page.getByTestId("changed-mark")).toHaveCount(1);
    await chooseDate(page, expires, isoDay(30));
    await expect(count).toHaveText("2 unsaved changes");
    expect(patches).toHaveLength(0);

    await bar.getByRole("button", { name: "Undo" }).click();
    await expect(count).toHaveText("1 unsaved change");
    await expect(expires).toHaveAttribute("data-value", "");
    await bar.getByRole("button", { name: "Redo" }).click();
    await expect(expires).toHaveAttribute("data-value", isoDay(30));

    // Leaving the tab with unsaved edits asks first; staying keeps them.
    await page.getByRole("tab", { name: "Overview" }).click();
    const dialog = page.getByTestId("unsaved-changes-dialog");
    await expect(dialog).toBeVisible();
    await dialog.getByRole("button", { name: "Stay here" }).click();
    await expect(dialog).toHaveCount(0);
    await expect(count).toHaveText("2 unsaved changes");

    await page.getByTestId("profile-save-bar-save").click();
    await expect(bar).toContainText("Changes saved.");
    expect(patches).toEqual([{ starts_on: isoDay(-1), expires_on: isoDay(30) }]);
    await expect(starts).toHaveAttribute("data-value", isoDay(-1));

    // «Cancel» drops the draft and goes back to what was saved.
    await chooseDate(page, starts, isoDay(-3));
    await bar.getByRole("button", { name: "Cancel" }).click();
    await expect(starts).toHaveAttribute("data-value", isoDay(-1));
    await expect(count).toHaveCount(0);

    // Discarding on the way out leaves the tab without saving.
    await chooseDate(page, starts, isoDay(-3));
    await page.getByRole("tab", { name: "Overview" }).click();
    await page.getByTestId("unsaved-changes-dialog").getByRole("button", { name: "Discard" }).click();
    await expect(page).toHaveURL(/tab=overview/);
    expect(patches).toHaveLength(1);
  });

  test("roles on the Account tab are a draft saved with the same bar", async ({ page }) => {
    let roles = ["member"];
    const puts: unknown[] = [];
    await asOwner(page);
    await page.route("**/api/org/box1/admin/users/u-3", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "u-3", nickname: "Nikos", avatar_url: null, role: "member", joined_at: "2026-01-10T00:00:00Z" },
            account_status: "active",
            membership: { roles, coach_scope: "own", location_scope: { all_locations: true, location_ids: [] } },
            available_sections: ["overview", "admin_actions"],
            attention: [],
            operational_links: {},
          },
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/users/u-3/roles", (route) => {
      const body = bodyOf(route.request());
      puts.push(body);
      roles = body.roles;
      return route.fulfill(json({ membership: { roles, coach_scope: "own" } }));
    });

    await page.goto("/admin/users/u-3?tab=account");
    const count = page.getByTestId("profile-save-bar-count");
    const coach = page.getByRole("button", { name: "Coach", exact: true });
    await coach.click();
    await expect(coach).toHaveAttribute("aria-pressed", "true");
    await expect(count).toHaveText("1 unsaved change");
    await page.getByTestId("profile-save-bar").getByRole("button", { name: "Undo" }).click();
    await expect(coach).toHaveAttribute("aria-pressed", "false");
    await page.getByTestId("profile-save-bar").getByRole("button", { name: "Redo" }).click();
    await expect(coach).toHaveAttribute("aria-pressed", "true");
    expect(puts).toEqual([]);

    await page.keyboard.press("Control+s");
    await expect.poll(() => puts).toEqual([{ roles: ["coach", "member"] }]);
    await expect(page.getByTestId("profile-save-bar")).toContainText("Changes saved.");
  });
});
