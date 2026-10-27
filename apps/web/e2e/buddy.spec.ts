import { expect, test, type Page, type Request } from "./support/test";

// Redesign Phase 2 M12 (ADR-160): Buddy για στήριξη. An invite link is
// accepted from its landing page, a buddy is invited from Εγώ › Buddy,
// «Χρειάζομαι στήριξη» sends with a five-second undo, the buddy's quick reply
// opens the pair's conversation, ten minutes without a reply bring the calm
// card, the member chooses what the coach's weekly summary shows, and the
// coach reads it on the client's profile. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const pad = (value: number) => String(value).padStart(2, "0");
const now = new Date();
const today = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

function persona(role: "member" | "coach" = "member") {
  const user = {
    id: role === "coach" ? "coach-1" : "member-1",
    nickname: role === "coach" ? "Kostas" : "Maria",
    role: role === "coach" ? "admin" : "member",
    email: `${role}@example.com`,
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

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });

function link(id: string, nickname: string, extra: Record<string, unknown> = {}) {
  return {
    id,
    person: person(`${id}-user`, nickname),
    role: "requester",
    status: "active",
    ended_by_me: false,
    receives_weekly_summary: false,
    via_link: false,
    started_at: new Date(Date.now() - 86_400_000).toISOString(),
    created_at: new Date(Date.now() - 86_400_000).toISOString(),
    unread_messages: 0,
    ...extra,
  };
}

function overview(lists: { buddies?: unknown[]; supporting?: unknown[]; invitations?: unknown[] } = {}) {
  return {
    buddies: lists.buddies ?? [],
    supporting: lists.supporting ?? [],
    invitations: lists.invitations ?? [],
    max_buddies: 3,
    invite_days: 7,
    settings: { phone: null, share_phone: false, quiet_hours: null, tz: "UTC" },
  };
}

function supportRequest(extra: Record<string, unknown> = {}) {
  return {
    id: "req-1",
    role: "sender",
    source: "quick",
    status: "sending",
    message: null,
    created_at: new Date().toISOString(),
    undo_until: new Date(Date.now() + 5_000).toISOString(),
    can_undo: true,
    recipients: [{ person: person("link-1-user", "Eleni"), quiet_hours: false, replied_at: null }],
    replies: [],
    quiet_hours: [],
    nudge: {
      due: false,
      due_at: new Date(Date.now() + 10 * 60_000).toISOString(),
      breathing_seconds: 120,
      can_resend: true,
      suggestions: ["breathing", "water", "walk"],
      help_lines: { informational: true, path: "/help/support-lines" },
      sent_at: null,
    },
    ...extra,
  };
}

function wellnessOverview() {
  return {
    from: today,
    to: today,
    consented: true,
    preferences: { glass_ml: 250, water_goal_ml: 2000, sleep_goal_minutes: 450, hidden_items: [], item_order: ["water", "sleep", "meals", "plan", "mood"], water_reminder: false },
    days: [
      {
        date: today,
        water: { ml: 0, count: 0, glass_ml: 250, goal_ml: 2000, status: "none" },
        sleep: { status: "none", goal_minutes: 450, nap_minutes: 0 },
        meals: { status: "none", count: 0, portions: {} },
        cravings: { status: "none", count: 0 },
      },
    ],
    entries: [],
    cravings: [],
    plans: [],
    photos: {},
    photo_capabilities: { content_types: ["image/jpeg"], max_bytes: 10_000_000 },
    week: { water_days_logged: 0, water_days_on_goal: 0, nights_logged: 0, nights_on_goal: 0, meal_days_logged: 0, cravings: 0 },
  };
}

async function common(page: Page, options: { role?: "member" | "coach"; buddies?: () => unknown; authenticated?: boolean } = {}) {
  const role = options.role ?? "member";
  const { user, token } = persona(role);
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  if (options.authenticated === false) {
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
  } else {
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  }
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role,
          roles: [role],
          capabilities: role === "coach" ? { view_health: true } : {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/community/wod-today**", (route) => route.fulfill(json({ wod: null })));
  await page.route("**/api/me/buddies", (route) =>
    route.request().method() === "GET" ? route.fulfill(json(options.buddies ? options.buddies() : overview())) : route.fallback(),
  );
  await page.route("**/api/me/support-requests?**", (route) => route.fulfill(json({ support_requests: [] })));
}

async function wellnessPage(page: Page) {
  await page.route("**/api/wellbeing/injuries", (route) => route.fulfill(json({ injuries: [] })));
  await page.route("**/api/wellbeing/check-ins?**", (route) =>
    route.fulfill(json({ check_ins: [], questions: ["sleep", "energy", "mood", "stress", "body"].map((key) => ({ key, min: 1, max: 4 })) })),
  );
  await page.route("**/api/me/wellness?**", (route) => route.fulfill(json(wellnessOverview())));
}

test.describe("Buddy για στήριξη", () => {
  test("an invite link is accepted from its landing page", async ({ page }) => {
    await common(page);
    await page.route("**/api/buddy-invites/tok1", (route) =>
      route.fulfill(json({ status: "pending", inviter: person("u-9", "Dimitra"), expires_at: new Date(Date.now() + 86_400_000).toISOString() })),
    );
    await page.route("**/api/me/buddy-invites/tok1/claim", (route) =>
      route.fulfill(json({ link: link("link-9", "Dimitra", { role: "buddy", via_link: true }) })),
    );
    const claim = page.waitForRequest((request) => request.url().endsWith("/me/buddy-invites/tok1/claim") && request.method() === "POST");

    await page.goto("/buddy/tok1");
    await expect(page.getByTestId("buddy-inviter")).toContainText("Dimitra");
    await page.getByRole("button", { name: "Accept Dimitra's invitation" }).click();
    await claim;
    await expect(page.getByText("You are now Dimitra's check-in buddy.")).toBeVisible();
  });

  test("a buddy is invited from Εγώ › Buddy and an invitation is accepted", async ({ page }) => {
    let accepted = false;
    const invitation = link("link-5", "Petros", { role: "buddy", status: "pending", started_at: null });
    await common(page, {
      buddies: () => overview({ invitations: accepted ? [] : [invitation], supporting: accepted ? [{ ...invitation, status: "active" }] : [] }),
    });
    await page.route("**/api/me/buddies/candidates**", (route) => route.fulfill(json({ candidates: [{ person: person("u-7", "Nikos"), relation: "club", link_status: null }] })));
    await page.route("**/api/me/buddies", (route) =>
      route.request().method() === "POST" ? route.fulfill(json({ link: link("link-7", "Nikos", { status: "pending" }) })) : route.fallback(),
    );
    await page.route("**/api/me/buddies/link-5/accept", (route) => {
      accepted = true;
      return route.fulfill(json({ link: { ...invitation, status: "active" } }));
    });

    await page.goto("/me/buddy");
    await expect(page.getByRole("heading", { name: "Check-in buddy", level: 1 })).toBeVisible();

    const acceptCall = page.waitForRequest((request) => request.url().endsWith("/me/buddies/link-5/accept") && request.method() === "POST");
    await page.getByRole("button", { name: "Accept", exact: true }).click();
    await acceptCall;

    await page.getByRole("button", { name: "Add a person or your coach" }).click();
    const invite = page.waitForRequest((request) => request.url().endsWith("/api/me/buddies") && request.method() === "POST");
    await page.getByRole("button", { name: "Invite Nikos" }).click();
    expect(bodyOf(await invite)).toEqual({ user_id: "u-7" });

    // ADR-210: a link for someone not on Palee can also go by email.
    await page.route("**/api/me/buddies/invite-links", (route) =>
      route.fulfill(
        json(
          { token: "tok2", path: "/buddy-invite/tok2", url: "http://127.0.0.1/buddy-invite/tok2", expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(), link: link("link-8", "Someone", { status: "pending" }) },
          201,
        ),
      ),
    );
    const emailed: unknown[] = [];
    await page.route("**/api/me/share-links/email", (route) => {
      emailed.push(route.request().postDataJSON());
      return route.fulfill(json({ delivery: { id: "message-1", status: "queued" } }, 202));
    });
    await page.getByRole("button", { name: "Send a link to someone not on Palee" }).click();
    await expect(page.getByTestId("buddy-invite-url")).toHaveValue(/\/buddy\/tok2$/);
    await page.getByRole("button", { name: "Send by email" }).click();
    await page.getByLabel("Their email address").fill("friend@example.com");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect(page.getByText("Sent to friend@example.com")).toBeVisible();
    expect(emailed).toEqual([{ link: "buddy_invite", token: "tok2", to: "friend@example.com" }]);
  });

  test("«I need support» sends with a five-second undo", async ({ page }) => {
    let current = supportRequest();
    await common(page, { buddies: () => overview({ buddies: [link("link-1", "Eleni")] }) });
    await wellnessPage(page);
    await page.route("**/api/me/support-requests", (route) =>
      route.request().method() === "POST" ? route.fulfill(json({ support_request: current })) : route.fallback(),
    );
    await page.route("**/api/me/support-requests/req-1", (route) => route.fulfill(json({ support_request: current })));
    await page.route("**/api/me/support-requests/req-1/undo", (route) => {
      current = { ...current, status: "undone", can_undo: false };
      return route.fulfill(json({ support_request: current }));
    });

    await page.goto("/journal/wellbeing?support=new");
    await expect(page.getByTestId("support-recipients")).toContainText("Eleni");
    const sent = page.waitForRequest((request) => request.url().endsWith("/api/me/support-requests") && request.method() === "POST");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await sent;
    await expect(page.getByText(/Sending in \d s/)).toBeVisible();

    const undo = page.waitForRequest((request) => request.url().endsWith("/me/support-requests/req-1/undo"));
    await page.getByRole("button", { name: "Undo" }).click();
    await undo;
    await expect(page.getByText("Taken back. Nobody was told.").first()).toBeVisible();
  });

  test("the buddy's quick reply opens the conversation, and «Call me» shows a shared phone", async ({ page }) => {
    const request = {
      ...supportRequest({ id: "req-9", status: "delivered", can_undo: false, undo_until: null }),
      role: "buddy",
      sender: person("u-3", "Eleni"),
      message: "Rough evening.",
      quick_replies: ["here", "walk", "call"],
    };
    await common(page, { buddies: () => overview({ supporting: [link("link-2", "Eleni", { role: "buddy" })] }) });
    await page.route("**/api/me/support-requests/req-9", (route) => route.fulfill(json({ support_request: request })));
    await page.route("**/api/me/support-requests/req-9/replies", (route) => {
      const kind = bodyOf(route.request()).kind;
      return route.fulfill(
        json({
          reply: { id: `reply-${kind}`, kind, created_at: new Date().toISOString(), person: person("member-1", "Maria"), conversation: { link_id: "link-2", message_id: "m-2" } },
          sender_phone: kind === "call" ? "+30 690 000 0000" : null,
        }),
      );
    });
    await page.route("**/api/me/buddies/link-2/messages**", (route) =>
      route.fulfill(
        json({
          messages: [
            { id: "m-2", link_id: "link-2", author: person("member-1", "Maria"), body: "I'm here", mine: true, read_at: null, created_at: new Date().toISOString() },
            { id: "m-1", link_id: "link-2", author: person("u-3", "Eleni"), body: "Rough evening.", mine: false, read_at: null, created_at: new Date(Date.now() - 60_000).toISOString() },
          ],
          next_cursor: null,
          read_only: false,
          unread: 0,
        }),
      ),
    );

    await page.goto("/me/buddy/support/req-9");
    await expect(page.getByTestId("support-request-card")).toContainText("Eleni is having a hard moment");
    await page.getByRole("button", { name: "Call me" }).click();
    await expect(page.getByTestId("sender-phone")).toContainText("+30 690 000 0000");
    await expect(page.getByRole("link", { name: "Call Eleni" })).toHaveAttribute("href", "tel:+306900000000");

    const reply = page.waitForRequest((call) => call.url().endsWith("/me/support-requests/req-9/replies") && bodyOf(call).kind === "here");
    await page.getByRole("button", { name: "I'm here" }).click();
    await reply;
    await expect(page).toHaveURL(/\/me\/buddy\/link-2\/chat$/);
    await expect(page.getByTestId("buddy-chat")).toContainText("Rough evening.");
    await expect(page.getByRole("textbox", { name: "Write a message" })).toBeVisible();
  });

  test("ten minutes without a reply bring the calm card", async ({ page }) => {
    const waiting = supportRequest({
      status: "delivered",
      can_undo: false,
      undo_until: null,
      created_at: new Date(Date.now() - 11 * 60_000).toISOString(),
      message: "Hard evening.",
    });
    waiting.nudge = { ...waiting.nudge, due: true, due_at: new Date(Date.now() - 60_000).toISOString() };
    await common(page, { buddies: () => overview({ buddies: [link("link-1", "Eleni")] }) });
    await wellnessPage(page);
    await page.route("**/api/me/support-requests?**", (route) => route.fulfill(json({ support_requests: [waiting] })));
    await page.route("**/api/me/support-requests/req-1", (route) => route.fulfill(json({ support_request: waiting })));
    await page.route("**/api/me/support-requests", (route) =>
      route.request().method() === "POST" ? route.fulfill(json({ support_request: supportRequest({ id: "req-2", message: "Hard evening." }) })) : route.fallback(),
    );

    await page.goto("/journal/wellbeing");
    const card = page.getByTestId("no-reply-card");
    await expect(card).toContainText("No one has replied yet");
    await card.getByRole("button", { name: "Breathe for 2′" }).click();
    await card.getByRole("button", { name: "Start" }).click();
    await expect(page.getByTestId("breath-phase")).toContainText("Breathe in");
    await expect(card.getByRole("link", { name: /./ }).last()).toHaveAttribute("href", "/help/support-lines");

    const again = page.waitForRequest((request) => request.url().endsWith("/api/me/support-requests") && request.method() === "POST");
    await card.getByRole("button", { name: "Send again" }).click();
    expect(bodyOf(await again)).toEqual({ message: "Hard evening." });
  });

  test("the member chooses what the coach's weekly summary shows", async ({ page }) => {
    let sharing = { wellness: false, cravings: false, wellness_since: null as string | null, cravings_since: null as string | null };
    const saved: unknown[] = [];
    await common(page);
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
    await page.route("**/api/me/wellness-summary-sharing", (route) => {
      if (route.request().method() === "PUT") {
        const body = bodyOf(route.request());
        saved.push(body);
        sharing = { ...sharing, ...body };
      }
      return route.fulfill(json({ sharing }));
    });
    await page.route("**/api/me/wellness-summary-sharing/access-log", (route) =>
      route.fulfill(
        json({
          entries: [
            { id: "log-1", reader: { id: "coach-1", nickname: "Kostas" }, organization: { id: "org-1", name: "Box Kypseli" }, read_at: new Date().toISOString(), week_start: today, shared: true, cravings_shown: false },
          ],
        }),
      ),
    );

    await page.goto("/me/sharing");
    const section = page.getByTestId("wellness-summary-sharing");
    const wellness = section.getByRole("switch", { name: /Wellness · weekly summary/ });
    const cravings = section.getByRole("switch", { name: /Cravings in the summary/ });
    await expect(wellness).not.toBeChecked();
    await expect(cravings).toBeDisabled();
    await wellness.click();
    await expect(wellness).toBeChecked();
    await expect(cravings).toBeEnabled();
    await cravings.click();
    await expect(cravings).toBeChecked();
    expect(saved).toEqual([expect.objectContaining({ wellness: true }), expect.objectContaining({ cravings: true })]);
    await expect(page.getByTestId("wellness-access-log")).toContainText("Kostas");
  });

  test("the coach reads the shared summary on the client's profile", async ({ page }) => {
    const weeks: string[] = [];
    await common(page, { role: "coach" });
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
    await page.route("**/api/org/*/staff/clients/u-1/wellness-summary**", (route) => {
      weeks.push(new URL(route.request().url()).searchParams.get("week") ?? "");
      return route.fulfill(
        json({
          shared: true,
          summary: {
            week_start: today,
            week_end: today,
            allowed_since: "2026-10-01T09:00:00Z",
            sleep: { nights_logged: 5, nights_on_goal: 3 },
            water: { days_logged: 6, days_on_goal: 4 },
            meals: { days_logged: 7 },
            cravings: { count: 2, moments: [{ date: today, time: "21:30" }] },
          },
        }),
      );
    });

    await page.goto("/admin/users/u-1?tab=wellbeing");
    const panel = page.getByTestId("coach-wellness-summary");
    await expect(panel).toContainText("Nights at the sleep goal: 3 of 5");
    await expect(panel).toContainText("Cravings: 2");
    await panel.getByRole("button", { name: "Previous week" }).click();
    await expect.poll(() => weeks.some((week) => week.length === 10)).toBe(true);
  });
});
