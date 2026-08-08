import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

const pages = [
  { path: "/about", heading: /trainingjournal/i },
  { path: "/register", heading: /create your account/i },
  {
    path: "/schedule",
    heading: /^schedule$/i,
    user: { id: "member-1", nickname: "Maya Member", role: "member" },
  },
  {
    path: "/admin",
    heading: /ada admin/i,
    user: { id: "admin-1", nickname: "Ada Admin", role: "admin" },
  },
];

async function analyzeAccessibility(page: Page) {
  try {
    return await new AxeBuilder({ page }).analyze();
  } catch (error) {
    if (error instanceof Error && error.message.includes("Execution context was destroyed")) {
      await page.waitForLoadState("networkidle");
      await page.waitForTimeout(500);
      return new AxeBuilder({ page }).analyze();
    }

    throw error;
  }
}

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(
    JSON.stringify({
      sub: user.id,
      role: user.role,
      memberships: [{ organization_slug: "demo-gym" }],
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");

  return `stub.${payload}.signature`;
}

async function stubApi(page: Page, user?: { id: string; nickname: string; role: string }) {
  const currentUser =
    user &&
    ({
      ...user,
      email: `${user.id}@example.com`,
      preferred_locale: "en",
      vendor: false,
      memberships: [{ organization_slug: "demo-gym", role: user.role, settings: {} }],
    } as const);
  const accessToken = user ? tokenFor(user) : null;

  await page.route("**/api/auth/refresh", (route) =>
    currentUser
      ? route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ access_token: accessToken, refresh_token: "refresh" }),
        })
      : route.fulfill({ status: 401, contentType: "application/json", body: "{}" }),
  );
  await page.route("**/api/auth/me", (route) =>
    currentUser
      ? route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(currentUser) })
      : route.fulfill({ status: 401, contentType: "application/json", body: "{}" }),
  );
  await page.route("**/api/theme", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "{}" }),
  );
  await page.route("**/api/org/*/schedule?**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ start_date: "2026-08-08", end_date: "2026-08-15", days: 7, class_types: [], slots: [] }),
    }),
  );
  await page.route("**/api/memberships", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          role: currentUser?.role ?? "member",
          organization: { slug: "demo-gym", name: "Demo Gym", settings: {} },
        },
      ]),
    }),
  );
  await page.route("**/api/org/*/me/finance", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        membership: null,
        active_package_subscription: null,
        invoices: [],
        payments: [],
        credit_balance: 0,
        total_outstanding_balance_cents: 0,
        referral_credits: [],
        promotion_redemptions: [],
        available_packages: [],
      }),
    }),
  );
  await page.route("**/api/notifications/push-config", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ configured: false, public_key: null, subscribed: false }),
    }),
  );
  await page.route("**/api/notifications?**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ notifications: [] }) }),
  );
  await page.route("**/api/org/*/me/threads/unread-count", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ unread_count: 0 }) }),
  );
  await page.route(/\/api(?:\/org\/[^/]+)?\/landing$/, (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        role: currentUser?.role ?? "member",
        admin_metrics: { member_count: 0, total_outstanding_cents: 0, pending_referral_approvals: 0, classes_today: 0 },
        gamification: {
          settings: { weekly_workout_target: 3, streak_shield_reset_day: null, leaderboard_enabled: true },
          stats: {
            current_streak: 0,
            longest_streak: 0,
            total_workouts: 0,
            total_prs: 0,
            current_streak_shields: 0,
            consistency_score: 0,
            motivation_score: 0,
            perseverance_score: 0,
            advancement_count: 0,
            last_workout_at: null,
          },
          preferences: null,
          badges: [],
          active_challenges: [],
          leaderboard: { visible: true, opted_in: false, weekly: [], monthly: [] },
        },
        coach_notes: [],
        membership: null,
        recent_executions: [],
      }),
    }),
  );
  await page.route("**/api/org/*/admin/finance/summary", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ totals: {} }) }),
  );
  await page.route("**/api/org/*/admin/finance/queues?**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ queues: {} }) }),
  );
  await page.route("**/api/org/*/admin/analytics/summary?**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ coaching: {} }) }),
  );
  await page.route("**/api/org/*/admin/challenges", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ challenges: [] }) }),
  );
}

for (const pageSpec of pages) {
  test(`${pageSpec.path} renders without detectable accessibility violations`, async ({ page }) => {
    await stubApi(page, pageSpec.user);

    await page.goto(pageSpec.path);
    await expect(page.getByRole("heading", { name: pageSpec.heading }).first()).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);

    const accessibility = await analyzeAccessibility(page);

    expect(accessibility.violations).toEqual([]);
  });
}
