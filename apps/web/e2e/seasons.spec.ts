import { expect, test, type Page } from "@playwright/test";

import { chooseDate, chooseOption } from "./support/select";

// Redesign Phase 3 M5 (ADR-167): seasons. A member finds the gym's open
// season in Box › Membership, reads it and asks for a place (and a season
// notification's link opens it straight away); staff build a season in
// Finance › Seasons and confirm a request. The API is stubbed; anything not
// stubbed answers `{}`, so the screens must cope with missing fields.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const SEASON_ID = "5e1a7c1e-0000-4000-8000-000000000001";
const ENROLLMENT_ID = "5e1a7c1e-0000-4000-8000-0000000000e1";

const isoDay = (days: number) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
};

function personaFor(id: string, nickname: string, role: "member" | "admin") {
  const user = {
    id,
    nickname,
    role,
    email: `${id}@example.com`,
    completed_tours: ["admin", "member", "athlete"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: role === "admin" ? "owner" : "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = (role: string, capabilities: Record<string, string> = {}) => ({
  role,
  roles: [role],
  capabilities,
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
});

async function common(page: Page, persona: ReturnType<typeof personaFor>, memberships: unknown[]) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
  // Box's own lists, so its other cards stay quiet.
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/executions", (route) => route.fulfill(json({ executions: [] })));
}

function memberSeason(mine: { id: string; status: string } | null) {
  return {
    id: SEASON_ID,
    title: "Hyrox prep",
    description: "Eight weeks to race day.",
    starts_on: isoDay(5),
    ends_on: isoDay(5 + 55),
    weeks: 8,
    capacity: 12,
    places_left: 3,
    price_cents: 12000,
    currency: "EUR",
    status: "published",
    coaches: [{ id: "coach-1", nickname: "Nikos" }],
    workout_count: 16,
    mine,
  };
}

test.describe("seasons", () => {
  test("a member asks for a place in an open season from Box", async ({ page }) => {
    await common(page, personaFor("member-1", "Maria", "member"), [membership("member")]);
    let mine: { id: string; status: string } | null = null;
    const requests: string[] = [];
    await page.route("**/api/org/kypseli/me/seasons", (route) => route.fulfill(json({ seasons: [memberSeason(mine)] })));
    await page.route(`**/api/org/kypseli/me/seasons/${SEASON_ID}/request`, (route) => {
      requests.push(route.request().method());
      mine = { id: ENROLLMENT_ID, status: "requested" };
      return route.fulfill(json({ season: memberSeason(mine) }));
    });

    await page.goto("/box");
    await page.getByRole("button", { name: /1 season open/ }).click();

    const sheet = page.getByRole("dialog", { name: "Hyrox prep" });
    await expect(sheet.getByText("8 weeks")).toBeVisible();
    await expect(sheet.getByText("€120.00")).toBeVisible();
    await expect(sheet.getByText("3 places left")).toBeVisible();
    await expect(sheet.getByText("Nikos")).toBeVisible();
    await expect(sheet.getByText("16 workouts")).toBeVisible();

    await sheet.getByRole("button", { name: "Ask for a place" }).click();
    await expect(sheet.getByText("Request pending")).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Withdraw request" })).toBeVisible();
    expect(requests).toEqual(["POST"]);

    // Escape closes the sheet (the dev tools badge sits over the footer's left button on phones).
    await page.keyboard.press("Escape");
    await expect(sheet).toHaveCount(0);
    await expect(page.getByRole("button", { name: /Hyrox prep\s*Request pending/ })).toBeVisible();
  });

  test("a season notification's link opens the season in Box", async ({ page }) => {
    await common(page, personaFor("member-1", "Maria", "member"), [membership("member")]);
    await page.route("**/api/org/kypseli/me/seasons", (route) =>
      route.fulfill(json({ seasons: [memberSeason({ id: ENROLLMENT_ID, status: "active" })] })),
    );

    await page.goto(`/box?season=${SEASON_ID}`);
    const sheet = page.getByRole("dialog", { name: "Hyrox prep" });
    await expect(sheet.getByText("You're in")).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Ask for a place" })).toHaveCount(0);
    // The header × and the footer button both close it.
    await sheet.getByRole("button", { name: "Close" }).first().click();
    await expect(page).not.toHaveURL(/season=/);
  });

  test("Box shows no season line while the gym has none", async ({ page }) => {
    await common(page, personaFor("member-1", "Maria", "member"), [membership("member")]);
    await page.goto("/box");
    await expect(page.getByText("Membership", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: /season/i })).toHaveCount(0);
  });

  test("staff build a season and confirm a request in Finance › Seasons", async ({ page }) => {
    await common(page, personaFor("owner-1", "Apostolos", "admin"), [
      membership("owner", { view_package_catalog: "all", manage_packages: "all", take_payments: "all", manage_memberships: "all" }),
    ]);
    let detail = {
      ...memberSeason(null),
      mine: undefined,
      coach_ids: ["coach-1"],
      membership_package_id: null,
      programme: [{ day: 0, workout_id: "w-1" }],
      welcome_message: "Welcome!",
      channel_id: null,
      counts: { active: 0, requested: 1, waitlisted: 0 },
      enrollments: [
        { id: ENROLLMENT_ID, user_id: "member-1", nickname: "Maria", status: "requested", requested_at: new Date().toISOString() },
      ],
    };
    const created: unknown[] = [];
    const confirmed: string[] = [];
    await page.route("**/api/org/kypseli/admin/finance/package-catalog", (route) => route.fulfill(json({ types: [], modules: [] })));
    await page.route("**/api/org/kypseli/admin/workouts", (route) =>
      route.fulfill(json({ workouts: [{ id: "w-1", title: "Engine 1", type: "for_time", status: "published", sections: [], available_scale_levels: [] }] })),
    );
    await page.route("**/api/org/kypseli/admin/seasons", (route) => {
      if (route.request().method() === "POST") {
        created.push(route.request().postDataJSON());
        return route.fulfill(json({ season: { ...detail, id: "new-season", title: "Strong winter", status: "draft", enrollments: [] } }, 201));
      }
      return route.fulfill(json({ seasons: [detail], coach_candidates: [{ id: "coach-1", nickname: "Nikos" }] }));
    });
    await page.route(`**/api/org/kypseli/admin/seasons/${SEASON_ID}`, (route) => route.fulfill(json({ season: detail })));
    await page.route(`**/api/org/kypseli/admin/season-enrollments/${ENROLLMENT_ID}/confirm`, (route) => {
      confirmed.push(ENROLLMENT_ID);
      detail = {
        ...detail,
        counts: { active: 1, requested: 0, waitlisted: 0 },
        enrollments: [{ ...detail.enrollments[0], status: "active" }],
      };
      return route.fulfill(json({ season: detail }));
    });

    await page.goto("/org/kypseli/admin/finance?tab=seasons");
    const row = page.getByRole("button", { name: /Hyrox prep/ });
    await expect(row).toContainText("0/12 in");
    await expect(row).toContainText("1 request");
    await row.click();

    await expect(page.getByRole("textbox", { name: "Title" })).toHaveValue("Hyrox prep");
    await expect(page.getByRole("combobox", { name: "Workout" })).toHaveAttribute("data-value", "w-1");
    await expect(page.getByRole("button", { name: "Nikos" })).toHaveAttribute("aria-pressed", "true");
    await page.getByRole("button", { name: "Confirm" }).click();
    await expect(page.getByText("Participants · 1/12")).toBeVisible();
    await expect(page.getByRole("button", { name: "Remove", exact: true })).toBeVisible();
    // Once someone is confirmed the schedule is locked.
    await expect(page.getByText("Start date, weeks and programme lock once someone is confirmed.")).toBeVisible();
    expect(confirmed).toEqual([ENROLLMENT_ID]);

    await page.getByRole("button", { name: "Close" }).click();
    await page.getByRole("button", { name: "New season" }).click();
    await page.getByRole("textbox", { name: "Title" }).fill("Strong winter");
    await chooseDate(page, page.getByLabel("Starts on"), isoDay(10));
    await page.getByRole("button", { name: "Add workout" }).click();
    await chooseOption(page, page.getByRole("combobox", { name: "Workout" }), "w-1");
    await page.getByRole("button", { name: "Save draft" }).click();

    await expect.poll(() => created.length).toBe(1);
    expect(created[0]).toMatchObject({
      title: "Strong winter",
      starts_on: isoDay(10),
      weeks: 6,
      capacity: 12,
      status: "draft",
      programme: [{ day: 0, workout_id: "w-1" }],
    });
    await expect(page).toHaveURL(/season=new-season/);
  });
});
