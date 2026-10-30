import { expect, test, type Page } from "./support/test";

// Redesign Phase 1 (ADR-137): the member app is four fixed tabs, and Box
// opens on today's workout. The API is stubbed; every route not listed here
// answers an empty object so unrelated widgets stay quiet.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
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
    settings: { streak_shields: 1, streak_shield_reset_day: null, leaderboard_enabled: true },
    goal: { weekly_workout_target: 3, is_default: false, set_by_role: "self", min: 1, max: 14 },
    stats: {
      current_streak: 4,
      longest_streak: 9,
      total_workouts: 42,
      total_prs: 6,
      current_streak_shields: 0,
      consistency_score: 80,
      perseverance_score: 91,
      advancement_count: 2,
      weeks_on_goal: 9,
      challenges_completed: 1,
      last_workout_at: null,
    },
    // ADR-285: the scores that replaced «Motivation».
    level: {
      level: 8,
      xp: 4_550,
      level_start_xp: 4_100,
      next_level_xp: 5_000,
      points: { workouts: 50, prs: 100, weeks_on_goal: 150, challenges: 300 },
    },
    next_milestone: { badge_key: "workouts_50", kind: "workouts", current: 42, target: 50, remaining: 8 },
    strength: {
      percent: 6.4,
      window_days: 56,
      lifts: [{ name: "Back squat", from_kg: 100, to_kg: 108, gain_kg: 8 }],
      compared_lifts: 2,
      new_lifts: 0,
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
        posts_count: 1,
        media_count: 1,
        followers_count: 0,
        following_count: 0,
        requests_count: 0,
        booking_sharing: { enabled: false, offered: false },
      }),
    ),
  );
  // ADR-231: Me's «Media» tab reads the same grid as the public profile.
  await page.route("**/api/people/member-1/media**", (route) =>
    route.fulfill(
      json({
        posts: [
          {
            id: "post-media-1",
            origin: "profile",
            audience: "public",
            author: { id: "member-1", nickname: "Maria L", avatar_url: null },
            body: "Morning lifts",
            media: [{ id: "m-1", kind: "image", status: "ready", thumb_url: "/icon.svg", feed_url: "/icon.svg", alt_text: "Barbell on the floor", width: 1080, height: 1080 }],
            media_status: "ready",
            kudos_count: 0,
            comment_count: 0,
            kudos_by_me: false,
            can_delete: true,
            inserted_at: new Date().toISOString(),
          },
        ],
        next_cursor: null,
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
  // ADR-229: the weekly goal is read on its own (also without a gym).
  await page.route("**/api/gamification/goal", (route) => route.fulfill(json({ goal: landing.gamification.goal })));
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
    await expect(tabs.getByRole("link")).toHaveText(["Feed", "Box", "Journal", "Messages", /Me$/]);
    // The bell lives in the top bar beside the logo (PR #114).
    await expect(page.getByTestId("member-top-bar").getByRole("button", { name: "Notifications" })).toBeVisible();
    await expect(tabs.getByRole("link", { name: "Box" })).toHaveAttribute("aria-current", "page");
    // The current bottom-bar item has no fill (no Spark pill); it shows by colour, weight and the dot.
    await expect(tabs.getByRole("link", { name: "Box" })).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");

    await expect(page.getByRole("heading", { name: "Box Kypseli" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    // On a phone the two sources don't fit one row, so they are a dropdown (SegmentPicker).
    const sources = page.getByRole("combobox", { name: "Today's workouts by source" });
    await expect(sources).toContainText("Class");
    // The folded tabs are the page's main switch: a Dojo fill, never a grey field (ANR 2026-10-28).
    const dojo = await sources.evaluate((node) => {
      const probe = document.createElement("span");
      probe.style.color = "var(--primary)";
      node.appendChild(probe);
      const colour = getComputedStyle(probe).color;
      probe.remove();
      return colour;
    });
    await expect(sources).toHaveCSS("background-color", dojo);
    await expect(page.getByRole("button", { name: /Start/ })).toBeEnabled();
    await expect(page.getByRole("link", { name: "Videos" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Coach" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Appointments" })).toHaveCount(0);
    await page.screenshot({ path: "test-results/member-app/box.png", fullPage: true });

    await sources.click();
    await page.getByRole("option", { name: /Strength A/ }).click();
    await expect(page.getByRole("heading", { name: "Strength A" })).toBeVisible();
  });

  test("Box hides empty cards: no workout or booking means no card, and «Schedule» stays in the action row", async ({ page }) => {
    await stubMemberApi(page);
    await page.route("**/api/org/*/schedule?**", (route) =>
      route.fulfill(json({ start_date: localToday(), end_date: localToday(), days: 7, class_types: [], slots: [] })),
    );
    await page.route("**/api/org/*/my-workouts**", (route) =>
      route.fulfill(json({ start_date: localToday(), end_date: localToday(), assignments: [] })),
    );
    await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
    await page.goto("/box");

    await expect(page.getByRole("heading", { name: "Box Kypseli" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Schedule" })).toHaveAttribute("href", "/box/schedule");
    await expect(page.getByText("Membership", { exact: true })).toBeVisible();
    // Vision §4.2, §8.5: a card with nothing in it is hidden, never an empty state.
    await expect(page.getByText("Today's workout", { exact: true })).toHaveCount(0);
    await expect(page.getByText("Your next session", { exact: true })).toHaveCount(0);
    await expect(page.getByText("Open gym", { exact: true })).toHaveCount(0);
    await expect(page.getByText(/Nothing planned|No booking yet|No active subscription package/)).toHaveCount(0);
  });

  test("Box offers open-gym check-in without a booking when the package covers it (§6.2)", async ({ page }) => {
    await stubMemberApi(page);
    await page.route("**/api/org/*/schedule?**", (route) =>
      route.fulfill(json({ start_date: localToday(), end_date: localToday(), days: 7, class_types: [], slots: [] })),
    );
    await page.route("**/api/org/*/me/entitlement", (route) =>
      route.fulfill(
        json({
          entitlement: {
            status: "active",
            enforcement_mode: "enforce",
            plan: { entitlement_version: 1, channels: [], capabilities: ["open_gym"] },
            allowances: {},
          },
        }),
      ),
    );
    await page.goto("/box");

    await expect(page.getByText("Open gym", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Check in", exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "QR check-in" })).toHaveAttribute("href", "/box/check-in");
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

  test("Box without a membership shows only «Find a box»", async ({ page }) => {
    await stubMemberApi(page);
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));
    await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
    await page.goto("/box");

    await expect(page.getByRole("heading", { name: "You're not in a box yet" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Find a box" })).toHaveAttribute("href", "/around?kind=boxes");
    // ADR-221: or by name, when they already know which box.
    await page.route("**/api/box-search**", (route) =>
      route.fulfill(
        json({
          boxes: [
            {
              organization_id: "org-9",
              slug: "tolaras-box",
              name: "Τολάρας Box",
              logo_url: null,
              primary_color: null,
              provider_kind: "gym",
              neighbourhood: null,
              city: "Αθήνα",
              my_status: "none",
            },
          ],
        }),
      ),
    );
    await page.getByLabel("Or search by name").fill("tolaras");
    await expect(page.getByRole("link", { name: /Τολάρας Box/ })).toHaveAttribute("href", "/b/tolaras-box");
    await expect(page.getByText("Today's workout", { exact: true })).toHaveCount(0);
    await expect(page.getByText("Membership", { exact: true })).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Schedule" })).toHaveCount(0);

    await page.goto("/");
    await expect(page.getByText("Today's WOD at the gym")).toHaveCount(0);

    // The gym's landing payload doesn't exist without a gym: Progress skips it, no «not found».
    await page.goto("/journal/progress");
    await expect(page.getByRole("region", { name: "Personal Records" })).toBeVisible();
    await expect(page.getByText("The requested item was not found.")).toHaveCount(0);
  });

  test("Vault shows done workouts in folders or as a tree list", async ({ page }) => {
    await stubMemberApi(page);
    const box = { kind: "organization", organization_id: "org-1", name: "Box Kypseli", former: false };
    const coach = { kind: "organization", organization_id: "org-2", name: "Nikos P.", former: false };
    const group = (identity: string, type: string, sources: object[]) => ({
      identity,
      title: identity,
      workout_type: type,
      sources,
      attempts: [],
      attempt_count: 1,
      last_at: "2026-10-20T08:00:00Z",
    });
    await page.route("**/api/me/vault**", (route) =>
      route.fulfill(
        json({
          active_filter_count: 0,
          filter: {},
          groups: [group("Fran", "for_time", [box, coach]), group("Cindy", "amrap", [box])],
        }),
      ),
    );
    await page.goto("/journal/vault");

    const view = page.getByRole("tablist", { name: "View" });
    await expect(view.getByRole("tab", { name: "Folders" })).toHaveAttribute("aria-selected", "true");
    await page.getByRole("button", { name: /Box Kypseli/ }).click();
    await expect(page.getByRole("navigation", { name: "Folder path" })).toContainText("Box Kypseli");
    await page.getByRole("button", { name: /For time/i }).click();
    await expect(page.getByText("Fran").first()).toBeVisible();
    await expect(page.getByText("Cindy")).toHaveCount(0);

    await view.getByRole("tab", { name: "List" }).click();
    const tree = page.getByRole("tree", { name: "Workouts by folder" });
    await tree.getByRole("button", { name: /Nikos P\./ }).click();
    await tree.getByRole("button", { name: /For time/i }).click();
    await expect(tree.getByText("Fran").first()).toBeVisible();
    await page.screenshot({ path: "test-results/member-app/vault-tree.png", fullPage: true });
  });

  test("Me holds every secondary link, and old URLs land on the new pages", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/me");
    await expect(page.getByRole("main").getByText("Maria L")).toBeVisible();
    await expect(page.getByRole("link", { name: /Payments & receipts/ })).toHaveAttribute("href", "/me/payments");
    // ADR-196: the fixed §7.11 list; tour and first steps live in Help & tour.
    await expect(page.getByRole("button", { name: "Take the tour" })).toHaveCount(0);
    // ADR-231: «Posts · Media · PRs · Clubs»; Media is my photos and videos only.
    const mediaTab = page.getByRole("tab", { name: /Media/ });
    await expect(mediaTab).toContainText("1");
    await mediaTab.click();
    await expect(page.getByTestId("media-grid").getByRole("button", { name: "Photo: Barbell on the floor" })).toBeVisible();
    await page.getByRole("tab", { name: /Posts/ }).click();
    await page.screenshot({ path: "test-results/member-app/me.png", fullPage: true });
    await page.getByRole("link", { name: /Help & tour/ }).click();
    await expect(page).toHaveURL(/\/me\/help$/);
    await expect(page.getByRole("button", { name: "How visibility works" })).toBeVisible();

    await page.goto("/me/activity/chats");
    await expect(page).toHaveURL(/\/messages$/);

    await page.goto("/profile");
    await expect(page).toHaveURL(/\/me\/settings$/);
  });

  test("Instagram-like bars: Messages in the bottom bar, logo · ⊕ · bell on top, hidden while scrolling down", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/");

    const bottom = page.getByRole("navigation", { name: "Main sections" });
    await expect(bottom.getByRole("link", { name: "Messages", exact: true })).toHaveAttribute("href", "/messages");
    await expect(bottom.getByRole("button", { name: "Notifications" })).toHaveCount(0);
    const top = page.getByTestId("member-top-bar");
    await expect(top.getByRole("link", { name: "Palee" })).toBeVisible();
    await expect(top.getByRole("button", { name: "Notifications" })).toBeVisible();
    // ⊕ new post sits next to the bell, on the Feed only (vision §4 principle 3).
    await expect(top.getByRole("button", { name: "New post" })).toBeVisible();
    await page.screenshot({ path: "test-results/member-app/top-bar.png" });

    await page.evaluate(() => document.body.style.setProperty("min-height", "4000px"));
    await page.mouse.wheel(0, 600);
    await expect(top).toHaveAttribute("data-state", "hidden");
    await page.mouse.wheel(0, -200);
    await expect(top).toHaveAttribute("data-state", "shown");

    await page.goto("/box");
    await expect(page.getByTestId("member-top-bar").getByRole("button", { name: "Notifications" })).toBeVisible();
    await expect(page.getByTestId("member-top-bar").getByRole("button", { name: "New post" })).toHaveCount(0);
  });

  test("Home shows the gym's day: greeting and today's WOD, and hides the empty cards", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/");

    await expect(page.getByRole("navigation", { name: "Main sections" }).getByRole("link", { name: "Feed" })).toHaveAttribute("aria-current", "page");
    await expect(page.getByText("Strength grows in the moments you think you can't go on.")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    // ADR-138 D6: the gym club's #wod-today card, with the score action.
    await expect(page.getByRole("button", { name: "Log your score" })).toBeVisible();
    // ANR 2026-10-24: a card with nothing in it is not shown at all.
    await expect(page.getByText("From your club")).toHaveCount(0);
    await expect(page.getByText("My events", { exact: true })).toHaveCount(0);
    await expect(page.getByText("Seasonal momentum")).toHaveCount(0);
    // A ranking with no rows is no card; joining lives in Me › Sharing.
    await expect(page.getByText("Opt-in ranking")).toHaveCount(0);
    await page.screenshot({ path: "test-results/member-app/home.png", fullPage: true });
  });

  test("Journal's flow merges finished workouts, logged ones and reviews; Progress holds stats and PRs", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/journal");
    const flow = page.getByRole("main").last();
    await expect(flow.getByText("Fran")).toBeVisible();
    await expect(flow.getByText("Park run")).toBeVisible();
    await expect(flow.getByText("Love the new journal")).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Journal" }).getByRole("link")).toHaveText(["Timeline", "Vault", "Body", "Wellbeing", "Progress"]);
    await expect(flow.getByRole("button", { name: /Share in Palee: Fran/ })).toBeVisible();
    await page.screenshot({ path: "test-results/member-app/journal-flow.png", fullPage: true });

    // ADR-285 (mockup Φ3): a period bar, and «Source» only with two or more sources.
    const progressQueries: string[] = [];
    await page.route("**/api/me/progress?**", (route) => {
      progressQueries.push(new URL(route.request().url()).search);
      return route.fulfill(
        json({
          progress: {
            totals: { sessions: 3, minutes: 120, workouts: 3 },
            weekly: [],
            days: [],
            consistency: { current_streak_weeks: 0 },
            sources: {},
            score_history: [],
            pr_timeline: [],
            by_source: [],
            available_sources: ["freeform", "device"],
            filter: {},
            active_filter_count: 0,
          },
        }),
      );
    });
    await page.goto("/journal/progress");
    await expect(page.getByRole("button", { name: /^Filters/ })).toHaveCount(0);
    await page.getByRole("group", { name: "Period" }).getByRole("button", { name: "6 months" }).click();
    await expect.poll(() => progressQueries.some((query) => query.includes("range=6m"))).toBe(true);
    await page.getByRole("button", { name: "Source" }).click();
    await page.getByRole("menuitemcheckbox", { name: "Device" }).click();
    await expect.poll(() => progressQueries.some((query) => query.includes("sources=device"))).toBe(true);
    await page.keyboard.press("Escape");
    // ADR-285: «Motivation» repeated Consistency; three scores took its place.
    await expect(page.getByText("Motivation", { exact: true })).toHaveCount(0);
    await expect(page.getByText("4,550 / 5,000 XP to level 9")).toBeVisible();
    await expect(page.getByText("+6.4%")).toBeVisible();
    await expect(page.getByText("workouts to the 50 workouts badge")).toBeVisible();
    await expect(page.getByText("91%")).toBeVisible();
    await page.getByRole("button", { name: /Points from everything you do/ }).click();
    await expect(page.getByRole("dialog", { name: "XP level" })).toContainText("a workout +50");
    await page.keyboard.press("Escape");
    await expect(page.getByText("10 workouts")).toBeVisible();
    // ANR 2026-10-24: PRs are one section of Progress; the history export lives in Vault.
    await expect(page.getByRole("region", { name: "Personal Records" })).toBeVisible();
    await expect(page.getByRole("link", { name: "View all" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Export workout history" })).toHaveCount(0);
    await page.screenshot({ path: "test-results/member-app/progress.png", fullPage: true });
  });

  test("Sharing & visibility groups what the coach sees and the community opt-ins; rest days moved to Settings", async ({ page }) => {
    await stubMemberApi(page);
    await page.goto("/me");
    await page.getByRole("link", { name: /Sharing & visibility/ }).click();
    await expect(page).toHaveURL(/\/me\/sharing$/);
    // ADR-286: each injury has its own «Let my box see it» switch; who read them is listed here.
    await expect(page.locator("#coach-sees")).toContainText("Let my box see it");
    await expect(page.locator("#community").getByRole("button", { name: "Join leaderboard" })).toBeVisible();
    await expect(page.locator("#community").getByRole("switch", { name: /PR celebrations/ })).not.toBeChecked();
    await expect(page.locator("#community").getByRole("switch", { name: /Challenges/ })).toBeChecked();
    await expect(page.locator("#training-schedule")).toHaveCount(0);

    // ADR-196: rest days live in Settings; the old anchor follows them.
    await page.goto("/me/sharing#training-schedule");
    await expect(page).toHaveURL(/\/me\/settings#training-schedule$/);
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
