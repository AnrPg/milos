import { expect, test, type Page } from "./support/test";

// P3-M7 Partners (ADR-169): opting in from a club's Members tab, the deck
// with filters, undo and a mutual match, the match's conversation with
// «Plan together», blocking, and the Sharing switch with blocked people.
// The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
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

const gymClub = {
  id: "club-1",
  kind: "gym",
  name: "Box Kypseli",
  organization_id: "org-1",
  organization_slug: "kypseli",
  role: "member",
  notify_level: "all",
  logo_url: null,
  primary_color: null,
  channels: [],
};

const options = {
  levels: ["beginner", "intermediate", "advanced"],
  times: ["early", "midday", "afternoon", "evening", "weekend"],
  goals: ["strength", "conditioning", "weight_loss", "skills", "competition", "consistency"],
  genders: ["woman", "man", "other"],
  gender_preferences: ["any", "women", "men"],
  max_goals: 3,
  about_max: 140,
  daily_swipes: 200,
};

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });
const card = (id: string, nickname: string, shared: { times: string[]; goals: string[]; same_level: boolean }) => ({
  profile_id: `profile-${id}`,
  person: person(id, nickname),
  level: "intermediate",
  times: ["early", "evening"],
  goals: ["strength", "skills"],
  about: `${nickname} trains for Hyrox`,
  shared,
});

const match = {
  id: "match-1",
  club_id: "club-1",
  club_name: "Box Kypseli",
  person: person("member-3", "Dimitra"),
  partner_profile_id: "profile-member-3",
  status: "active",
  end_reason: null,
  ended_by_me: false,
  read_only: false,
  plannable: true,
  unread: 0,
  matched_at: "2026-10-21T08:00:00Z",
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
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [gymClub] })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-21", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
  await page.route("**/api/me/clubs/club-1/members**", (route) => route.fulfill(json({ club_id: "club-1", count: 0, members: [] })));
}

test.describe("partners", () => {
  test("a member opts in, filters the deck, passes and undoes, and a mutual like opens «You found a training partner»", async ({ page }) => {
    await common(page);
    const calls = { profile: [] as unknown[], swipes: [] as unknown[], undone: [] as string[], deckQueries: [] as string[] };
    let profile: Record<string, unknown> | null = null;
    await page.route("**/api/me/clubs/club-1/partners", (route) =>
      route.fulfill(json({ club_id: "club-1", offered: true, unavailable_reason: null, member: true, profile, swipes_remaining: 200, options })),
    );
    await page.route("**/api/me/clubs/club-1/partners/profile", (route) => {
      const body = route.request().postDataJSON();
      calls.profile.push(body);
      profile = { id: "profile-me", club_id: "club-1", suspended: false, ...body };
      return route.fulfill(json({ profile }));
    });
    await page.route("**/api/me/clubs/club-1/partners/deck**", (route) => {
      calls.deckQueries.push(new URL(route.request().url()).search);
      return route.fulfill(
        json({
          club_id: "club-1",
          swipes_remaining: 200,
          cards: [
            card("member-2", "Eleni", { times: ["early"], goals: ["strength"], same_level: true }),
            card("member-3", "Dimitra", { times: [], goals: ["skills"], same_level: false }),
          ],
        }),
      );
    });
    await page.route("**/api/me/clubs/club-1/partners/swipes", (route) => {
      const body = route.request().postDataJSON();
      calls.swipes.push(body);
      const mutual = body.target_id === "member-3" && body.direction === "like";
      return route.fulfill(json({ target_id: body.target_id, direction: body.direction, match: mutual ? match : null, swipes_remaining: 199 }));
    });
    await page.route("**/api/me/clubs/club-1/partners/swipes/*", (route) => {
      calls.undone.push(route.request().url().split("/").pop() ?? "");
      return route.fulfill(json({ target_id: "member-2", undone: true }));
    });

    await page.goto("/clubs/club-1");
    await page.getByRole("tab", { name: "Members" }).click();
    const section = page.getByTestId("partners-section");
    await expect(section).toContainText("Find a training partner");
    await expect(section).toContainText("A match needs you both");

    await section.getByRole("button", { name: "Set up my profile" }).click();
    const sheet = page.getByRole("dialog", { name: "Your partner profile" });
    await expect(sheet.getByRole("button", { name: "Turn on" })).toBeDisabled();
    await sheet.getByRole("button", { name: "Early morning" }).click();
    await sheet.getByRole("button", { name: "Strength" }).click();
    await sheet.getByRole("button", { name: "Skills" }).click();
    await sheet.getByRole("button", { name: "Competition" }).click();
    await expect(sheet.getByRole("button", { name: "Consistency" })).toBeDisabled();
    await sheet.getByRole("button", { name: "Turn on" }).click();
    await expect(sheet).toBeHidden();
    expect(calls.profile[0]).toMatchObject({ active: true, times: ["early"], goals: ["strength", "skills", "competition"], gender_preference: "any" });

    const first = page.getByTestId("partner-card");
    await expect(first).toContainText("Eleni");
    await expect(first).toContainText("You both: Intermediate · Early morning · Strength");

    await page.getByRole("button", { name: "Filters" }).click();
    await page.getByTestId("partner-filters").getByRole("button", { name: "Evening" }).click();
    await expect.poll(() => calls.deckQueries.at(-1)).toBe("?time=evening");
    await expect(page.getByRole("button", { name: "Filters (1)" })).toBeVisible();

    await page.getByRole("button", { name: "Not now, Eleni" }).click();
    await expect(page.getByTestId("partner-card")).toContainText("Dimitra");
    await page.getByTestId("partner-undo").click();
    await expect(page.getByTestId("partner-card")).toContainText("Eleni");
    expect(calls.undone).toEqual(["member-2"]);

    await page.getByRole("button", { name: "Not now, Eleni" }).click();
    await page.getByRole("button", { name: "Train with Dimitra" }).click();
    const matched = page.getByRole("dialog", { name: "You found a training partner" });
    await expect(matched).toContainText("You and Dimitra both want to train together");
    await expect(matched.getByRole("link", { name: "Say hi" })).toHaveAttribute("href", "/partners/match-1");
    expect(calls.swipes).toEqual([
      { target_id: "member-2", direction: "pass" },
      { target_id: "member-2", direction: "pass" },
      { target_id: "member-3", direction: "like" },
    ]);
  });

  test("the conversation suggests a class with «Plan together», and blocking ends it quietly", async ({ page }) => {
    await common(page);
    const posted: unknown[] = [];
    const blocked: unknown[] = [];
    const messages = [
      { id: "msg-1", match_id: "match-1", kind: "text", body: "Hi! 07:00 Thursday?", plan: null, mine: false, author: person("member-3", "Dimitra"), created_at: "2026-10-21T08:05:00Z" },
    ];
    await page.route("**/api/me/partners/matches", (route) => route.fulfill(json({ matches: [match] })));
    await page.route("**/api/me/partners/matches/match-1/messages**", (route) =>
      route.fulfill(json({ messages: [...messages].reverse(), next_cursor: null, read_only: false, unread: 0 })),
    );
    await page.route("**/api/me/partners/matches/match-1/sessions", (route) =>
      route.fulfill(
        json({
          available: true,
          timezone: "Europe/Athens",
          sessions: [
            { class_id: "class-1", name: "CrossFit", scheduled_at: "2026-10-23T04:00:00Z", duration_minutes: 60, spots_remaining: 4, booked_by_me: false, booked_by_partner: true, shared_time: true },
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
        body: body.body,
        plan: { class_id: "class-1", name: "CrossFit", scheduled_at: "2026-10-23T04:00:00Z", duration_minutes: 60 },
        mine: true,
        author: person("member-1", "Maria"),
        created_at: "2026-10-21T08:10:00Z",
      } as never);
      return route.fulfill(json({ message: messages.at(-1) }, 201));
    });
    await page.route("**/api/me/blocks", (route) => {
      blocked.push(route.request().postDataJSON());
      return route.fulfill(json({ user_id: "member-3", blocked: true }));
    });

    await page.goto("/partners/match-1");
    await expect(page.getByRole("heading", { name: "Dimitra" })).toBeVisible();
    await expect(page.getByTestId("partner-chat")).toContainText("Hi! 07:00 Thursday?");

    await page.getByTestId("partner-plan-open").click();
    const plan = page.getByRole("dialog", { name: "A class with Dimitra" });
    await expect(plan.getByTestId("partner-sessions")).toContainText("Dimitra booked");
    await plan.getByRole("radio", { name: /CrossFit/ }).click();
    await plan.getByPlaceholder("e.g. See you at the door").fill("See you there");
    await plan.getByRole("button", { name: "Suggest" }).click();
    await expect(plan).toBeHidden();
    expect(posted).toEqual([{ class_id: "class-1", body: "See you there" }]);
    await expect(page.getByTestId("partner-plan")).toHaveAttribute("href", "/box/schedule?open_slot=class-1");

    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Block Dimitra" }).click();
    const confirm = page.getByRole("dialog", { name: "Block Dimitra?" });
    await expect(confirm).toContainText("won't be told");
    await confirm.getByRole("button", { name: "Block" }).click();
    await expect(page).toHaveURL(/\/messages\?filter=partners/);
    expect(blocked).toEqual([{ user_id: "member-3" }]);
  });

  test("Sharing & visibility pauses every profile at once and lists blocked people to unblock", async ({ page }) => {
    await common(page);
    const saved: unknown[] = [];
    const unblocked: string[] = [];
    let visible = true;
    await page.route("**/api/me/partners/settings", (route) => {
      if (route.request().method() === "PUT") {
        saved.push(route.request().postDataJSON());
        visible = route.request().postDataJSON().visible;
      }
      return route.fulfill(json({ visible, clubs: 2, club_ids: ["club-1", "club-2"] }));
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
    const toggle = page.getByTestId("partner-visibility").getByRole("switch", { name: /Show me in Partners/ });
    await expect(toggle).toBeChecked();
    await expect(page.getByTestId("partner-visibility")).toContainText("Your profiles in 2 clubs");
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
