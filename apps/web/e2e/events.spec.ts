import { expect, test, type Page } from "./support/test";

// Redesign Phase 2 M5 (ADR-153, plan board 8): club events. The club's
// Events tab with «+ New event», «I'm in» turning into the waitlist when
// full, a friend's guest pass link, the feed card's inline «I'm in» and the
// staff attendee list (came, paid at the box, trial offer). The API is
// stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const inDays = (days: number, hour = 10) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
};

function personaFor(role: "member" | "admin", membershipRole: string) {
  const user = {
    id: role === "member" ? "member-1" : "owner-1",
    nickname: role === "member" ? "Maria" : "Apostolos",
    role,
    email: `${role}@example.com`,
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

const membership = (role: string, capabilities: Record<string, string>) => ({
  role,
  roles: [role],
  capabilities,
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
});

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

const gymClub = (role: "member" | "staff") => ({
  id: "club-1",
  kind: "gym",
  name: "Box Kypseli",
  organization_id: "org-1",
  organization_slug: "kypseli",
  role,
  notify_level: "all",
  logo_url: null,
  primary_color: null,
  channels: [channel("ch-ann", "announcements", { write_policy: "staff", can_post: false }), channel("ch-wod", "wod")],
});

function communityEvent(overrides: Record<string, unknown> = {}) {
  return {
    id: "event-1",
    organization_id: "org-1",
    club_id: "club-1",
    club: { id: "club-1", name: "Box Kypseli", kind: "gym" },
    box: { name: "Box Kypseli", slug: "kypseli", logo_url: null },
    title: "Saturday partner WOD",
    description: "Bring a partner, or find one there.",
    starts_at: inDays(3, 10),
    ends_at: inDays(3, 11),
    place: { name: "Box Kypseli", address: "Fokionos Negri 1", latitude: null, longitude: null, location_id: "loc-1" },
    capacity: 12,
    spots_left: 4,
    going_count: 8,
    waitlist_count: 0,
    price_cents: 0,
    currency: "EUR",
    open_to_non_members: false,
    guest_pass_allowed: false,
    guests_per_member: 0,
    guests_left: null,
    goers: [
      { id: "member-2", nickname: "Eleni", avatar_url: null },
      { id: "member-3", nickname: "Petros", avatar_url: null },
    ],
    cancelled: false,
    can_rsvp: true,
    can_manage: false,
    channel_id: null,
    group: null,
    my: null,
    ...overrides,
  };
}

const going = { status: "going", source: "member", paid: false, late_cancel: false };

async function common(page: Page, persona: ReturnType<typeof personaFor>, memberships: unknown[]) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
}

type Calls = { rsvps: unknown[]; created: unknown[]; invites: number };

/** A member of the box; `staff` makes them a coach who runs the box's events. */
async function member(
  page: Page,
  { staff = false, event = communityEvent(), feed = (() => []) as (current: Record<string, unknown>) => unknown[] } = {},
) {
  const calls: Calls = { rsvps: [], created: [], invites: 0 };
  let current: Record<string, unknown> = event;
  await common(
    page,
    personaFor("member", staff ? "coach" : "member"),
    staff ? [membership("coach", { manage_events: "all" })] : [membership("member", {})],
  );
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [gymClub(staff ? "staff" : "member")] })));
  await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: feed(current), pinned: [], next_cursor: null })));
  await page.route("**/api/boxes/kypseli", (route) =>
    route.fulfill(json({ slug: "kypseli", name: "Box Kypseli", locations: [{ id: "loc-1", name: "Box Kypseli" }] })),
  );
  await page.route("**/api/me/community/clubs/club-1/events**", (route) => {
    if (route.request().method() === "POST") {
      const body = route.request().postDataJSON();
      calls.created.push(body);
      return route.fulfill(json({ event: communityEvent({ ...body, id: "event-2", going_count: 0, goers: [] }), occurrences: 1 }, 201));
    }
    const scope = new URL(route.request().url()).searchParams.get("scope");
    return route.fulfill(json({ events: scope === "past" ? [] : [current] }));
  });
  await page.route("**/api/me/events/event-1?**", (route) => route.fulfill(json({ event: current })));
  await page.route("**/api/me/events/event-1", (route) => route.fulfill(json({ event: current })));
  await page.route("**/api/me/events/event-1/rsvp", (route) => {
    const body = route.request().postDataJSON() as { going: boolean };
    calls.rsvps.push(body);
    const full = current.spots_left === 0;
    current = {
      ...current,
      my: body.going ? { ...going, status: full ? "waitlisted" : "going" } : { ...going, status: "cancelled" },
      going_count: (current.going_count as number) + (body.going && !full ? 1 : 0),
      waitlist_count: (current.waitlist_count as number) + (body.going && full ? 1 : 0),
      guests_left: body.going && current.guest_pass_allowed ? current.guests_per_member : null,
    };
    return route.fulfill(json({ event: current }));
  });
  await page.route("**/api/me/events/event-1/invites", (route) => {
    calls.invites += 1;
    return route.fulfill(
      json({ token: "guest-token", path: "/events/event-1?invite=guest-token", guests_left: 2, expires_at: inDays(3, 11) }, 201),
    );
  });
  return calls;
}

test.describe("events", () => {
  test("the club's Events tab lists upcoming events, and a coach creates one from «+ New event»", async ({ page }) => {
    const calls = await member(page, { staff: true });
    await page.goto("/clubs/club-1");

    await page.getByRole("tablist", { name: "Box Kypseli" }).getByRole("tab", { name: "Events" }).click();
    const scopes = page.getByRole("tablist", { name: "Which events" });
    await expect(scopes.getByRole("tab", { name: "Upcoming" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByRole("link", { name: /Saturday partner WOD/ })).toHaveAttribute("href", "/events/event-1");

    await page.getByRole("button", { name: "+ New event" }).click();
    // The event wizard: one decision per screen, Next waits until the step is filled in.
    const sheet = page.getByRole("dialog", { name: "New event" });
    const next = sheet.getByRole("button", { name: "Next", exact: true });
    await expect(sheet.getByRole("heading", { name: "What is it?" })).toBeVisible();
    await expect(next).toHaveAttribute("aria-disabled", "true");
    await sheet.getByLabel("Title").fill("Run up Lycabettus");
    await next.click();
    await expect(sheet.getByRole("heading", { name: "When is it?" })).toBeVisible();
    await next.click();
    await sheet.getByRole("radio", { name: "Another address" }).click();
    await sheet.getByLabel("Place name").fill("Lycabettus Hill");
    await next.click();
    await sheet.getByRole("radio", { name: /Paid/ }).click();
    await sheet.getByLabel("Amount (€)").fill("15");
    await next.click();
    await sheet.getByLabel("Places", { exact: true }).fill("20");
    await next.click();
    await expect(sheet.getByRole("heading", { name: "Check and publish" })).toBeVisible();
    await expect(sheet.getByText("Lycabettus Hill")).toBeVisible();
    await sheet.getByRole("button", { name: "Publish" }).click();

    await expect(sheet).toBeHidden();
    expect(calls.created).toHaveLength(1);
    expect(calls.created[0]).toMatchObject({
      title: "Run up Lycabettus",
      location_id: null,
      place_name: "Lycabettus Hill",
      capacity: 20,
      price_cents: 1500,
      open_to_non_members: false,
    });
  });

  test("a full event offers the waitlist, and «Join the waitlist» puts you on it", async ({ page }) => {
    const calls = await member(page, { event: communityEvent({ spots_left: 0, going_count: 12, waitlist_count: 1 }) });
    await page.goto("/events/event-1");

    await expect(page.getByRole("heading", { name: "Saturday partner WOD" })).toBeVisible();
    await expect(page.getByText("Full · 1 waiting")).toBeVisible();
    await page.getByRole("button", { name: "Join the waitlist" }).click();

    await expect(page.getByText(/You're on the waitlist/)).toBeVisible();
    await expect(page.getByRole("button", { name: "Leave the waitlist" })).toBeVisible();
    expect(calls.rsvps).toEqual([{ going: true }]);
  });

  test("a friend's guest pass link shows who invites you and joins you as their guest", async ({ page }) => {
    const calls = await member(page, {
      event: communityEvent({
        open_to_non_members: false,
        guest_pass_allowed: true,
        guests_per_member: 2,
        invitation: { inviter: { id: "member-2", nickname: "Eleni", avatar_url: null }, usable: true, reason: null },
      }),
    });
    await page.goto("/events/event-1?invite=guest-token");

    await expect(page.getByText("Eleni is inviting you")).toBeVisible();
    await page.getByRole("button", { name: "I'm in" }).click();
    await expect(page.getByText("You're going ✓")).toBeVisible();
    expect(calls.rsvps).toEqual([{ going: true, invite_token: "guest-token" }]);

    // Going now, they bring a friend of their own.
    await page.getByRole("button", { name: "Bring a friend" }).click();
    const sheet = page.getByRole("dialog", { name: "Bring a friend" });
    await expect(sheet.getByLabel("Invitation link")).toHaveValue(/\/events\/event-1\?invite=guest-token$/);
    await expect(page.getByText("2 guests left")).toBeVisible();
    expect(calls.invites).toBe(1);

    // ADR-210: or by email, with the same guest pass.
    const emailed: unknown[] = [];
    await page.route("**/api/me/share-links/email", (route) => {
      emailed.push(route.request().postDataJSON());
      return route.fulfill(json({ delivery: { id: "message-1", status: "queued" } }, 202));
    });
    await sheet.getByRole("button", { name: "Send by email" }).click();
    await sheet.getByLabel("Their email address").fill("guest@example.com");
    await sheet.getByRole("button", { name: "Send", exact: true }).click();
    await expect(sheet.getByText("Sent to guest@example.com")).toBeVisible();
    expect(emailed).toEqual([{ link: "guest_pass", token: "guest-token", to: "guest@example.com" }]);
  });

  test("signed out, a guest pass link signs in and comes back to the invitation", async ({ page }) => {
    await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
    await page.goto("/events/event-1?invite=guest-token");

    await expect(page).toHaveURL(/\/login\?next=%2Fevents%2Fevent-1%3Finvite%3Dguest-token$/);
  });

  test("the feed's event card answers «I'm in» in place", async ({ page }) => {
    const event = communityEvent({ post_id: "post-1" });
    const calls = await member(page, {
      event,
      feed: (current) => [
        {
          id: "post-1",
          origin: "club",
          audience: "club_channel",
          author: { id: "coach-1", nickname: "Stelios", avatar_url: null },
          body: "",
          attachment: { title: event.title, starts_at: event.starts_at },
          attachment_id: "event-1",
          attachment_type: "event",
          event: current,
          can_delete: false,
          can_moderate: false,
          can_pin: false,
          can_report: false,
          channel: { id: "ch-ann", kind: "announcements", name: null },
          club: { id: "club-1", name: "Box Kypseli", organization_slug: "kypseli", kind: "gym" },
          comment_count: 0,
          hidden: false,
          inserted_at: new Date().toISOString(),
          kudos_by_me: false,
          kudos_count: 0,
          pinned: false,
        },
      ],
    });
    await page.goto("/clubs/club-1");

    await expect(page.getByRole("link", { name: /Saturday partner WOD/ })).toBeVisible();
    await page.getByRole("button", { name: "I'm in" }).click();
    await expect(page.getByRole("link", { name: "You're going ✓" })).toHaveAttribute("href", "/events/event-1");
    expect(calls.rsvps).toEqual([{ going: true }]);
  });
});

test.describe("staff events", () => {
  test("staff mark who came and who paid at the box, and send the trial offer once", async ({ page }) => {
    const sent: { checkIns: unknown[]; paid: unknown[]; trial: number } = { checkIns: [], paid: [], trial: 0 };
    const attendee = (id: string, nickname: string, extra: Record<string, unknown> = {}) => ({
      person: { id, nickname, avatar_url: null },
      status: "going",
      source: "member",
      member: true,
      late_cancel: false,
      late_cancels_90d: 0,
      queued_at: inDays(-5),
      receipt_issued: false,
      checked_in_at: null,
      paid_at: null,
      payment_method: null,
      ...extra,
    });
    let event: Record<string, unknown> = {
      ...communityEvent({ starts_at: inDays(-2, 10), ends_at: inDays(-2, 11), price_cents: 1500, going_count: 2, can_manage: true }),
      stats: { going: 2, came: 0, no_shows: 2, late_cancels: 1, waitlisted: 0, guests: 1, paid: 0, trial_requests: 0, converted: 0 },
      trial_offer: { can_send: true, recipients: 1, sent_at: null },
      attendees: {
        going: [attendee("member-2", "Eleni"), attendee("guest-1", "Nikos", { source: "guest", member: false, invited_by: { id: "member-2", nickname: "Eleni" } })],
        waitlisted: [],
        cancelled: [attendee("member-3", "Petros", { status: "cancelled", late_cancel: true, cancelled_at: inDays(-2, 9), late_cancels_90d: 2 })],
      },
    };
    const withAttendee = (userId: string, patch: Record<string, unknown>) => {
      const attendees = event.attendees as { going: { person: { id: string } }[] };
      event = { ...event, attendees: { ...attendees, going: attendees.going.map((row) => (row.person.id === userId ? { ...row, ...patch } : row)) } };
      return json({ event });
    };

    await common(page, personaFor("admin", "owner"), [
      membership("owner", { manage_events: "all", check_in: "all", take_payments: "all", manage_settings: "all" }),
    ]);
    await page.route("**/api/org/kypseli/admin/community/events/event-1", (route) => route.fulfill(json({ event })));
    await page.route("**/api/org/kypseli/admin/community/events/event-1/attendees/*/check-in", (route) => {
      sent.checkIns.push(route.request().postDataJSON());
      return route.fulfill(withAttendee("member-2", { checked_in_at: new Date().toISOString() }));
    });
    await page.route("**/api/org/kypseli/admin/community/events/event-1/attendees/*/paid", (route) => {
      sent.paid.push(route.request().postDataJSON());
      return route.fulfill(withAttendee("member-2", { paid_at: new Date().toISOString(), payment_method: "cash", amount_cents: 1500 }));
    });
    await page.route("**/api/org/kypseli/admin/community/events/event-1/trial-offer", (route) => {
      sent.trial += 1;
      event = { ...event, trial_offer: { can_send: false, recipients: 0, sent_at: new Date().toISOString() } };
      return route.fulfill(json({ sent: 1 }));
    });

    await page.goto("/org/kypseli/admin/community/events/event-1");
    await expect(page.getByRole("heading", { name: "Saturday partner WOD" })).toBeVisible();
    const tabs = page.getByRole("tablist", { name: "Attendees" });
    await expect(tabs.getByRole("tab")).toHaveText(["Going · 2", "Waitlist · 0", "Cancelled · 1", "Came · 0"]);
    await expect(page.getByText("Invited by Eleni")).toBeVisible();

    const eleni = page.getByRole("listitem").filter({ hasText: "Eleni" }).filter({ hasNotText: "Invited by" });
    await eleni.getByRole("button", { name: "Came" }).click();
    await expect(eleni.getByRole("button", { name: "Came" })).toHaveAttribute("aria-pressed", "true");
    await expect(tabs.getByRole("tab", { name: "Came · 1" })).toBeVisible();
    expect(sent.checkIns).toEqual([{ checked_in: true }]);

    await eleni.getByRole("button", { name: "Paid" }).click();
    const paidSheet = page.getByRole("dialog", { name: "Payment at the box" });
    await paidSheet.getByRole("radio", { name: "Cash" }).click();
    await paidSheet.getByRole("button", { name: "Paid" }).click();
    await expect(eleni.getByText("Paid · Cash")).toBeVisible();
    expect(sent.paid).toEqual([{ payment_method: "cash" }]);

    await tabs.getByRole("tab", { name: "Cancelled · 1" }).click();
    await expect(page.getByText(/^Late cancel · /)).toBeVisible();
    await expect(page.getByText("2 late cancels in 90 days")).toBeVisible();

    await page.getByRole("button", { name: "Send trial offer · 1" }).click();
    const trialSheet = page.getByRole("dialog", { name: "Trial offer" });
    await expect(trialSheet.getByText("It goes to 1 person who came. It can only be sent once.")).toBeVisible();
    await trialSheet.getByRole("button", { name: "Send trial offer · 1" }).click();
    await expect(page.getByText("The offer went to 1 person.")).toBeVisible();
    expect(sent.trial).toBe(1);
  });
});
