import { expect, test, type Page } from "@playwright/test";

// Redesign Phase 1 (ADR-137): the member app is four fixed tabs, and Box
// opens on today's workout. The API is stubbed; every route not listed here
// answers an empty object so unrelated widgets stay quiet.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(
    JSON.stringify({
      sub: user.id,
      role: user.role,
      memberships: [{ organization_slug: "kypseli" }],
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

function localToday() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

function daysAgoAt(days: number, hour: number) {
  const date = new Date();
  date.setDate(date.getDate() - days);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

const landing = {
  role: "member",
  admin_metrics: null,
  quote: { body: "Strength grows in the moments you think you can't go on.", author: "Coach Nikos" },
  gamification: {
    settings: { weekly_workout_target: 3, streak_shield_reset_day: null, leaderboard_enabled: true },
    stats: {
      current_streak: 4,
      longest_streak: 9,
      total_workouts: 42,
      total_prs: 6,
      current_streak_shields: 0,
      consistency_score: 80,
      motivation_score: 76,
      perseverance_score: 91,
      advancement_count: 2,
      last_workout_at: null,
    },
    preferences: { off_days: [] },
    badges: [{ id: "badge-1", badge_key: "workouts_10", label: "10 workouts" }],
    active_challenges: [],
    leaderboard: { visible: true, opted_in: false, weekly: [], monthly: [] },
  },
  coach_notes: [],
  membership: null,
  recent_executions: [],
};

async function stubMemberApi(page: Page) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/me/clubs", (route) =>
    route.fulfill(
      json({
        clubs: [
          { id: "club-1", kind: "gym", name: "Box Kypseli", organization_id: "org-1", organization_slug: "kypseli", role: "member", notify_level: "all", logo_url: null, primary_color: null, channels: [] },
        ],
      }),
    ),
  );
  await page.route("**/api/org/kypseli/community/wod-today**", (route) =>
    route.fulfill(
      json({
        date: localToday(),
        channel_id: null,
        classes: [{ id: "slot-1", scheduled_at: todayAt(18) }],
        leaderboard: [],
        logged_by_me: false,
        score: null,
        workout: { id: "wod-1", title: "Fran", type: "for_time", authoring_mode: "free_text", free_text_body: "21-15-9\nThrusters 43/30 kg\nPull-ups", sections: [] },
      }),
    ),
  );
  await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
  await page.route("**/api/me/social", (route) =>
    route.fulfill(
      json({
        posts_count: 0,
        followers_count: 0,
        following_count: 0,
        requests_count: 0,
        booking_sharing: { enabled: false, offered: false },
      }),
    ),
  );
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/threads/unread-count", (route) => route.fulfill(json({ unread_count: 0 })));
  await page.route("**/api/org/*/schedule?**", (route) =>
    route.fulfill(
      json({
        start_date: localToday(),
        end_date: localToday(),
        days: 7,
        class_types: [],
        slots: [
          {
            id: "slot-1",
            master_workout_id: "wod-1",
            name: "CrossFit",
            duration_minutes: 60,
            scheduled_at: todayAt(18),
            class_type_id: "ct-1",
            class_type: { id: "ct-1", name: "CrossFit" },
            capacity: 12,
            auto_approve: true,
            booking_timeout_minutes: 30,
            approved_booking_count: 4,
            spots_remaining: 8,
            workout: {
              id: "wod-1",
              title: "Fran",
              type: "for_time",
              authoring_mode: "free_text",
              free_text_body: "21-15-9\nThrusters 43/30 kg\nPull-ups",
              sections: [],
            },
            current_user_booking: { id: "booking-1", user_id: user.id, status: "approved", inserted_at: todayAt(8) },
            bookings: [],
          },
        ],
      }),
    ),
  );
  await page.route("**/api/org/*/my-workouts**", (route) =>
    route.fulfill(
      json({
        start_date: localToday(),
        end_date: localToday(),
        assignments: [
          {
            id: "assignment-1",
            master_workout_id: "strength-a",
            scheduled_for: localToday(),
            workout: { id: "strength-a", title: "Strength A", type: "strength", sections: [] },
          },
        ],
      }),
    ),
  );
  await page.route("**/api/org/*/executions", (route) => route.fulfill(json({ executions: [] })));
  await page.route("**/api/org/*/me/training-log/sources", (route) =>
    route.fulfill(json({ classes: [], assignments: [], library_workouts: [] })),
  );
  await page.route("**/api/org/*/me/workouts/*/injury-warnings**", (route) =>
    route.fulfill(json({ level: "none", warnings: [], warning_count: 0 })),
  );
  await page.route(/\/api(?:\/org\/[^/]+)?\/landing$/, (route) => route.fulfill(json(landing)));
  await page.route(/\/api(?:\/org\/[^/]+)?\/prs$/, (route) => route.fulfill(json({ prs: [] })));
  await page.route(/\/api(?:\/org\/[^/]+)?\/executions\/vault$/, (route) =>
    route.fulfill(
      json({
        workouts: [
          {
            master_workout_id: "wod-1",
            workout_title: "Fran",
            workout_type: "for_time",
            entries: [
              {
                id: "execution-1",
                completed_at_utc: daysAgoAt(1, 18),
                completed_at_tz: "UTC",
                source: "class_booking",
                total_elapsed_ms: 312_000,
                scale_level_slug: null,
              },
            ],
          },
        ],
      }),
    ),
  );
  await page.route("**/api/org/*/me/training-log/entries", (route) =>
    route.fulfill(
      json({
        entries: [
          {
            id: "log-1",
            source_type: "freeform",
            title: "Park run",
            performed_at_utc: daysAgoAt(1, 8),
            performed_at_tz: "UTC",
            duration_seconds: 1800,
            perceived_effort: 6,
            notes: null,
            status: "logged",
            lock_version: 1,
            section_scores: [],
            exercise_modifications: [],
            performed_exercises: [],
          },
        ],
      }),
    ),
  );
  await page.route(/\/api(?:\/org\/[^/]+)?\/me\/reviews$/, (route) =>
    route.fulfill(
      json({
        reviews: [
          { id: "review-1", inserted_at: daysAgoAt(1, 12), target_type: "app", rating: 5, body: "Love the new journal", status: "open", sentiment: "positive", tags: [], answers: [], params: {}, target_snapshot: {} },
        ],
      }),
    ),
  );
  // Ημερολόγιο › Ροή reads the server's feed (ADR-139).
  const item = (kind: string, id: string, occurredAt: string, entry: Record<string, unknown>) => ({
    kind,
    id,
    occurred_at: occurredAt,
    occurred_tz: "UTC",
    journal_visibility: "private",
    choosable_visibilities: ["private"],
    entry,
  });
  await page.route("**/api/me/journal**", (route) =>
    route.fulfill(
      json({
        items: [
          item("review", "review-1", daysAgoAt(1, 12), {
            id: "review-1",
            inserted_at: daysAgoAt(1, 12),
            target_type: "app",
            rating: 5,
            body: "Love the new journal",
            status: "open",
            sentiment: "positive",
            tags: [],
            answers: [],
            params: {},
            target_snapshot: {},
          }),
          item("training_log", "log-1", daysAgoAt(1, 8), {
            id: "log-1",
            source_type: "freeform",
            title: "Park run",
            performed_at_utc: daysAgoAt(1, 8),
            performed_at_tz: "UTC",
            duration_seconds: 1800,
            perceived_effort: 6,
            notes: null,
            status: "logged",
            lock_version: 1,
            section_scores: [],
            exercise_modifications: [],
            performed_exercises: [],
            comments: [],
          }),
          item("execution", "execution-1", daysAgoAt(1, 18), {
            id: "execution-1",
            master_workout_id: "wod-1",
            workout_title: "Fran",
            workout_type: "for_time",
            completed_at_utc: daysAgoAt(1, 18),
            completed_at_tz: "UTC",
            source: "class_booking",
            total_elapsed_ms: 312_000,
            scale_level_slug: null,
            status: "completed",
          }),
        ],
        next_cursor: null,
      }),
    ),
  );
  await page.route(/\/api(?:\/org\/[^/]+)?\/pr-sharing$/, (route) =>
    route.fulfill(json({ coach_visibility: true, grants: [] })),
  );
  await page.route(/\/api(?:\/org\/[^/]+)?\/gamification\/preferences$/, (route) =>
    route.fulfill(
      json({ preferences: route.request().method() === "GET" ? { off_days: [0] } : JSON.parse(route.request().postData() ?? "{}") }),
    ),
  );
  await page.route("**/api/org/*/me/entitlement", (route) =>
    route.fulfill(
      json({
        entitlement: {
          status: "active",
          enforcement_mode: "enforce",
          plan: { entitlement_version: 1, channels: [], capabilities: ["watch_on_demand", "request_form_reviews"] },
          allowances: {},
        },
      }),
    ),
  );
}

test.describe("member app shell", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("Box opens on today's class WOD, with the coach programme as a second source", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/box");

    const tabs = page.getByRole("navigation", { name: "Main sections" });
    await expect(tabs.getByRole("link")).toHaveText(["Home", "Box", "Journal", "Me"]);
    await expect(tabs.getByRole("link", { name: "Box" })).toHaveAttribute("aria-current", "page");

    await expect(page.getByRole("heading", { name: "Box Kypseli" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    // On a phone the two sources don't fit one row, so they are a dropdown (SegmentPicker).
    const sources = page.getByRole("combobox", { name: "Today's workouts by source" });
    await expect(sources).toContainText("Class");
    await expect(page.getByRole("button", { name: /Start/ })).toBeEnabled();
    await expect(page.getByRole("link", { name: "Videos" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Coach" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Appointments" })).toHaveCount(0);
    await page.screenshot({ path: "test-results/member-app/box.png", fullPage: true });

    await sources.click();
    await page.getByRole("option", { name: /Strength A/ }).click();
    await expect(page.getByRole("heading", { name: "Strength A" })).toBeVisible();
  });

  test("Journal's one write action lists the entry kinds that exist", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/journal");

    await expect(page.getByRole("heading", { name: "Journal", exact: true })).toBeVisible();
    await page.getByRole("button", { name: "New entry" }).click();
    const sheet = page.getByRole("dialog", { name: "New entry" });
    await expect(sheet.getByRole("heading", { level: 3 })).toHaveText(["Training", "Body", "Wellbeing", "Coach", "Note"]);
    await expect(sheet.getByRole("button")).toContainText(["Workout", "PR", "Measurement", "Injury", "Technique video", "Review", "Cancel"]);
    await page.screenshot({ path: "test-results/member-app/journal-new-entry.png" });
  });

  test("Me holds every secondary link, and old URLs land on the new pages", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/me");
    await expect(page.getByRole("main").getByText("Maria L")).toBeVisible();
    await expect(page.getByRole("link", { name: /Payments & receipts/ })).toHaveAttribute("href", "/me/payments");
    await page.screenshot({ path: "test-results/member-app/me.png", fullPage: true });

    await page.goto("/profile");
    await expect(page).toHaveURL(/\/me\/settings$/);
  });

  test("Home shows the gym's day: greeting, today's WOD, challenges, leaderboard and club posts", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/");

    await expect(page.getByRole("navigation", { name: "Main sections" }).getByRole("link", { name: "Home" })).toHaveAttribute("aria-current", "page");
    await expect(page.getByText("Strength grows in the moments you think you can't go on.")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    // ADR-138 D6: the gym club's #wod-today card, with the score action.
    await expect(page.getByRole("button", { name: "Log your score" })).toBeVisible();
    await expect(page.getByText("Posts from your club will show up here.")).toBeVisible();
    await page.screenshot({ path: "test-results/member-app/home.png", fullPage: true });
  });

  test("Journal's flow merges finished workouts, logged ones and reviews; Progress holds stats and PRs", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/journal");
    const flow = page.getByRole("main").last();
    await expect(flow.getByText("Fran")).toBeVisible();
    await expect(flow.getByText("Park run")).toBeVisible();
    await expect(flow.getByText("Love the new journal")).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Journal" }).getByRole("link")).toHaveText(["Feed", "Vault", "Body", "Wellbeing", "Progress"]);
    await expect(flow.getByRole("button", { name: /Share in Palee: Fran/ })).toBeVisible();
    await page.screenshot({ path: "test-results/member-app/journal-flow.png", fullPage: true });

    await page.goto("/journal/progress");
    await expect(page.getByText("76%")).toBeVisible();
    await expect(page.getByText("10 workouts")).toBeVisible();
    await expect(page.getByRole("button", { name: "Export workout history" })).toBeVisible();
    await page.screenshot({ path: "test-results/member-app/progress.png", fullPage: true });
  });

  test("Sharing & visibility gathers PR sharing, the leaderboard and rest days; old anchors follow them", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/me");
    await page.getByRole("link", { name: /Sharing & visibility/ }).click();
    await expect(page).toHaveURL(/\/me\/sharing$/);
    await expect(page.getByRole("button", { name: "Join leaderboard" })).toBeVisible();

    const sunday = page.locator("#training-schedule").getByRole("button", { pressed: true });
    await expect(sunday).toHaveCount(1);
    const saved = page.waitForRequest((request) => request.url().includes("/gamification/preferences") && request.method() !== "GET");
    await page.locator("#training-schedule").getByRole("button", { name: "Mon", exact: true }).click();
    expect(JSON.parse((await saved).postData() ?? "{}").off_days).toHaveLength(2);
    await page.screenshot({ path: "test-results/member-app/sharing.png", fullPage: true });

    await page.goto("/profile#vault");
    await expect(page).toHaveURL(/\/journal\/vault$/);
    await page.goto("/me/settings#pr-sharing");
    await expect(page).toHaveURL(/\/me\/sharing#pr-sharing$/);
  });
});
