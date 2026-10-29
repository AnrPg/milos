import { expect, test, type Page, type Request } from "./support/test";
import { chooseOption } from "./support/select";

// ADR-220, staff side: on a box member's profile (Finance tab) staff see the
// member's own automatic renewal, can change it for them (ADR-276: saved
// with the tab's «Save», not on the click), mark them as
// leaving (end of the paid period, today or a date) and undo it. The API is
// stubbed; every route not listed answers an empty object.

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

test.describe("member leaving (staff)", () => {
  test("staff turn renewal off for a member, mark them as leaving today and undo it", async ({ page }) => {
    const state = { autoRenew: true, changedBy: null as string | null, leavingOn: null as string | null };
    const calls: Array<{ method: string; path: string; body: Record<string, unknown> }> = [];
    await asOwner(page);
    await page.route("**/api/org/box1/admin/users/u-2", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "u-2", nickname: "Kostas", avatar_url: null, role: "member", joined_at: "2026-01-10T00:00:00Z" },
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
          summary: { credit_balance: 0, current_status: { state: "active" }, package_relationship: {}, outstanding_items: [], effective_entitlement: null },
          details: {
            membership: {
              id: "m-2",
              status: state.leavingOn ? "cancelled" : "active",
              starts_on: isoDay(-40),
              expires_on: state.leavingOn,
              leaving_on: state.leavingOn,
              left_by: state.leavingOn ? "staff" : null,
              leave_reason: state.leavingOn ? "Moved" : null,
            },
            package_subscriptions: [
              {
                id: "sub-1",
                status: "active",
                package_name: "Unlimited monthly",
                starts_on: isoDay(-40),
                ends_on: state.autoRenew ? null : isoDay(20),
                auto_renew: state.autoRenew,
                renewal_changed_by: state.changedBy,
                renewal_changed_at: state.changedBy ? `${isoDay(0)}T10:00:00Z` : null,
              },
            ],
            referral_claims: [],
            referred_members: [],
            referral_rewards: [],
          },
          drill_down: null,
          operational_links: {},
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/finance/members/u-2/**", (route) => {
      const request = route.request();
      const path = new URL(request.url()).pathname;
      calls.push({ method: request.method(), path, body: request.method() === "DELETE" ? {} : bodyOf(request) });
      if (path.endsWith("/auto-renew")) {
        state.autoRenew = bodyOf(request).auto_renew;
        state.changedBy = "staff";
        return route.fulfill(json({ package_subscription: {} }));
      }
      if (request.method() === "POST") {
        state.leavingOn = isoDay(0);
        state.autoRenew = false;
        return route.fulfill(json({ membership: {}, leaving_on: state.leavingOn, voided_invoice_count: 1, outstanding_cents: 6000 }));
      }
      state.leavingOn = null;
      state.autoRenew = true;
      return route.fulfill(json({ membership: {} }));
    });

    await page.goto("/admin/users/u-2?tab=finance");
    const card = page.getByTestId("admin-membership-leaving");
    const renewal = card.getByRole("switch", { name: /Automatic renewal · Unlimited monthly/ });
    await expect(renewal).toBeChecked();
    await expect(card.getByText("The box member can turn it off in the app.", { exact: false })).toBeVisible();

    await renewal.click();
    await expect(renewal).not.toBeChecked();
    await expect(page.getByTestId("profile-save-bar-count")).toHaveText("1 unsaved change");
    expect(calls).toHaveLength(0);
    await page.getByTestId("profile-save-bar-save").click();
    await expect(card.getByText("Last changed by staff", { exact: false })).toBeVisible();
    await expect(page.getByTestId("profile-save-bar")).toContainText("Changes saved.");
    expect(calls[0]).toMatchObject({ method: "PUT", path: "/api/org/box1/admin/finance/members/u-2/subscriptions/sub-1/auto-renew", body: { auto_renew: false } });

    await card.getByTestId("admin-leave-open").click();
    await expect(card.getByText("Anything already used stays owed until it is paid.", { exact: false })).toBeVisible();
    await chooseOption(page, card.getByRole("combobox"), "today");
    await card.getByPlaceholder("Reason (optional)").fill("Moved");
    await card.getByTestId("admin-leave-confirm").click();
    expect(calls[1]).toMatchObject({ method: "POST", path: "/api/org/box1/admin/finance/members/u-2/leave", body: { leaving_on: isoDay(0), reason: "Moved" } });

    await expect(card.getByTestId("admin-leaving-on")).toContainText("marked by staff · Moved");
    await expect(card.getByRole("switch")).toBeDisabled();

    await card.getByRole("button", { name: "Undo leaving" }).click();
    await expect(card.getByTestId("admin-leave-open")).toBeVisible();
    expect(calls[2]).toMatchObject({ method: "DELETE" });
  });
});
