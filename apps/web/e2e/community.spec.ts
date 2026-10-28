import { expect, test, type Page } from "./support/test";

// Redesign Phase 2 M4 (ADR-143, plan §5a board 7): the club page's four tabs
// with «Μέλη», member groups and «Πρότεινε ομάδα», reporting a post, «+ Βρες»
// with open clubs, and staff's «Κοινότητα». The API is stubbed; every route
// not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function personaFor(role: "member" | "admin", membershipRole: string) {
  const user = {
    id: role === "member" ? "member-1" : "owner-1",
    nickname: role === "member" ? "Maria" : "Apostolos",
    role,
    email: `${role}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: membershipRole, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const channel = (id: string, kind: string, extra: Record<string, unknown> = {}) => ({
  id,
  kind,
  name: null,
  write_policy: "members",
  membership: "everyone",
  joined: true,
  can_post: true,
  can_leave: false,
  ...extra,
});

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
  channels: [channel("ch-ann", "announcements", { write_policy: "staff", can_post: false }), channel("ch-wod", "wod")],
};

const author = { id: "member-2", nickname: "Eleni", avatar_url: null };
const post = {
  id: "post-1",
  origin: "club",
  audience: "club_channel",
  author,
  body: "Who's in for Saturday's partner WOD?",
  attachment: null,
  attachment_id: null,
  attachment_type: null,
  can_delete: false,
  can_moderate: false,
  can_pin: false,
  can_report: true,
  channel: { id: "ch-wod", kind: "wod", name: null },
  club: { id: "club-1", name: "Box Kypseli", organization_slug: "kypseli", kind: "gym" },
  comment_count: 0,
  hidden: false,
  inserted_at: new Date().toISOString(),
  kudos_by_me: false,
  kudos_count: 2,
  pinned: false,
};

const runners = {
  id: "group-1",
  club_id: "club-1",
  name: "Sunday runners",
  description: "Easy 10k after the WOD",
  join_policy: "open",
  status: "active",
  member_count: 6,
  request_count: 0,
  membership: "none",
  admin: false,
  can_manage: false,
  can_report: true,
  created_by_me: false,
  club: { id: "club-1", name: "Box Kypseli", organization_slug: "kypseli" },
};

const openClub = {
  id: "open-1",
  organization_id: "org-2",
  name: "Hyrox crew",
  description: "Race prep with the Gazi box.",
  join_policy: "open",
  cover_media_id: null,
  cover_url: null,
  member_count: 14,
  membership: "none",
  role: null,
  box: { name: "CrossFit Gazi", slug: "crossfit-gazi", logo_url: null },
  channels: [
    { id: "o-ann", kind: "announcements", name: null },
    { id: "o-gen", kind: "general", name: null },
  ],
};

async function common(page: Page, persona: ReturnType<typeof personaFor>, memberships: unknown[] = []) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

type MemberCalls = { proposals: unknown[]; reports: unknown[]; joins: string[] };

async function member(page: Page) {
  const calls: MemberCalls = { proposals: [], reports: [], joins: [] };
  let clubs: unknown[] = [gymClub];
  await common(page, personaFor("member", "member"));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/api/me/feed**", (route) =>
    route.fulfill(json({ posts: calls.reports.length ? [] : [post], pinned: [], next_cursor: null })),
  );
  await page.route("**/api/me/clubs/club-1/members**", (route) => {
    const q = new URL(route.request().url()).searchParams.get("q") ?? "";
    const everyone = [
      { id: "coach-1", nickname: "Stelios", avatar_url: null, coach: true, following: false },
      { id: "member-2", nickname: "Eleni", avatar_url: null, coach: false, following: true },
      { id: "member-3", nickname: "Petros", avatar_url: null, coach: false, following: false },
    ];
    const members = everyone.filter((row) => row.nickname.toLowerCase().includes(q.toLowerCase()));
    return route.fulfill(json({ club_id: "club-1", count: members.length, members }));
  });
  await page.route("**/api/org/kypseli/community/groups", (route) => {
    if (route.request().method() === "POST") {
      calls.proposals.push(route.request().postDataJSON());
      return route.fulfill(json({ group: { ...runners, id: "group-2", name: "Mobility club", status: "pending", membership: "member", admin: true, created_by_me: true } }, 201));
    }
    return route.fulfill(
      json({
        settings: { member_groups: "approval", needs_approval: true, can_propose: true, lifecycle: { warn_after_days: 50, archive_after_days: 60 } },
        groups: [runners],
        archived: [],
      }),
    );
  });
  await page.route("**/api/org/kypseli/community/groups/group-1/membership", (route) => {
    calls.joins.push("group-1");
    return route.fulfill(json({ group: { ...runners, membership: "member", member_count: 7 } }));
  });
  await page.route("**/api/me/community/reports", (route) => {
    calls.reports.push(route.request().postDataJSON());
    return route.fulfill(json({ reported: true, target_type: "post", target_id: "post-1" }, 201));
  });
  await page.route("**/api/me/community/discover**", (route) =>
    route.fulfill(json({ clubs: [{ ...openClub, membership: calls.joins.includes("open-1") ? "member" : "none" }], groups: [runners] })),
  );
  await page.route("**/api/me/open-clubs/open-1", (route) => route.fulfill(json({ club: openClub })));
  await page.route("**/api/me/open-clubs/open-1/membership", (route) => {
    calls.joins.push("open-1");
    clubs = [
      gymClub,
      {
        ...gymClub,
        id: "open-1",
        kind: "open",
        name: "Hyrox crew",
        organization_id: "org-2",
        organization_slug: "crossfit-gazi",
        channels: [channel("o-ann", "announcements", { write_policy: "staff", can_post: false }), channel("o-gen", "general")],
      },
    ];
    return route.fulfill(json({ club: { ...openClub, membership: "member", member_count: 15 } }));
  });
  return calls;
}

test.describe("community", () => {
  test("the club page has Feed · Channels · Events · Members, and Members lists coaches first with a search", async ({ page }) => {
    await member(page);
    await page.goto("/clubs/club-1");

    const tabs = page.getByRole("tablist", { name: "Box Kypseli" });
    await expect(tabs.getByRole("tab")).toHaveText(["Feed", "Channels", "Events", "Club members"]);
    await tabs.getByRole("tab", { name: "Events" }).click();
    await expect(page.getByText("No upcoming events.")).toBeVisible();

    await tabs.getByRole("tab", { name: "Club members" }).click();
    await expect(page.getByText("3 members")).toBeVisible();
    const people = page.getByRole("link", { name: /Stelios|Eleni|Petros/ });
    await expect(people).toHaveCount(3);
    await expect(people.first()).toContainText("Stelios");
    await expect(people.first()).toContainText("Coach");
    await page.getByPlaceholder("Search club members").fill("ele");
    await expect(page.getByText("1 member", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: /Eleni/ })).toHaveAttribute("href", "/people/member-2");
  });

  test("the club's Feed keeps a fixed order: pinned · WOD · PRs · events · posts (vision §7.1)", async ({ page }) => {
    await member(page);
    const pinnedPost = { ...post, id: "post-pin", body: "Doors open at 07:00 on Monday", pinned: true, channel: { id: "ch-ann", kind: "announcements", name: null } };
    const prPost = { ...post, id: "post-pr", body: "New deadlift PR: 140 kg", attachment_type: "pr" };
    await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [post, prPost], pinned: [pinnedPost], next_cursor: null })));
    await page.route("**/api/org/*/community/wod-today**", (route) =>
      route.fulfill(
        json({
          date: "2026-10-20",
          channel_id: null,
          classes: [],
          leaderboard: [],
          logged_by_me: false,
          score: null,
          workout: { id: "wod-1", title: "Fran", type: "for_time", authoring_mode: "free_text", free_text_body: "21-15-9", sections: [] },
        }),
      ),
    );
    const startsAt = new Date(Date.now() + 3 * 86_400_000).toISOString();
    await page.route("**/api/me/community/clubs/club-1/events**", (route) =>
      route.fulfill(
        json({
          events: [
            {
              id: "event-1",
              organization_id: "org-1",
              club_id: "club-1",
              club: { id: "club-1", name: "Box Kypseli", kind: "gym" },
              box: { name: "Box Kypseli", slug: "kypseli", logo_url: null },
              title: "Saturday partner WOD",
              starts_at: startsAt,
              ends_at: startsAt,
              place: { name: "Box Kypseli", address: null, latitude: null, longitude: null, location_id: null },
              capacity: 20,
              spots_left: 10,
              going_count: 10,
              waitlist_count: 0,
              price_cents: 0,
              currency: "EUR",
              open_to_non_members: false,
              guest_pass_allowed: false,
              guests_per_member: 0,
              goers: null,
              cancelled: false,
              can_rsvp: true,
              can_manage: false,
              my: null,
            },
          ],
        }),
      ),
    );
    await page.goto("/clubs/club-1");

    const order = [
      page.getByText("Doors open at 07:00 on Monday"),
      page.getByText("Fran", { exact: true }),
      page.getByText("New deadlift PR: 140 kg"),
      page.getByText("Saturday partner WOD", { exact: true }),
      page.getByText("Who's in for Saturday's partner WOD?"),
    ];
    const tops: number[] = [];
    for (const item of order) {
      await expect(item).toBeVisible();
      tops.push((await item.boundingBox())!.y);
    }
    expect([...tops].sort((a, b) => a - b)).toEqual(tops);
    await expect(page.getByText("No posts yet.")).toHaveCount(0);
  });

  test("an empty club Feed shows no empty cards, only one quiet line", async ({ page }) => {
    await member(page);
    await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
    await page.goto("/clubs/club-1");

    await expect(page.getByText("No posts yet.")).toHaveCount(1);
    // No workout today: no WOD card at all.
    await expect(page.getByRole("button", { name: "Log your score" })).toHaveCount(0);
  });

  test("Channels lists member groups; a member joins one and suggests a new one for approval", async ({ page }) => {
    const calls = await member(page);
    await page.goto("/clubs/club-1");
    await page.getByRole("tab", { name: "Channels" }).click();

    await expect(page.getByText("Member groups")).toBeVisible();
    await expect(page.getByRole("link", { name: /Sunday runners/ })).toContainText("Member group · 6 members");
    await page.getByRole("button", { name: "Join", exact: true }).click();
    await expect.poll(() => calls.joins).toEqual(["group-1"]);

    await page.getByRole("button", { name: "+ Suggest a group" }).click();
    const sheet = page.getByRole("dialog", { name: "Suggest a group" });
    await sheet.getByLabel("Name").fill("Mobility club");
    await sheet.getByLabel("In one line").fill("Stretch after class");
    await sheet.getByRole("radio", { name: /On request/ }).click();
    await sheet.getByRole("button", { name: "Send for approval" }).click();

    await expect(page.getByRole("dialog", { name: "Sent to staff" })).toBeVisible();
    expect(calls.proposals).toEqual([{ name: "Mobility club", description: "Stretch after class", join_policy: "request" }]);
  });

  test("the subtle report flag sends a reason and the post disappears for the reporter", async ({ page }) => {
    const calls = await member(page);
    await page.goto("/clubs/club-1");

    await expect(page.getByText("Who's in for Saturday's partner WOD?")).toBeVisible();
    // Board 12: reporting is a low-contrast flag on the card, no longer an entry under ⋯.
    await expect(page.getByRole("button", { name: "More" })).toHaveCount(0);
    await page.getByRole("button", { name: "Report", exact: true }).click();
    const sheet = page.getByRole("dialog", { name: "Report this post" });
    await expect(sheet.getByRole("button", { name: "Send report" })).toBeDisabled();
    await sheet.getByRole("radio", { name: "Spam" }).click();
    await sheet.getByLabel("Anything to add? (optional)").fill("Selling supplements");
    await sheet.getByRole("button", { name: "Send report" }).click();

    await expect(page.getByText("Thanks, staff will take a look.")).toBeVisible();
    await page.getByRole("dialog", { name: "Thank you" }).getByRole("button", { name: "OK" }).click();
    await expect(page.getByText("Who's in for Saturday's partner WOD?")).toBeHidden();
    expect(calls.reports).toEqual([{ target_type: "post", target_id: "post-1", reason: "spam", note: "Selling supplements" }]);
  });

  test("«+ Find» lists open clubs and groups; an open club opens on its landing and «Join» lets you in", async ({ page }) => {
    const calls = await member(page);
    await page.goto("/");
    await page.goto("/clubs/find");

    await expect(page.getByRole("heading", { name: "Find clubs, boxes and people" })).toBeVisible();
    await expect(page.getByRole("link", { name: /Hyrox crew/ })).toContainText("CrossFit Gazi · 14 club members");
    await expect(page.getByText("Groups in your boxes")).toBeVisible();

    await page.getByRole("link", { name: /Hyrox crew/ }).click();
    await expect(page).toHaveURL(/\/clubs\/open-1$/);
    await expect(page.getByText("Run by CrossFit Gazi")).toBeVisible();
    await expect(page.getByText("#announcements · #general")).toBeVisible();
    await page.getByRole("button", { name: "Join", exact: true }).click();

    await expect(page.getByRole("tablist", { name: "Hyrox crew" })).toBeVisible();
    expect(calls.joins).toEqual(["open-1"]);
  });

  // ADR-216: the same field finds a live, published box or coach by name.
  test("«Find» finds a box by name and opens its public page", async ({ page }) => {
    await member(page);
    const queries: string[] = [];
    await page.route("**/api/box-search**", (route) => {
      const q = new URL(route.request().url()).searchParams.get("q") ?? "";
      queries.push(q);
      return route.fulfill(
        json({
          boxes: q.toLowerCase().startsWith("tol")
            ? [
                {
                  organization_id: "org-9",
                  slug: "tolaras-box",
                  name: "Τολάρας Box",
                  logo_url: null,
                  primary_color: null,
                  provider_kind: "gym",
                  neighbourhood: "Κυψέλη",
                  city: "Αθήνα",
                  my_status: "none",
                },
              ]
            : [],
        }),
      );
    });
    await page.goto("/clubs/find");

    const field = page.getByPlaceholder("Search clubs, boxes and people");
    await field.fill("zz");
    await expect.poll(() => queries).toContain("zz");
    // Nothing matched: no empty card.
    await expect(page.getByText("Boxes and coaches")).toHaveCount(0);

    await field.fill("tolaras");
    const card = page.getByRole("link", { name: /Τολάρας Box/ });
    await expect(page.getByText("Boxes and coaches")).toBeVisible();
    await expect(card).toContainText("Box · Κυψέλη");
    await expect(card).toHaveAttribute("href", "/b/tolaras-box");
  });
});

test.describe("staff community", () => {
  test("staff approve a group, act on a report and see the box's open clubs", async ({ page }) => {
    const decisions: unknown[] = [];
    const actions: unknown[] = [];
    let pending = [
      {
        id: "group-2",
        name: "Mobility club",
        description: "Stretch after class",
        join_policy: "request",
        status: "pending",
        member_count: 1,
        inserted_at: new Date().toISOString(),
        created_by: { id: "member-1", nickname: "Maria", avatar_url: null },
      },
    ];
    await common(page, personaFor("admin", "owner"), [
      {
        role: "owner",
        roles: ["owner"],
        capabilities: { moderate_community: "all", manage_community: "all", manage_settings: "all" },
        organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
        settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
      },
    ]);
    await page.route("**/api/org/kypseli/admin/community/groups", (route) =>
      route.fulfill(
        json({
          settings: { member_groups: "approval", needs_approval: true, can_propose: true, lifecycle: { warn_after_days: 50, archive_after_days: 60 } },
          pending,
          live: [{ ...runners, inserted_at: new Date().toISOString(), last_post_at: new Date().toISOString(), created_by: null }],
          archived: [],
        }),
      ),
    );
    await page.route("**/api/org/kypseli/admin/community/groups/group-2/decision", (route) => {
      decisions.push(route.request().postDataJSON());
      pending = [];
      return route.fulfill(json({ group: { id: "group-2", status: "active" } }));
    });
    await page.route("**/api/org/kypseli/admin/community/reports", (route) =>
      route.fulfill(
        json({
          reports: [
            {
              target_type: "post",
              target_id: "post-1",
              report_count: 2,
              reasons: { spam: 2 },
              notes: ["Selling supplements"],
              author,
              preview: { body: post.body, hidden: false },
              last_reported_at: new Date().toISOString(),
            },
          ],
        }),
      ),
    );
    await page.route("**/api/org/kypseli/admin/community/reports/actions", (route) => {
      actions.push(route.request().postDataJSON());
      return route.fulfill(json({ target_type: "post", target_id: "post-1", action: "hide", resolved: 2 }));
    });
    await page.route("**/api/org/kypseli/admin/community/clubs", (route) =>
      route.fulfill(json({ clubs: [{ ...openClub, organization_id: "org-1", request_count: 1, role: "staff" }] })),
    );

    await page.goto("/org/kypseli/admin/community");
    await expect(page.getByRole("heading", { name: "Community" })).toBeVisible();
    await expect(page.getByRole("radio", { name: /With approval/ })).toHaveAttribute("aria-checked", "true");
    await expect(page.getByText("Mobility club")).toBeVisible();
    await page.getByRole("button", { name: "Approve" }).click();
    await expect.poll(() => decisions).toEqual([{ decision: "approve" }]);

    await page.getByRole("tab", { name: /Reports/ }).click();
    await expect(page.getByText("Spam ×2")).toBeVisible();
    await expect(page.getByText("«Selling supplements»")).toBeVisible();
    await page.getByRole("button", { name: "Hide" }).click();
    await expect(page.getByText("Hidden. The reports are closed.")).toBeVisible();
    expect(actions).toEqual([{ target_type: "post", target_id: "post-1", action: "hide" }]);

    await page.getByRole("tab", { name: /Open clubs/ }).click();
    await expect(page.getByRole("button", { name: /Hyrox crew/ })).toContainText("14 club members · Anyone · 1 request");
    await expect(page.getByRole("button", { name: "+ New open club" })).toBeVisible();
  });
});
