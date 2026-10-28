import { expect, test, type Page } from "./support/test";

// ADR-229: the weekly workout goal is the person's own. The member sets it in
// Εγώ › Ρυθμίσεις › Πρόγραμμα προπόνησης and sees when their coach set it; a
// coach sets it from the client's profile (Training tab); the box settings
// keep only the streak shields and when they renew. The API is stubbed;
// every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

type Role = "member" | "coach" | "owner";

function persona(role: Role) {
  const user = {
    id: `${role}-1`,
    nickname: role === "coach" ? "Kostas" : role === "owner" ? "Anna" : "Maria",
    role: role === "member" ? "member" : "admin",
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

const CAPABILITIES: Record<Role, Record<string, boolean>> = {
  member: {},
  coach: { manage_coaching: true, view_client_training: true },
  owner: { manage_coaching: true, manage_settings: true, view_client_training: true },
};

async function common(page: Page, role: Role) {
  const { user, token } = persona(role);
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
          status: "active",
          capabilities: CAPABILITIES[role],
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
}

test.describe("personal weekly goal (ADR-229)", () => {
  test("a member sets their own goal and sees when their coach set it", async ({ page }) => {
    await common(page, "member");
    let goal = { weekly_workout_target: 2, is_default: true, set_by_role: null as string | null, set_by_nickname: null as string | null, min: 1, max: 14 };
    const puts: unknown[] = [];
    await page.route("**/api/gamification/goal", (route) => {
      if (route.request().method() === "PUT") {
        const body = route.request().postDataJSON() as { weekly_workout_target: number };
        puts.push(body);
        goal = { ...goal, weekly_workout_target: body.weekly_workout_target, is_default: false, set_by_role: "self", set_by_nickname: "Maria" };
      }
      return route.fulfill(json({ goal }));
    });

    await page.goto("/me/settings#training-schedule");
    const setting = page.getByTestId("weekly-goal-setting");
    await expect(setting.getByTestId("training-goal-value")).toHaveText("2 workouts a week", { timeout: 60_000 });
    await expect(setting).toContainText("This is the starting suggestion.");

    await setting.getByRole("button", { name: "One workout more" }).click();
    await expect.poll(() => puts).toEqual([{ weekly_workout_target: 3 }]);
    await expect(setting.getByTestId("training-goal-value")).toHaveText("3 workouts a week");
    await expect(setting).not.toContainText("This is the starting suggestion.");

    // Back at the minimum the "fewer" button stops.
    await setting.getByRole("button", { name: "One workout fewer" }).click();
    await setting.getByRole("button", { name: "One workout fewer" }).click();
    await expect(setting.getByTestId("training-goal-value")).toHaveText("1 workout a week");
    await expect(setting.getByRole("button", { name: "One workout fewer" })).toBeDisabled();

    // A goal the coach set says so, and stays editable.
    goal = { ...goal, weekly_workout_target: 4, set_by_role: "coach", set_by_nickname: "Kostas" };
    await page.reload();
    await expect(setting.getByTestId("training-goal-value")).toHaveText("4 workouts a week", { timeout: 60_000 });
    await expect(setting).toContainText("Set by your coach Kostas. You can change it at any time.");
    await expect(setting.getByRole("button", { name: "One workout more" })).toBeEnabled();
  });

  test("a goal that failed to load is never edited on a guess", async ({ page }) => {
    await common(page, "member");
    let fail = true;
    const puts: unknown[] = [];
    await page.route("**/api/gamification/goal", (route) => {
      if (route.request().method() === "PUT") puts.push(route.request().postDataJSON());
      if (fail) return route.fulfill(json({ error: "boom" }, 500));
      return route.fulfill(json({ goal: { weekly_workout_target: 5, is_default: false, set_by_role: "self", set_by_nickname: "Maria", min: 1, max: 14 } }));
    });

    await page.goto("/me/settings#training-schedule");
    const setting = page.getByTestId("weekly-goal-setting");
    await expect(setting).toContainText("Could not load your goal.", { timeout: 60_000 });
    await expect(setting.getByRole("button", { name: "One workout more" })).toHaveCount(0);
    await expect(setting).not.toContainText("This is the starting suggestion.");

    fail = false;
    await setting.getByRole("button", { name: "Try again" }).click();
    await expect(setting.getByTestId("training-goal-value")).toHaveText("5 workouts a week");
    expect(puts).toEqual([]);
  });

  test("a coach sets a client's goal on the client's profile", async ({ page }) => {
    await common(page, "coach");
    const puts: unknown[] = [];
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
    await page.route("**/api/org/*/staff/clients/u-1/training-goal", (route) => {
      if (route.request().method() === "PUT") {
        const body = route.request().postDataJSON() as { weekly_workout_target: number };
        puts.push(body);
        return route.fulfill(
          json({ goal: { weekly_workout_target: body.weekly_workout_target, is_default: false, set_by_role: "coach", set_by_nickname: "Kostas", min: 1, max: 14 } }),
        );
      }
      return route.fulfill(json({ goal: { weekly_workout_target: 2, is_default: true, set_by_role: null, min: 1, max: 14 } }));
    });

    await page.goto("/admin/users/u-1?tab=training");
    const panel = page.getByTestId("client-training-goal");
    await expect(panel.getByTestId("training-goal-value")).toHaveText("2 workouts a week", { timeout: 60_000 });
    await expect(panel).toContainText("Not set yet. The default of 2 workouts a week applies.");
    await expect(panel).toContainText("Eleni is notified and can change it.");

    const save = panel.getByRole("button", { name: "Save goal" });
    await expect(save).toBeDisabled();
    await panel.getByRole("button", { name: "One workout more" }).click();
    await panel.getByRole("button", { name: "One workout more" }).click();
    await save.click();
    await expect.poll(() => puts).toEqual([{ weekly_workout_target: 4 }]);
    await expect(panel).toContainText("Saved. Eleni has been notified.");
    await expect(panel).toContainText("Last set by Kostas.");
  });

  test("box settings keep only the streak shields and when they renew", async ({ page }) => {
    await common(page, "owner");
    const patches: Record<string, unknown>[] = [];
    let gamification = { streak_shields: 1, streak_shield_reset_day: null as number | null, leaderboard_enabled: true };
    const settings = () => ({ notifications: { enabled: false }, gamification, finance: {}, scheduling: {}, workouts: {}, provider: {} });
    await page.route("**/api/org/*/admin/settings", (route) => {
      if (route.request().method() === "PATCH") {
        const body = route.request().postDataJSON() as { gamification?: typeof gamification };
        patches.push(body as Record<string, unknown>);
        if (body.gamification) gamification = { ...gamification, ...body.gamification };
      }
      return route.fulfill(json(settings()));
    });

    // The settings hub also shows the join links (ADR-216).
    await page.route("**/api/org/kypseli/join-link", (route) =>
      route.fulfill(json({ member: { enabled: false }, athlete: { enabled: false, key: null } })),
    );
    await page.goto("/org/kypseli/admin/settings#gamification");
    const section = page.locator("section#gamification");
    await expect(section.getByTestId("weekly-goal-is-personal")).toContainText("The weekly workout goal is personal", { timeout: 60_000 });
    await expect(section).not.toContainText("Weekly workout target");

    const shields = section.getByRole("spinbutton", { name: /Streak shields per renewal/ });
    await expect(shields).toHaveValue("1");
    await expect(section).toContainText("Empty: each client's shields renew every month on the day they signed up.");

    await shields.fill("2");
    await section.getByRole("spinbutton", { name: /Shield renewal day/ }).fill("5");
    await expect(section).toContainText("Shields renew for everyone on day 5 of every month.");
    await section.getByRole("button", { name: "Save", exact: true }).click();

    await expect.poll(() => patches.length).toBe(1);
    expect(patches[0]).toEqual({ gamification: { streak_shields: 2, streak_shield_reset_day: 5, leaderboard_enabled: true } });
  });
});
