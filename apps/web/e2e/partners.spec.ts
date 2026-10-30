import { expect, test, type Page } from "./support/test";

// Public Partners («Συναθλητές», ADR-280): the Γύρω μου card, /partners by
// verification state, the profile with the 18+ box, the full-screen deck
// swiped by drag and by buttons with undo and a match, the conversation's
// suggestions and the report to the Palee team, and the Sharing switch.
// The API is stubbed; every route not listed answers an empty object.

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
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const options = {
  levels: ["beginner", "intermediate", "advanced"],
  times: ["early", "midday", "afternoon", "evening", "weekend"],
  goals: ["strength", "conditioning", "weight_loss", "skills", "competition", "consistency"],
  genders: ["woman", "man", "other"],
  gender_preferences: ["any", "women", "men"],
  max_goals: 3,
  about_max: 140,
  daily_swipes: 200,
  default_within_km: 10,
  disciplines: ["crossfit", "running"],
  max_disciplines: 5,
  distances_km: [2, 5, 10, 25],
  report_reasons: ["unsafe", "fake", "minor", "harassment", "other"],
};

const myProfile = {
  id: "profile-me",
  active: true,
  paused: false,
  adult_confirmed_at: "2026-10-30T08:00:00Z",
  show_box: true,
  level: "intermediate",
  times: ["early"],
  goals: ["strength"],
  disciplines: [],
  about: null,
  gender: null,
  gender_preference: "any",
};

type Status = "verified" | "needs_verification" | "in_review" | "rejected" | "suspended";
const overview = (status: Status, profile: unknown = null, distance = "available") => ({
  eligibility: { status, method: status === "verified" ? "membership" : null, next_step: null },
  profile,
  swipes_remaining: 200,
  distance,
  options,
});

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });
const card = (id: string, nickname: string, badge: unknown) => ({
  profile_id: `profile-${id}`,
  person: person(id, nickname),
  level: "intermediate",
  times: ["early", "evening"],
  goals: ["strength", "skills"],
  disciplines: [],
  about: `${nickname} trains for Hyrox`,
  badge,
  shared: { times: ["early"], goals: ["strength"], disciplines: [], same_level: true },
});

const match = {
  id: "match-1",
  partner_id: "member-3",
  person: person("member-3", "Dimitra"),
  status: "active",
  end_reason: null,
  ended_by_me: false,
  read_only: false,
  unread: 0,
  matched_at: "2026-10-30T08:00:00Z",
  last_message_at: null,
};

async function common(page: Page) {
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
}

test.describe("partners", () => {
  test("without verification, /partners is one short card to get verified", async ({ page }) => {
    await common(page);
    await page.route("**/api/me/partners", (route) => route.fulfill(json(overview("needs_verification"))));

    await page.goto("/partners");
    const verify = page.getByTestId("partners-verify");
    await expect(verify).toContainText("Get verified to find training partners");
    await expect(verify.getByRole("link", { name: "Get verified" })).toHaveAttribute("href", "/partners/verify");
    await expect(page.getByTestId("partner-deck")).toHaveCount(0);
  });

  test("in review and suspended say so plainly", async ({ page }) => {
    await common(page);
    let status: Status = "in_review";
    await page.route("**/api/me/partners", (route) => route.fulfill(json(overview(status))));
    await page.goto("/partners");
    await expect(page.getByTestId("partners-in-review")).toContainText("We're checking your verification");

    status = "suspended";
    await page.reload();
    await expect(page.getByTestId("partners-suspended")).toContainText("Your Training partners access is suspended");
    await expect(page.getByTestId("partners-suspended").getByRole("link")).toHaveCount(0);
  });

  test("a verified member sets up the profile with the 18+ box, then swipes by drag and by buttons, undoes, and matches", async ({ page }) => {
    await common(page);
    const calls = { profile: [] as Record<string, unknown>[], swipes: [] as unknown[], undone: [] as string[], deckQueries: [] as string[] };
    let profile: Record<string, unknown> | null = null;
    await page.route("**/api/me/partners", (route) => route.fulfill(json(overview("verified", profile))));
    await page.route("**/api/me/partners/profile", (route) => {
      const body = route.request().postDataJSON();
      calls.profile.push(body);
      profile = { ...myProfile, ...body };
      return route.fulfill(json({ profile }));
    });
    await page.route("**/api/me/partners/deck**", (route) => {
      calls.deckQueries.push(new URL(route.request().url()).search);
      return route.fulfill(
        json({
          swipes_remaining: 200,
          within_km: 10,
          cards: [
            card("member-2", "Eleni", { kind: "box", box_name: "CrossFit Kypseli" }),
            card("member-4", "Kostas", { kind: "sponsors", box_name: null }),
            card("member-3", "Dimitra", { kind: "verified", box_name: null }),
          ],
        }),
      );
    });
    await page.route("**/api/me/partners/swipes", (route) => {
      const body = route.request().postDataJSON();
      calls.swipes.push(body);
      const mutual = body.target_id === "member-3" && body.direction === "like";
      return route.fulfill(json({ target_id: body.target_id, direction: body.direction, match: mutual ? match : null, swipes_remaining: 199 }));
    });
    await page.route("**/api/me/partners/swipes/*", (route) => {
      calls.undone.push(route.request().url().split("/").pop() ?? "");
      return route.fulfill(json({ target_id: "member-4", undone: true }));
    });

    await page.goto("/partners");
    const setup = page.getByTestId("partners-setup");
    await expect(setup).toContainText("Verified member");
    await setup.getByRole("button", { name: "Set up my profile" }).click();

    const sheet = page.getByRole("dialog", { name: "Your training partner profile" });
    await expect(sheet.getByRole("switch", { name: /Show my box/ })).toBeChecked();
    await sheet.getByRole("button", { name: "Turn on" }).click();
    await expect(sheet).toContainText("Training partners is only for people aged 18 or older.");
    await expect(sheet).toContainText("Choose your level.");
    expect(calls.profile).toEqual([]);

    await sheet.getByRole("checkbox", { name: "I am 18 or older" }).check();
    await sheet.getByRole("radio", { name: "Intermediate" }).click();
    await sheet.getByRole("button", { name: "Early morning" }).click();
    await sheet.getByRole("button", { name: "Strength" }).click();
    await sheet.getByRole("button", { name: "Turn on" }).click();
    await expect(sheet).toBeHidden();
    expect(calls.profile[0]).toMatchObject({
      active: true,
      adult_confirmed: true,
      show_box: true,
      level: "intermediate",
      times: ["early"],
      goals: ["strength"],
      gender_preference: "any",
    });

    const top = page.getByTestId("partner-card");
    await expect(top).toContainText("Eleni");
    await expect(top).toContainText("Member of CrossFit Kypseli");
    await expect(top).toContainText("“Eleni trains for Hyrox”");
    await expect(top).toContainText("In common:");

    // Drag to the right past the threshold: yes.
    const box = (await top.boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 220, box.y + box.height / 2, { steps: 8 });
    await page.mouse.up();
    await expect.poll(() => calls.swipes).toEqual([{ target_id: "member-2", direction: "like" }]);
    await expect(page.getByTestId("partner-card")).toContainText("Kostas");
    await expect(page.getByTestId("partner-card")).toContainText("With sponsors");

    // A short drag springs back and decides nothing.
    const next = (await page.getByTestId("partner-card").boundingBox())!;
    await page.mouse.move(next.x + next.width / 2, next.y + next.height / 2);
    await page.mouse.down();
    await page.mouse.move(next.x + next.width / 2 - 30, next.y + next.height / 2, { steps: 3 });
    await page.mouse.up();
    expect(calls.swipes).toHaveLength(1);

    // The ✕ button passes; undo brings the card back.
    await page.getByRole("button", { name: "Not now, Kostas" }).click();
    await expect(page.getByTestId("partner-card")).toContainText("Dimitra");
    await page.getByTestId("partner-undo").click();
    await expect(page.getByTestId("partner-card")).toContainText("Kostas");
    expect(calls.undone).toEqual(["member-4"]);

    // The ← key passes too.
    await page.keyboard.press("ArrowLeft");
    await expect(page.getByTestId("partner-card")).toContainText("Dimitra");

    await page.getByRole("button", { name: "Train with Dimitra" }).click();
    const matched = page.getByRole("dialog", { name: "You found a training partner" });
    await expect(matched).toContainText("You and Dimitra both want to train together");
    await expect(matched.getByRole("link", { name: "Say hi" })).toHaveAttribute("href", "/partners/match-1");
    expect(calls.swipes).toEqual([
      { target_id: "member-2", direction: "like" },
      { target_id: "member-4", direction: "pass" },
      { target_id: "member-4", direction: "pass" },
      { target_id: "member-3", direction: "like" },
    ]);
  });

  test("the filters narrow the deck by time and distance", async ({ page }) => {
    await common(page);
    const queries: string[] = [];
    await page.route("**/api/me/partners", (route) => route.fulfill(json(overview("verified", myProfile))));
    await page.route("**/api/me/partners/deck**", (route) => {
      queries.push(new URL(route.request().url()).search);
      const within = Number(new URL(route.request().url()).searchParams.get("within_km") ?? 10);
      return route.fulfill(json({ swipes_remaining: 200, within_km: within, cards: [card("member-2", "Eleni", null)] }));
    });

    await page.goto("/partners");
    await expect(page.getByTestId("partner-card")).toContainText("Eleni");
    await page.getByTestId("partner-filters").click();
    const filters = page.getByRole("dialog", { name: "Filters" });
    await filters.getByRole("group", { name: "Distance" }).getByRole("button", { name: "Within 5 km" }).click();
    await filters.getByRole("group", { name: "Time" }).getByRole("button", { name: "Evening" }).click();
    await filters.getByRole("button", { name: "Show", exact: true }).click();
    await expect.poll(() => queries.at(-1)).toBe("?time=evening&within_km=5");
    await expect(page.getByTestId("partner-filters")).toContainText("≤ 5 km");
    await expect(page.getByTestId("partner-filters")).toContainText("Filters (1)");
  });

  test("the conversation suggests ideas near you both, «Suggest» posts one, and reporting also blocks", async ({ page }) => {
    await common(page);
    const posted: unknown[] = [];
    const reports: unknown[] = [];
    const messages: Record<string, unknown>[] = [
      { id: "msg-1", match_id: "match-1", kind: "text", body: "Hi! Saturday?", plan: null, mine: false, author: person("member-3", "Dimitra"), created_at: "2026-10-30T08:05:00Z" },
    ];
    await page.route("**/api/me/partners", (route) => route.fulfill(json(overview("verified", myProfile))));
    await page.route("**/api/me/partners/matches", (route) => route.fulfill(json({ matches: [match] })));
    await page.route("**/api/me/partners/matches/match-1/messages**", (route) =>
      route.fulfill(json({ messages: [...messages].reverse(), next_cursor: null, read_only: false, unread: 0 })),
    );
    await page.route("**/api/me/partners/matches/match-1/suggestions", (route) =>
      route.fulfill(
        json({
          suggestions: [
            {
              id: "event-1",
              key: "event:event-1",
              kind: "event",
              title: "Run club",
              place: "Pedion tou Areos",
              starts_at: "2026-11-01T08:00:00Z",
              ends_at: null,
              time_zone: "Europe/Athens",
              spots_left: null,
              distances_km: [2.1, 3],
              reasons: ["shared_time:weekend", "near_both"],
              booked_by_me: false,
              booked_by_partner: false,
            },
          ],
        }),
      ),
    );
    await page.route("**/api/me/partners/matches/match-1/plans", (route) => {
      const body = route.request().postDataJSON();
      posted.push(body);
      messages.push({
        id: "msg-2",
        match_id: "match-1",
        kind: "plan",
        body: null,
        plan: { kind: "event", id: "event-1", title: "Run club", starts_at: "2026-11-01T08:00:00Z", place: "Pedion tou Areos" },
        mine: true,
        author: person("member-1", "Maria"),
        created_at: "2026-10-30T08:10:00Z",
      });
      return route.fulfill(json({ message: messages.at(-1) }, 201));
    });
    await page.route("**/api/me/partners/reports", (route) => {
      reports.push(route.request().postDataJSON());
      return route.fulfill(json({ target_id: "member-3", reported: true, blocked: true }));
    });

    await page.goto("/partners/match-1");
    await expect(page.getByRole("heading", { name: "Dimitra" })).toBeVisible();
    await expect(page.getByTestId("partner-chat")).toContainText("Hi! Saturday?");

    const ideas = page.getByTestId("partner-suggestions");
    await expect(ideas).toContainText("You don't share a box. Ideas near you both:");
    await expect(ideas).toContainText("you both train: Weekend · 2.1 and 3 km away");
    await ideas.getByRole("button", { name: "Suggest" }).click();
    expect(posted).toEqual([{ kind: "event", id: "event-1" }]);
    await expect(page.getByTestId("partner-plan")).toHaveAttribute("href", "/events/event-1");

    await page.getByTestId("partner-go-together").click();
    await expect(page.getByRole("textbox", { name: "Write a message" })).toHaveValue(/Shall we train together\?/);

    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Report Dimitra" }).click();
    const report = page.getByRole("dialog", { name: "Report Dimitra" });
    await expect(report).toContainText("Reporting also blocks");
    await report.getByRole("button", { name: "Report", exact: true }).click();
    await expect(report).toContainText("Choose a reason.");
    await report.getByRole("radio", { name: "Under 18" }).click();
    await report.getByRole("button", { name: "Report", exact: true }).click();
    await expect(page.getByTestId("partner-report-done")).toBeVisible();
    expect(reports).toEqual([{ target_id: "member-3", reason: "minor", note: null }]);
    await page.getByRole("button", { name: "OK" }).click();
    await expect(page).toHaveURL(/\/messages\?filter=partners/);
  });

  test("Sharing & visibility switches me out of the deck and lists blocked people to unblock", async ({ page }) => {
    await common(page);
    const saved: unknown[] = [];
    const unblocked: string[] = [];
    let visible = true;
    await page.route("**/api/me/partners/settings", (route) => {
      if (route.request().method() === "PUT") {
        saved.push(route.request().postDataJSON());
        visible = route.request().postDataJSON().visible;
      }
      return route.fulfill(json({ visible, has_profile: true }));
    });
    let blocks = [{ person: person("member-9", "Nikos"), blocked_at: "2026-10-20T10:00:00Z" }];
    await page.route("**/api/me/blocks", (route) => route.fulfill(json({ blocks })));
    await page.route("**/api/me/blocks/*", (route) => {
      unblocked.push(route.request().url().split("/").pop() ?? "");
      blocks = [];
      return route.fulfill(json({ user_id: "member-9", blocked: false }));
    });
    await page.route(/\/api(?:\/org\/[^/]+)?\/pr-sharing$/, (route) => route.fulfill(json({ coach_visibility: true, grants: [] })));
    await page.route(/\/api(?:\/org\/[^/]+)?\/gamification\/preferences$/, (route) => route.fulfill(json({ preferences: { off_days: [0] } })));
    await page.route("**/api/me/social", (route) =>
      route.fulfill(
        json({
          posts_count: 0,
          followers_count: 0,
          following_count: 0,
          requests_count: 0,
          booking_sharing: { enabled: false, offered: true },
          member_visibility: { hidden: false },
          around_visibility: { visible: false, has_area: false },
        }),
      ),
    );
    await page.route("**/api/me/wellness-summary-sharing", (route) =>
      route.fulfill(json({ sharing: { wellness: false, cravings: false, wellness_since: null, cravings_since: null } })),
    );
    await page.route("**/api/me/wellness-summary-sharing/access-log", (route) => route.fulfill(json({ entries: [] })));

    await page.goto("/me/sharing");
    const toggle = page.getByTestId("partner-visibility").getByRole("switch", { name: /Show me in Training partners/ });
    await expect(toggle).toBeChecked();
    await expect(page.getByTestId("partner-visibility")).toContainText("Off takes you out of the cards");
    await toggle.click();
    await expect(toggle).not.toBeChecked();
    expect(saved).toEqual([{ visible: false }]);

    await page.getByRole("button", { name: /Blocked people/ }).click();
    const list = page.getByTestId("blocked-people");
    await expect(list).toContainText("Nikos");
    await list.getByRole("button", { name: "Unblock" }).click();
    await expect(list).toContainText("You haven't blocked anyone.");
    expect(unblocked).toEqual(["member-9"]);
  });
});
