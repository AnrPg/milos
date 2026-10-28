import { expect, test, type Page, type Request } from "./support/test";

// ADR-216: a box has one join link per client role. The owner switches the
// box-member link and the athlete link on and off on their own; the athlete
// link carries a secret key. The visitor never picks the role. The API is
// stubbed.

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  completed_tours: ["admin", "gym"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

const organization = { id: "org-1", slug: "kypseli", name: "Box Kypseli" };

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

async function stubAdmin(page: Page) {
  const updates: Request[] = [];
  let links = { member: { enabled: true }, athlete: { enabled: false, key: null as string | null } };

  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(owner), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(owner)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          id: "m-1",
          role: "owner",
          roles: ["owner"],
          coach_scope: "all",
          capabilities: { invite_clients: "all", manage_settings: "all" },
          location_scope: { all_locations: true, location_ids: [] },
          organization: { ...organization, provider_kind: "gym", activation: "active" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null, default_locale: "el" },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/onboarding", (route) =>
    route.fulfill(json({ audience: "gym", steps: [], completed_count: 0, total: 0, finished: true, dismissed: true, tour_completed: true })),
  );
  await page.route("**/api/org/*/admin/locations**", (route) => route.fulfill(json([])));
  await page.route("**/api/org/kypseli/invitations", (route) => route.fulfill(json([])));
  await page.route("**/api/org/kypseli/join-link", (route) => {
    const request = route.request();
    if (request.method() === "PUT") {
      updates.push(request);
      const body = request.postDataJSON() as { role: "member" | "athlete"; enabled?: boolean; rotate_key?: boolean };
      if (body.role === "member") links = { ...links, member: { enabled: body.enabled ?? links.member.enabled } };
      else {
        const enabled = body.enabled ?? links.athlete.enabled;
        const key = body.rotate_key ? "fresh-key-2" : (links.athlete.key ?? (enabled ? "secret-key-1" : null));
        links = { ...links, athlete: { enabled, key } };
      }
    }
    return route.fulfill(json(links));
  });
  return updates;
}

test.describe("join links per role", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
  });

  test("the owner runs the member and athlete links side by side", async ({ page }) => {
    const updates = await stubAdmin(page);
    await page.goto("/org/kypseli/admin");
    await page.getByRole("button", { name: "Invite clients" }).first().click();
    const dialog = page.getByRole("dialog", { name: "Invite clients" });
    await dialog.getByRole("tab", { name: "Join links" }).click();

    const member = dialog.getByRole("region", { name: "Link for box members" });
    const athlete = dialog.getByRole("region", { name: "Link for athletes" });
    await expect(member.getByRole("textbox")).toHaveValue(/\/join\/kypseli$/);
    await expect(athlete).toContainText("Off.");

    await athlete.getByRole("switch", { name: "Link for athletes" }).click();
    await expect(athlete.getByRole("textbox")).toHaveValue(/\/join\/kypseli\/athlete\/secret-key-1$/);
    await expect(member.getByRole("switch")).toHaveAttribute("aria-checked", "true");
    expect(updates[0].postDataJSON()).toEqual({ role: "athlete", enabled: true });

    await athlete.getByRole("button", { name: "New athletes’ link" }).click();
    await athlete.getByRole("button", { name: "Yes, make a new one" }).click();
    await expect(athlete.getByRole("textbox")).toHaveValue(/\/athlete\/fresh-key-2$/);
    expect(updates[1].postDataJSON()).toEqual({ role: "athlete", rotate_key: true });

    await member.getByRole("switch", { name: "Link for box members" }).click();
    await expect(member).toContainText("Off.");
    await expect(athlete.getByRole("switch")).toHaveAttribute("aria-checked", "true");
  });

  test("signed out: the athlete link signs up as an athlete and comes back to it", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "invalid_refresh_token" }, 401)));
    await page.route("**/api/auth/join/kypseli/athlete/secret-key-1", (route) =>
      route.fulfill(json({ organization, role: "athlete", settings: { brand_name: "Box Kypseli", brand_logo_url: null } })),
    );

    await page.goto("/join/kypseli/athlete/secret-key-1");
    await expect(page.getByRole("heading", { name: "Join Box Kypseli" })).toBeVisible();
    await expect(page.getByText(/to join as Athlete/)).toBeVisible();
    await expect(page.getByRole("link", { name: "Create an account" })).toHaveAttribute(
      "href",
      `/register?next=${encodeURIComponent("/join/kypseli/athlete/secret-key-1")}&role=athlete`,
    );
  });

  test("signed in: the athlete link joins through its own endpoint", async ({ page }) => {
    const visitor = { ...owner, id: "visitor-1", role: "member", email: "v@example.com", memberships: [] };
    let joined: Request | null = null;
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(visitor), refresh_token: "refresh" })));
    await page.route("**/api/auth/me", (route) => route.fulfill(json(visitor)));
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));
    await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
    await page.route("**/api/auth/join/kypseli/athlete/secret-key-1", (route) =>
      route.fulfill(json({ organization, role: "athlete", settings: { brand_name: "Box Kypseli", brand_logo_url: null } })),
    );
    await page.route("**/api/memberships/join/kypseli/athlete/secret-key-1", (route) => {
      joined = route.request();
      return route.fulfill(json({ code: "membership_unavailable", error: "x" }, 409));
    });

    await page.goto("/join/kypseli/athlete/secret-key-1");
    await page.getByRole("button", { name: "Join Box Kypseli" }).click();
    await expect.poll(() => joined?.method()).toBe("POST");
  });

  test("a wrong athlete key says the link is not active", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "invalid_refresh_token" }, 401)));
    await page.route("**/api/auth/join/**", (route) =>
      route.fulfill(json({ code: "join_link_unavailable", error: "This join link is not active" }, 404)),
    );

    await page.goto("/join/kypseli/athlete/guess");
    await expect(page.getByRole("heading", { name: "This link isn’t active" })).toBeVisible();
  });
});
