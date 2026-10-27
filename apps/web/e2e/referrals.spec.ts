import { createServer, type Server } from "node:http";

import { expect, test, type Page } from "./support/test";

import { stubApiPort } from "../playwright.config";

// Redesign Phase 2 M8 (ADR-156, plan board 11): member referrals. A member's
// «Bring a friend» (the offer, the link and its QR, an event invite, how each
// friend is doing, a new link), the friend's invite page signed out and
// signed in (the invite is kept on the device and claimed), and staff's
// queue in Finance › Referrals. The API is stubbed; the invite page's
// server-side read goes to a stub server.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const CODE = "AB12CD34";
const EVENT_ID = "2b0f8f8e-3f7c-4bd4-9b0e-6a4c1d7e9a10";

const publicInvite = {
  invite: {
    code: CODE,
    box: {
      slug: "kypseli",
      name: "Box Kypseli",
      logo_url: null,
      primary_color: "#D9743D",
      published: true,
      cover: null,
      disciplines: ["crossfit"],
      neighbourhood: "Kypseli",
    },
    inviter: { nickname: "Maria", avatar_url: null },
    gift: { type: "free_days", value: 7, note: null },
    window_days: 30,
    trials_enabled: true,
  },
};

let server: Server;

test.beforeAll(async () => {
  server = createServer((request, response) => {
    if (request.url === `/api/public/referrals/${CODE}`) {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify(publicInvite));
      return;
    }
    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: "not_found" }));
  });
  await new Promise<void>((resolve) => server.listen(stubApiPort, "127.0.0.1", resolve));
});

test.afterAll(async () => {
  await new Promise((resolve) => server.close(resolve));
});

const inDays = (days: number, hour = 10) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
};

function personaFor(id: string, nickname: string, role: "member" | "admin", slugs: string[]) {
  const user = {
    id,
    nickname,
    role,
    email: `${id}@example.com`,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: slugs.map((slug) => ({ organization_slug: slug, role: role === "admin" ? "owner" : "member", settings: {} })),
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role, memberships: slugs.map((slug) => ({ organization_slug: slug })), exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = (role: string, capabilities: Record<string, string> = {}) => ({
  role,
  roles: [role],
  capabilities,
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
});

async function common(page: Page, persona: ReturnType<typeof personaFor> | null, memberships: unknown[] = []) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  // Copying, not the system share sheet, so the link can be read back.
  await page.addInitScript(() => Object.defineProperty(navigator, "share", { value: undefined, configurable: true }));
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  if (persona) {
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
    await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  } else {
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
    await page.route("**/api/auth/me", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
  }
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
}

function overview(invites: unknown[] = []) {
  return {
    code: CODE,
    path: `/r/${CODE}`,
    earns_rewards: true,
    program: {
      id: "program-1",
      name: "October",
      reward: { type: "credit", value: 2000, note: null },
      gift: { type: "free_days", value: 7, note: null },
      qualifying_stage: "paid",
      attribution_days: 30,
      yearly_cap: 5,
    },
    events: [
      {
        id: EVENT_ID,
        title: "Open WOD",
        starts_at: inDays(4, 10),
        ends_at: inDays(4, 11),
        price_cents: 0,
        currency: "EUR",
        place_name: "Box Kypseli",
        access: "open",
        good_for_friends: false,
      },
      {
        id: "event-friends",
        title: "Bring a friend WOD",
        starts_at: inDays(9, 11),
        ends_at: inDays(9, 12),
        price_cents: 0,
        currency: "EUR",
        place_name: "Box Kypseli",
        access: "open",
        good_for_friends: true,
      },
    ],
    invites,
    totals: { invited: invites.length, trials: 1, paid: 1 },
  };
}

const invite = (id: string, nickname: string, stage: string, reward: Record<string, unknown> | null) => ({
  id,
  friend: { id: `friend-${id}`, nickname, avatar_url: null },
  stage,
  stage_at: inDays(-2),
  status: stage === "paid" ? "qualified" : "open",
  channel: "link",
  attributed_at: inDays(-10),
  expires_at: inDays(20),
  reward,
});

test.describe("referrals", () => {
  test("a member shares their link and QR, invites to an event and follows their friends", async ({ page, context }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    const persona = personaFor("member-1", "Maria", "member", ["kypseli"]);
    await common(page, persona, [membership("member")]);
    let rotations = 0;
    await page.route("**/api/org/kypseli/me/referrals", (route) =>
      route.fulfill(
        json(
          overview([
            invite("a", "Katerina", "paid", { type: "credit", value: 2000, status: "given" }),
            invite("b", "Giorgos", "trial", { type: "credit", value: 2000, status: "upcoming" }),
            invite("c", "Sofia", "signed_up", { type: "credit", value: 2000, status: "upcoming" }),
          ]),
        ),
      ),
    );
    await page.route("**/api/org/kypseli/me/referrals/code", (route) => {
      rotations += 1;
      return route.fulfill(json({ code: "ZZ99YY88", path: "/r/ZZ99YY88" }, 201));
    });

    await page.goto("/me/referrals");
    await expect(page.getByRole("heading", { name: "Bring a friend", level: 1 })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Your friend: 7 days free" })).toBeVisible();
    await expect(page.getByText("You: €20 credit, when they subscribe")).toBeVisible();
    await expect(page.getByText("Up to 5 friends a year")).toBeVisible();
    await expect(page.getByRole("tab", { name: "Invite", exact: true })).toHaveAttribute("aria-selected", "true");

    const list = page.getByRole("listitem");
    await expect(list.filter({ hasText: "Bring a friend WOD" })).toContainText("Good for friends");

    await page.getByRole("button", { name: "Share link" }).click();
    await expect(page.getByRole("button", { name: "Link copied" })).toBeVisible();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toMatch(new RegExp(`/r/${CODE}$`));

    // ADR-210: the same link, sent by email from the address the member types.
    const emailed: unknown[] = [];
    await page.route("**/api/me/share-links/email", (route) => {
      emailed.push(route.request().postDataJSON());
      return route.fulfill(json({ delivery: { id: "message-1", status: "queued" } }, 202));
    });
    await page.getByRole("button", { name: "Send by email" }).click();
    await page.getByLabel("Their email address").fill("friend@example.com");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect(page.getByText("Sent to friend@example.com")).toBeVisible();
    expect(emailed).toEqual([{ link: "referral", token: CODE, to: "friend@example.com" }]);

    await list.filter({ hasText: "Open WOD" }).getByRole("button", { name: "Invite" }).click();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toMatch(new RegExp(`/r/${CODE}\\?event=${EVENT_ID}$`));

    await page.getByRole("button", { name: "Show QR" }).click();
    const qr = page.getByRole("dialog", { name: "Your invite QR" });
    await expect(qr.getByRole("img", { name: "QR code of your invite link" })).toBeVisible();
    await expect(qr.getByText(CODE)).toBeVisible();
    // The header × and the footer button both close it.
    await qr.getByRole("button", { name: "Close" }).first().click();

    await page.getByRole("button", { name: "New link" }).click();
    await page.getByRole("button", { name: "Make a new link" }).click();
    await expect.poll(() => rotations).toBe(1);

    await page.getByRole("tab", { name: "Your invites · 3" }).click();
    await expect(page).toHaveURL(/tab=invites/);
    await expect(list.filter({ hasText: "Katerina" })).toContainText("You got €20 credit");
    await expect(list.filter({ hasText: "Katerina" })).toContainText("Given");
    await expect(list.filter({ hasText: "Giorgos" })).toContainText("Came to a trial");
    await expect(list.filter({ hasText: "Sofia" })).toContainText("Signed up");
    await expect(page.getByRole("button", { name: "Share link" })).toHaveCount(0);
  });

  test("signed out, a friend sees who invites them and what they get, and the invite is kept", async ({ page }) => {
    await common(page, null);
    await page.goto(`/r/${CODE}`);

    await expect(page.getByText("Maria invites you to train at Box Kypseli")).toBeVisible();
    await expect(page.getByText("For you: 7 days free")).toBeVisible();
    await expect(page.getByText(/Maria will see your first name/)).toBeVisible();
    await expect(page.getByRole("link", { name: "Create an account" })).toHaveAttribute("href", `/register?next=${encodeURIComponent(`/r/${CODE}`)}`);

    const kept = await page.evaluate(() => window.localStorage.getItem("palee:pending-referrals"));
    expect(JSON.parse(kept ?? "[]")).toMatchObject([{ code: CODE, channel: "link", event_id: null }]);
  });

  test("signed in, opening an event invite claims it and offers the event and a trial", async ({ page }) => {
    await common(page, personaFor("friend-1", "Nikos", "member", []));
    const claims: unknown[] = [];
    await page.route("**/api/referrals/claim", (route) => {
      claims.push(route.request().postDataJSON());
      return route.fulfill(json({ outcome: "claimed", box: { slug: "kypseli", name: "Box Kypseli" } }));
    });

    await page.goto(`/r/${CODE}?event=${EVENT_ID}`);
    await expect(page.getByText("Done. Your invite to Box Kypseli is saved.")).toBeVisible();
    await expect(page.getByRole("link", { name: "See the event" })).toHaveAttribute("href", `/events/${EVENT_ID}`);
    await expect(page.getByRole("link", { name: "Book a trial" })).toHaveAttribute("href", "/b/kypseli?trial=1");
    expect(claims).toEqual([{ code: CODE, channel: "event", event_id: EVENT_ID }]);
    expect(await page.evaluate(() => window.localStorage.getItem("palee:pending-referrals"))).toBeNull();
  });

  test("an invite that no longer works says so", async ({ page }) => {
    await common(page, null);
    await page.goto("/r/ZZ99YY88");
    await expect(page.getByText("This invite isn't active any more")).toBeVisible();
  });

  test("staff approve a friend's subscription from Finance › Referrals", async ({ page }) => {
    const persona = personaFor("owner-1", "Apostolos", "admin", ["kypseli"]);
    await common(page, persona, [membership("owner", { manage_promotions: "all", view_promotions: "all", manage_settings: "all" })]);
    let current = {
      ...invite("a", "Katerina", "paid", { type: "credit", value: 2000, status: "pending" }),
      referrer: { id: "member-1", nickname: "Maria", avatar_url: null },
      previous_referrer: null,
      steps: { event_at: null, trial_at: inDays(-6), joined_at: inDays(-3), paid_at: inDays(-2) },
      new_account: true,
      community_event_id: null,
      void_reason: null,
      notes: null,
      reassigned_at: null,
      referral_event_id: "event-a",
      program: { id: "program-1", name: "October" },
      friend_gift: { type: "free_days", value: 7, note: null },
      friend_gift_applied_at: null,
    };
    const approvals: string[] = [];
    await page.route("**/api/org/kypseli/admin/finance/package-catalog", (route) => route.fulfill(json({ types: [], modules: [] })));
    // The branch filter reads the branches; `{}` there logs an error whose dev
    // overlay badge sits over the sheet's Approve button on a phone.
    await page.route("**/api/org/kypseli/admin/locations", (route) => route.fulfill(json({ locations: [] })));
    await page.route(/\/api\/org\/kypseli\/admin\/referrals\?filter=review$/, (route) =>
      route.fulfill(json({ invites: current.reward?.status === "pending" ? [current] : [], stats: { open: 3, qualified: 1 } })),
    );
    await page.route("**/api/org/kypseli/admin/referrals/a/approve", (route) => {
      approvals.push("a");
      current = { ...current, reward: { type: "credit", value: 2000, status: "given" } };
      return route.fulfill(json({ invite: current }));
    });

    await page.goto("/org/kypseli/admin/finance?tab=referrals");
    await expect(page.getByText("Last 90 days: 3 on the way · 1 counted · 0 expired")).toBeVisible();
    await page.getByRole("button", { name: /Katerina ← Maria/ }).click();
    await expect(page.getByText("Came to a trial")).toBeVisible();
    await expect(page.getByText("€20 credit")).toBeVisible();
    await page.getByRole("button", { name: "Approve" }).click();

    await expect(page.getByText("Nothing to approve.")).toBeVisible();
    expect(approvals).toEqual(["a"]);
  });
});
