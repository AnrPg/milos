import { expect, test, type Page, type Request } from "@playwright/test";

// Redesign Phase 2 M11 (ADR-159, plan board 14): Ημερολόγιο › Ευεξία. The
// first visit asks for the health-data consent and which items to show, one
// tap adds a glass with undo, Λιγούρα opens from Νέα καταχώρηση and from the
// «How did it go?» notification, the coach's plan shows hand portions and
// never calories, and Customise saves the tile order. The API is stubbed;
// every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const pad = (value: number) => String(value).padStart(2, "0");
const now = new Date();
const today = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    completed_tours: ["admin", "member", "athlete"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const preferences = {
  glass_ml: 250,
  water_goal_ml: 2000,
  sleep_goal_minutes: 450,
  hidden_items: [] as string[],
  item_order: ["water", "sleep", "meals", "plan", "mood"],
  water_reminder: false,
};

const daySummary = (date: string, waterMl = 0) => ({
  date,
  water: { ml: waterMl, count: waterMl / 250, glass_ml: 250, goal_ml: 2000, status: waterMl ? "partial" : "none" },
  sleep: { status: "none", goal_minutes: 450, nap_minutes: 0 },
  meals: { status: "partial", count: 1, portions: { protein: 2, veg: 1 } },
  cravings: { status: "none", count: 0 },
});

const craving = {
  id: "craving-1",
  intensity: 7,
  triggers: ["stress"],
  outcome: null,
  note: null,
  occurred_at: new Date(Date.now() - 25 * 60_000).toISOString(),
  occurred_on: today,
  occurred_tz: "UTC",
  journal_visibility: "private",
};

function overview(options: { consented?: boolean; waterMl?: number; withPlan?: boolean } = {}) {
  return {
    from: today,
    to: today,
    consented: options.consented ?? true,
    preferences,
    days: [daySummary(today, options.waterMl ?? 0)],
    entries: [
      {
        id: "meal-1",
        kind: "meal",
        source: "manual",
        corrected: false,
        occurred_at: new Date().toISOString(),
        occurred_on: today,
        occurred_tz: "UTC",
        journal_visibility: "private",
        value: { slot: "breakfast", plan_fit: "on_plan", portions: { protein: 2, veg: 1 } },
      },
    ],
    cravings: [craving],
    plans: options.withPlan
      ? [{ id: "plan-1", organization_id: "org-1", title: "Cut, autumn", meal_slots: ["breakfast", "lunch", "dinner", "snack"], portions: { protein: 4, carbs: 3, veg: 4, fat: 2 } }]
      : [],
    photos: {},
    photo_capabilities: { content_types: ["image/jpeg", "image/png", "image/webp"], max_bytes: 10_000_000 },
    week: { water_days_logged: 1, water_days_on_goal: 0, nights_logged: 0, nights_on_goal: 0, meal_days_logged: 1, cravings: 1 },
  };
}

async function common(page: Page, wellness: () => unknown) {
  const { user, token } = persona();
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
  await page.route("**/api/wellbeing/injuries", (route) => route.fulfill(json({ injuries: [] })));
  await page.route("**/api/wellbeing/check-ins?**", (route) => route.fulfill(
      json({
        check_ins: [],
        questions: ["sleep", "energy", "mood", "stress", "body"].map((key) => ({ key, min: 1, max: 4 })),
      }),
    ),
  );
  await page.route("**/api/me/wellness?**", (route) =>
    route.request().method() === "GET" ? route.fulfill(json(wellness())) : route.fulfill(json({ erased: {} })),
  );
}

const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

test.describe("Ευεξία", () => {
  test("the first visit asks for consent and which items to show", async ({ page }) => {
    let consented = false;
    await common(page, () => overview({ consented }));
    const consent = page.waitForRequest((request) => request.url().includes("/me/body/consents/health_data") && request.method() === "PUT");
    const saved = page.waitForRequest((request) => request.url().endsWith("/me/wellness/preferences") && request.method() === "PUT");
    await page.route("**/api/me/wellness/preferences", (route) => {
      consented = true;
      return route.fulfill(json({ preferences }));
    });

    await page.goto("/journal/wellbeing");
    await expect(page.getByRole("heading", { name: "Your water, sleep, meals and cravings" })).toBeVisible();
    await page.getByRole("switch", { name: "Mood" }).click();
    await page.getByRole("button", { name: "Agree and start" }).click();

    await consent;
    expect(bodyOf(await saved)).toEqual({ hidden_items: ["mood"] });
    await expect(page.getByRole("button", { name: "+1 glass" })).toBeVisible();
  });

  test("one tap adds a glass and the toast can undo it", async ({ page }) => {
    let waterMl = 500;
    await common(page, () => overview({ waterMl }));
    await page.route("**/api/me/wellness/entries", (route) => {
      waterMl += 250;
      return route.fulfill(
        json({
          entry: {
            id: "water-3",
            kind: "water",
            source: "manual",
            corrected: false,
            occurred_at: new Date().toISOString(),
            occurred_on: today,
            occurred_tz: "UTC",
            journal_visibility: "private",
            value: { ml: 250 },
          },
        }),
      );
    });
    const removed = page.waitForRequest((request) => request.url().endsWith("/me/wellness/entries/water-3") && request.method() === "DELETE");
    await page.route("**/api/me/wellness/entries/water-3", (route) => {
      waterMl -= 250;
      return route.fulfill({ status: 204, body: "" });
    });

    await page.goto("/journal/wellbeing");
    await expect(page.getByText("2 of 8 glasses")).toBeVisible();
    const logged = page.waitForRequest((request) => request.url().endsWith("/me/wellness/entries") && request.method() === "POST");
    await page.getByRole("button", { name: "+1 glass" }).click();
    expect(bodyOf(await logged)).toMatchObject({ kind: "water", value: { ml: 250 } });
    await expect(page.getByText("Added a glass (250 ml)")).toBeVisible();
    await expect(page.getByText("3 of 8 glasses")).toBeVisible();

    await page.getByRole("button", { name: "Undo" }).click();
    await removed;
    await expect(page.getByText("2 of 8 glasses")).toBeVisible();
  });

  test("Νέα καταχώρηση › Λιγούρα opens the sheet and saves without an outcome", async ({ page }) => {
    await common(page, () => overview());
    const logged = page.waitForRequest((request) => request.url().endsWith("/me/wellness/cravings") && request.method() === "POST");
    await page.route("**/api/me/wellness/cravings", (route) => route.fulfill(json({ craving })));

    await page.goto("/journal/wellbeing?craving=new");
    const sheet = page.getByRole("dialog", { name: "Craving" });
    await expect(sheet).toBeVisible();
    await expect(sheet.getByText("Only you see this.", { exact: false })).toBeVisible();
    await sheet.getByRole("button", { name: "8", exact: true }).click();
    await sheet.getByRole("button", { name: "Boredom" }).click();
    await sheet.getByRole("button", { name: "Save" }).click();

    const body = bodyOf(await logged);
    expect(body).toMatchObject({ intensity: 8, triggers: ["boredom"] });
    expect(body.outcome ?? "ongoing").toBe("ongoing");
    await expect(sheet).toBeHidden();
  });

  test("«How did it go?» opens the open craving and records the outcome", async ({ page }) => {
    await common(page, () => overview());
    const updated = page.waitForRequest((request) => request.url().endsWith("/me/wellness/cravings/craving-1") && request.method() === "PATCH");
    await page.route("**/api/me/wellness/cravings/craving-1", (route) => route.fulfill(json({ craving: { ...craving, outcome: "resisted" } })));

    await page.goto("/journal/wellbeing?craving=craving-1");
    const sheet = page.getByRole("dialog");
    await expect(sheet).toBeVisible();
    await sheet.getByRole("radio", { name: "I got past it" }).click();
    await sheet.getByRole("button", { name: "Save" }).click();

    expect(bodyOf(await updated)).toMatchObject({ outcome: "resisted" });
  });

  test("the coach's plan shows hand portions and never calories", async ({ page }) => {
    await common(page, () => overview({ withPlan: true }));
    await page.goto("/journal/wellbeing");

    await expect(page.getByText("Nutrition · Cut, autumn")).toBeVisible();
    await expect(page.getByLabel("Protein (palm)")).toBeVisible();
    await page.getByRole("button", { name: "Show numbers" }).click();
    await expect(page.getByText("2 of 4").first()).toBeVisible();
    await expect(page.getByText(/kcal|calorie/i)).toHaveCount(0);
  });

  test("Customise moves a tile, turns one off and keeps its data", async ({ page }) => {
    await common(page, () => overview());
    const saved = page.waitForRequest((request) => request.url().endsWith("/me/wellness/preferences") && request.method() === "PUT");
    await page.route("**/api/me/wellness/preferences", (route) => route.fulfill(json({ preferences })));

    await page.goto("/journal/wellbeing");
    await page.getByRole("button", { name: "Customise" }).click();
    const sheet = page.getByRole("dialog", { name: "Customise" });
    await sheet.getByRole("button", { name: "Move Meals up" }).click();
    await sheet.getByRole("switch", { name: "Mood" }).click();
    await expect(sheet.getByText("Its data stays until you delete it.", { exact: false })).toBeVisible();
    await sheet.getByRole("button", { name: "Save", exact: true }).click();

    expect(bodyOf(await saved)).toMatchObject({
      item_order: ["water", "meals", "sleep", "plan", "mood"],
      hidden_items: ["mood"],
      water_goal_ml: 2000,
      water_reminder: false,
    });
  });
});
