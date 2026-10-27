import { expect, test, type Page, type Request } from "./support/test";

// Phase 3 P3-M8 (ADR-170): an independent coach's Box speaks in the coach's
// words (next session with the online call link, Sessions · Messages, the
// session package), and any member can open their own practice from Me.
// The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "nikos", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "nikos" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const coachMembership = {
  role: "member",
  roles: ["member"],
  capabilities: {},
  organization: { id: "org-coach", slug: "nikos", name: "Nikos P.", provider_kind: "coach" },
  settings: { brand_name: "Nikos P.", brand_logo_url: null, brand_primary_color: null },
};

async function common(page: Page) {
  const { user, token } = persona();
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => window.localStorage.setItem("palee:selected-organization-slug", "nikos"));
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([coachMembership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
}

test.describe("Solo coach", () => {
  test("the coach's Box shows the next online session with its call link", async ({ page }) => {
    await common(page);
    const startsAt = new Date(Date.now() + 26 * 3600_000).toISOString();
    await page.route("**/api/org/nikos/me/appointments", (route) =>
      route.fulfill(
        json({
          appointments: [
            {
              id: "booking-1",
              slot_id: "slot-1",
              status: "booked",
              slot: {
                id: "slot-1",
                kind: "pt_session",
                format: "one_to_one",
                starts_at: startsAt,
                duration_minutes: 45,
                mode: "online",
                meeting_url: "https://meet.example.com/nikos-maria",
              },
            },
          ],
        }),
      ),
    );

    await page.goto("/box");
    await expect(page.getByText("Nikos P. · Personal coach")).toBeVisible();
    await expect(page.getByText("Personal session · Online · 45 min")).toBeVisible();
    await expect(page.getByRole("link", { name: "Join call" })).toHaveAttribute("href", "https://meet.example.com/nikos-maria");
    const actions = page.getByRole("navigation", { name: "Coach actions" });
    await expect(actions.getByRole("link", { name: "Messages" })).toBeVisible();
    await expect(page.getByText("No session package yet. Ask your coach.")).toBeVisible();
  });

  test("a member opens their own practice from Me", async ({ page }) => {
    await common(page);
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));
    await page.route("**/api/public/platform-plans?**", (route) =>
      route.fulfill(
        json({
          plans: [
            {
              code: "solo_coach",
              audience: "coach",
              name: "Solo coach",
              description: null,
              limits: { staff_seats: 2, active_clients: 50 },
              monthly_price_cents: 1900,
              annual_price_cents: 19000,
              currency: "EUR",
              price_status: "placeholder",
              trial_days: 30,
              is_default: true,
              public: true,
              active: true,
              position: 0,
            },
          ],
        }),
      ),
    );
    let created: Record<string, unknown> | null = null;
    await page.route("**/api/coach-practices", (route) => {
      created = bodyOf(route.request());
      return route.fulfill(json({ organization_id: "org-new", slug: "maria-coaching", name: "Maria Coaching", club_name: "Team Maria" }, 201));
    });

    await page.goto("/me/coach-practice");
    await expect(page.getByText("30 days free")).toBeVisible();
    // A placeholder price is never shown to customers.
    await expect(page.getByText("Pricing will be announced before the trial ends")).toBeVisible();
    await expect(page.getByText("€19")).toHaveCount(0);

    await page.getByLabel("Practice name").fill("Maria Coaching");
    await expect(page.getByLabel("Team club name")).toHaveValue("Team Maria");
    // The stub has no membership for the new gym, so its admin may bounce on;
    // what matters is that the app went there.
    const opened = page.waitForURL(/\/org\/maria-coaching\/admin/, { waitUntil: "commit" });
    await page.getByRole("button", { name: "Start my practice" }).click();
    await opened;
    expect(created).toMatchObject({ name: "Maria Coaching", team_name: "Team Maria" });
  });
});
