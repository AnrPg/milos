import { expect, test, type Page } from "./support/test";

// P3-M4 (ADR-166): Πρόοδος › Insights. One fixed slot after the depth
// sections: findings labelled as indicators, each can be hidden (the next
// one takes its place) and shown again; before there is enough data the slot
// keeps its place with a sufficiency empty state. The API is stubbed; every
// route not listed answers an empty object. Set INSIGHTS_SHOTS_DIR to keep
// screenshots.

const SHOTS = process.env.INSIGHTS_SHOTS_DIR;

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

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
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const period = { period_start: "2026-07-30", period_end: "2026-10-21" };
const FINDINGS = [
  { ...period, rule: "sleep_prs", variant: "more_after_goal", weeks: 11, params: { ratio: 2.4, hours: 7 } },
  { ...period, rule: "time_of_day", variant: "best_part", weeks: 11, params: { part: "morning", ratio: 1.8 } },
  {
    ...period,
    rule: "cravings",
    variant: "part_and_trigger",
    weeks: 9,
    params: { part: "night", part_count: 6, total: 10, trigger: "stress", trigger_count: 5, with_trigger: 8 },
  },
  { ...period, rule: "hydration", variant: "on_goal", weeks: 11, params: { on_goal_days: 18, logged_days: 28, percent: 64 } },
];

function slot(hidden: string[], collecting = false) {
  const visible = collecting ? [] : FINDINGS.filter((finding) => !hidden.includes(finding.rule));
  return {
    state: collecting ? "collecting" : visible.length ? "insights" : "all_hidden",
    insights: visible.slice(0, 3),
    hidden_count: hidden.length,
    data_weeks: collecting ? 2 : 11,
    min_weeks: 4,
    window_weeks: 12,
    max_shown: 3,
    computed_at: "2026-10-21T02:40:00Z",
  };
}

async function common(page: Page, collecting = false) {
  const { user, token } = persona();
  const hidden: string[] = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/insights", (route) => route.fulfill(json(slot(hidden, collecting))));
  await page.route("**/api/me/insights/*/dismiss", (route) => {
    const rule = new URL(route.request().url()).pathname.split("/").at(-2) ?? "";
    hidden.push(rule);
    return route.fulfill(json(slot(hidden)));
  });
  await page.route("**/api/me/insights/restore", (route) => {
    hidden.splice(0);
    return route.fulfill(json(slot(hidden)));
  });
  return hidden;
}

test.describe("Πρόοδος insights (ADR-166)", () => {
  test("the member reads at most three findings as indicators and hides one", async ({ page }) => {
    const hidden = await common(page);
    await page.goto("/journal/progress");

    const card = page.getByRole("region", { name: "Insights" });
    await expect(card.getByText("You set PRs 2.4× more often after 7+ hours of sleep.")).toBeVisible({ timeout: 60_000 });
    await expect(card.getByText("You set PRs 1.8× more often in morning workouts.")).toBeVisible();
    await expect(card.getByText("Most of your cravings (6 of 10) come late at night, usually with stress.")).toBeVisible();
    await expect(card.getByRole("listitem")).toHaveCount(3);
    await expect(card).toContainText("From 11 weeks of data · An indicator, not medical advice.");
    if (SHOTS) {
      await card.scrollIntoViewIfNeeded();
      await card.screenshot({ path: `${SHOTS}/${test.info().project.name}-insights.png` });
    }

    await card.locator('[data-rule="sleep_prs"]').getByRole("button", { name: "Hide" }).click();
    await expect.poll(() => hidden).toEqual(["sleep_prs"]);
    await expect(card.getByText(/after 7\+ hours of sleep/)).toHaveCount(0);
    await expect(card.getByText("You reached your water goal on 18 of the 28 days you logged.")).toBeVisible();
    await expect(card.getByText("Hidden: 1")).toBeVisible();

    await card.getByRole("button", { name: "Show again" }).click();
    await expect(card.getByText("You set PRs 2.4× more often after 7+ hours of sleep.")).toBeVisible();
    await expect(card.getByText(/Hidden:/)).toHaveCount(0);
  });

  test("before four weeks of data the slot says how far along it is", async ({ page }) => {
    await common(page, true);
    await page.goto("/journal/progress");

    const card = page.getByRole("region", { name: "Insights" });
    await expect(card).toContainText("Insights appear after 4 weeks of entries (sleep, water, cravings, workouts). So far: 2 of 4.", {
      timeout: 60_000,
    });
    await expect(card).toContainText("An indicator, not medical advice.");
    await expect(card.getByRole("button", { name: "Hide" })).toHaveCount(0);
    if (SHOTS) await card.screenshot({ path: `${SHOTS}/${test.info().project.name}-collecting.png` });
  });
});
