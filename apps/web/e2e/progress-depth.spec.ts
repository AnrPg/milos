import { expect, test, type Page } from "./support/test";

// P3-M3 (ADR-165): Πρόοδος › Μυϊκή κάλυψη, Ποιότητες, Φορτίο. The member
// reads the three fixed slots under the page's range chip, a muscle opens the
// atlas on it, and the coach reads the same sections on a client's profile
// from shared entries only. The API is stubbed; every route not listed
// answers an empty object. Set DEPTH_SHOTS_DIR to keep screenshots.

const SHOTS = process.env.DEPTH_SHOTS_DIR;

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function persona(role: "member" | "coach") {
  const user = {
    id: role === "coach" ? "coach-1" : "member-1",
    nickname: role === "coach" ? "Kostas" : "Maria",
    role: role === "coach" ? "admin" : "member",
    email: `${role}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const QUALITIES = [
  "cardiorespiratory-endurance",
  "stamina",
  "strength",
  "flexibility",
  "power",
  "speed",
  "coordination",
  "agility",
  "balance",
  "accuracy",
];

function depth(range: string) {
  return {
    range,
    from: "2026-07-30",
    to: "2026-10-21",
    weeks: range === "4w" ? 4 : 12,
    sources: [],
    coverage: {
      sessions: 11,
      exercises: { recognized: 30, unrecognized: 2 },
      felt_entries: 3,
      thresholds: { medium: 3, high: 8 },
      most: [
        { id: "quadriceps", sets: 44, per_week: 3.7, level: "medium" },
        { id: "glutes", sets: 40, per_week: 3.3, level: "medium" },
        { id: "deltoid", sets: 30, per_week: 2.5, level: "low" },
      ],
      least: [
        { id: "hamstrings", sets: 4, per_week: 0.3, level: "low" },
        { id: "obliques", sets: 0, per_week: 0, level: "none" },
      ],
      balance: { push: 21, pull: 15, push_pull_ratio: 1.4, quad: 36, ham: 6, quad_ham_ratio: 6 },
    },
    qualities: {
      sessions: 11,
      felt_entries: 3,
      qualities: QUALITIES.map((id, index) => ({ id, sets: 20 - index * 2, score: (20 - index * 2) / 20, felt: id === "stamina" ? 3 : 0 })),
    },
    load: {
      acute: 1260,
      chronic: 900,
      ratio: 1.4,
      band: "above",
      sufficient: true,
      rated_sessions: 12,
      unrated_sessions: 3,
      bands: { below: 0.8, steady_to: 1.3, above_to: 1.5 },
      weeks: ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"].map(
        (week_start, index) => ({ week_start, load: 600 + index * 90, sessions: 3 }),
      ),
    },
  };
}

async function common(page: Page, role: "member" | "coach") {
  const { user, token } = persona(role);
  const depthRequests: string[] = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role,
          roles: [role],
          capabilities: role === "coach" ? { view_client_training: true } : {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/progress/depth?**", (route) => {
    const range = new URL(route.request().url()).searchParams.get("range") ?? "";
    depthRequests.push(range);
    return route.fulfill(json(depth(range)));
  });
  await page.route("**/api/org/*/staff/clients/u-1/progress-depth?**", (route) => {
    const range = new URL(route.request().url()).searchParams.get("range") ?? "";
    depthRequests.push(`client:${range}`);
    return route.fulfill(json(depth(range)));
  });
  return depthRequests;
}

test.describe("Πρόοδος depth (ADR-165)", () => {
  test("the member reads coverage, qualities and load, and a muscle opens the atlas", async ({ page }) => {
    const requests = await common(page, "member");
    await page.goto("/journal/progress");

    const coverage = page.getByRole("region", { name: "Muscle coverage" });
    await expect(coverage.getByText("1.4 : 1")).toBeVisible({ timeout: 60_000 });
    await expect(coverage.getByText("6.0 : 1")).toBeVisible();
    await expect(coverage.getByRole("link", { name: "Atlas ›" })).toHaveAttribute("href", "/journal/atlas");
    await expect(coverage).toContainText("An indication of training volume, not a target.");
    expect(requests).toContain("12w");

    const qualities = page.getByRole("region", { name: "Fitness qualities" });
    await expect(qualities.getByRole("img", { name: /Most: Cardiorespiratory endurance, Stamina/ })).toBeVisible();
    await expect(qualities).toContainText("“Felt”: Stamina");

    const load = page.getByRole("region", { name: "Training load" });
    await expect(load).toContainText("This week: 1.4× your usual");
    await expect(load.getByTestId("load-band")).toHaveText("Above usual");
    await expect(load).toContainText("3 workouts in the last 4 weeks have no RPE or duration");
    await expect(load).toContainText("not medical advice");
    if (SHOTS) {
      await coverage.scrollIntoViewIfNeeded();
      await page.screenshot({ path: `${SHOTS}/${test.info().project.name}-member.png`, fullPage: true });
    }

    // The page's range chip narrows the sections too.
    await page.getByRole("toolbar").getByRole("button", { name: /3 months/ }).click();
    await page.getByRole("menuitemradio", { name: "4 weeks" }).click();
    await expect.poll(() => requests).toContain("4w");

    await coverage.getByRole("link", { name: /Hamstrings/ }).click();
    await expect(page).toHaveURL(/\/journal\/atlas\?node=hamstrings$/, { timeout: 60_000 });
  });

  test("the coach reads a client's sections on the profile, without atlas links", async ({ page }) => {
    const requests = await common(page, "coach");
    await page.route("**/api/org/*/admin/users/u-1", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "u-1", nickname: "Eleni", avatar_url: null, role: "member", joined_at: "2026-01-10T10:00:00Z" },
            account_status: "active",
            membership: { roles: ["member"], coach_scope: "assigned" },
            available_sections: [],
            attention: [],
            operational_links: {},
          },
        }),
      ),
    );
    await page.route("**/api/org/*/admin/users/u-1/prs", (route) => route.fulfill(json({ user_id: "u-1", visibility: "coach", member: null, prs: [] })));

    await page.goto("/admin/users/u-1?tab=training");
    const panel = page.getByTestId("coach-training-depth");
    await expect(panel.getByText("1.4 : 1")).toBeVisible({ timeout: 60_000 });
    // The back link draws one arrow; the translation brings none of its own.
    await expect(page.getByRole("main").getByRole("link", { name: "Users", exact: true })).toHaveText(/^\s*←\s*Users\s*$/);
    await expect(panel).toContainText("Only from entries the client shares with the box's coaches.");
    await expect(panel.getByRole("region", { name: "Muscle coverage" }).getByRole("link")).toHaveCount(0);
    await expect(panel.getByRole("region", { name: "Training load" })).toContainText("not medical advice");
    expect(requests).toContain("client:4w");
    if (SHOTS) await panel.screenshot({ path: `${SHOTS}/${test.info().project.name}-coach.png` });

    await panel.getByRole("button", { name: "6 months" }).click();
    await expect.poll(() => requests).toContain("client:6m");
  });
});
