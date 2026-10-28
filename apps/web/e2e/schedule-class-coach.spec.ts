import { expect, test, type Page, type Request } from "./support/test";
import { chooseOption } from "./support/select";

// ADR-100 / ADR-099: a class's coach is anyone holding the coach role, so an
// owner who also coaches can put themselves on a class or a series. The API
// is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const staff = [
  { user_id: "owner-1", nickname: "Olga", role: "owner", roles: ["owner", "coach"] },
  { user_id: "admin-1", nickname: "Alex", role: "admin", roles: ["admin"] },
  { user_id: "coach-1", nickname: "Nikos", role: "coach", roles: ["coach"] },
];

async function asOwnerWhoCoaches(page: Page) {
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
    roles: ["owner", "coach"],
    capabilities: { manage_schedule: "all", run_classes: "all" },
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
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [] })),
  );
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
}

test.describe("Schedule › class coach", () => {
  test("an owner who also coaches can coach their own series", async ({ page }) => {
    await asOwnerWhoCoaches(page);
    let created: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/series", (route) => {
      created = bodyOf(route.request());
      return route.fulfill(json({ series: { id: "series-1", occurrence_count: 4, location_id: null } }, 201));
    });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: "New recurring class" }).click();

    const coach = page.getByRole("dialog").getByRole("combobox", { name: "Coach" });
    await coach.click();
    const options = page.getByRole("listbox").getByRole("option");
    await expect(options).toHaveText(["No coach", "Nikos", "Olga"]);
    await page.keyboard.press("Escape");

    await chooseOption(page, coach, "owner-1");
    await page.getByRole("dialog").getByRole("button", { name: "Create recurring class" }).click();
    await expect.poll(() => created?.coach_user_id).toBe("owner-1");
  });
});
