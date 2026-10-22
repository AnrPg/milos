import { expect, test, type Page, type Request } from "./support/test";

// Redesign Phase 3 M6 (ADR-168): PT squads. A client answers an invitation
// from Box and from the club's Channels, opens the squad and leaves it; the
// coach starts a squad with some of their clients and invites more. The API is
// stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

function persona(id: string, nickname: string, roles: string[]) {
  const user = {
    id,
    nickname,
    role: "member",
    email: `${id}@example.com`,
    completed_tours: ["admin", "member", "athlete"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: roles[0], settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature`, roles };
}

const coach = { id: "coach-1", nickname: "Nikos", avatar_url: null };
const anna = { id: "client-1", nickname: "Anna", avatar_url: null };
const petros = { id: "client-2", nickname: "Petros", avatar_url: null };

const squad = (extra: Record<string, unknown> = {}) => ({
  id: "squad-1",
  club_id: "club-1",
  name: "Hyrox crew",
  description: "Saturday sessions",
  coach,
  member_count: 2,
  invite_count: 0,
  archived_at: null,
  role: "member",
  can_manage: false,
  ...extra,
});

const overview = (extra: Record<string, unknown> = {}) => ({
  organization_id: "org-1",
  can_create: false,
  limits: { max_members: 30, max_live_squads: 20 },
  coached: [],
  archived: [],
  joined: [],
  invites: [],
  clients: [],
  ...extra,
});

const channel = (id: string, kind: string, extra: Record<string, unknown> = {}) => ({
  id,
  kind,
  name: null,
  write_policy: "members",
  membership: "everyone",
  joined: true,
  participant: false,
  can_post: true,
  can_leave: false,
  ...extra,
});

function gymClub(withSquad: boolean) {
  return {
    id: "club-1",
    kind: "gym",
    name: "Box Kypseli",
    organization_id: "org-1",
    organization_slug: "kypseli",
    role: "member",
    notify_level: "all",
    logo_url: null,
    primary_color: null,
    channels: [
      channel("ch-ann", "announcements", { write_policy: "staff", can_post: false }),
      ...(withSquad
        ? [channel("squad-1", "pt_squad", { name: "Hyrox crew", write_policy: "participants", membership: "invite", participant: true })]
        : []),
    ],
  };
}

async function common(page: Page, who: ReturnType<typeof persona>) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: who.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(who.user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: who.roles[0],
          roles: who.roles,
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-21", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
}

/** A client with one invitation; accepting it puts them in the squad. */
async function client(page: Page) {
  const calls: { answers: unknown[]; left: number } = { answers: [], left: 0 };
  let accepted = false;
  await common(page, persona("client-1", "Anna", ["member"]));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [gymClub(accepted)] })));
  await page.route("**/api/org/kypseli/community/squads", (route) =>
    route.fulfill(
      json(
        accepted
          ? overview({ joined: [squad()] })
          : overview({ invites: [squad({ role: "invited", member_count: 1 })] }),
      ),
    ),
  );
  await page.route("**/api/org/kypseli/community/squads/squad-1", (route) =>
    route.fulfill(
      json({
        squad: accepted
          ? squad({ members: [{ person: anna, status: "member", since: "2026-10-21T10:00:00Z" }, { person: petros, status: "member", since: "2026-10-21T10:00:00Z" }] })
          : squad({ role: "invited", member_count: 1, members: [] }),
      }),
    ),
  );
  await page.route("**/api/org/kypseli/community/squads/squad-1/invite", (route) => {
    const body = bodyOf(route.request());
    calls.answers.push(body);
    accepted = body.accept === true;
    return route.fulfill(json(accepted ? { squad: squad() } : { squad_id: "squad-1", outcome: "declined" }));
  });
  await page.route("**/api/org/kypseli/community/squads/squad-1/membership", (route) => {
    calls.left += 1;
    accepted = false;
    return route.fulfill(json({ squad_id: "squad-1", outcome: "left" }));
  });
  return calls;
}

test.describe("PT squads", () => {
  test("a client accepts an invitation from Channels, then opens the squad and leaves it", async ({ page }) => {
    const calls = await client(page);
    await page.goto("/clubs/club-1");
    await page.getByRole("tab", { name: "Channels" }).click();

    const invite = page.getByTestId("squad-invite");
    await expect(invite).toContainText("Hyrox crew");
    await expect(invite).toContainText("Nikos invited you");
    await invite.getByRole("button", { name: "Join" }).click();
    await expect.poll(() => calls.answers).toEqual([{ accept: true }]);

    // Now a squad row in the card, not an invitation; squads aren't listed with other channels.
    const row = page.getByRole("link", { name: /Hyrox crew/ });
    await expect(row).toContainText("With Nikos");
    await expect(page.getByText("Other channels")).toHaveCount(0);
    await row.click();

    await expect(page).toHaveURL(/\/clubs\/club-1\/squads\/squad-1$/);
    await expect(page.getByText("Only Nikos and the squad's members see what's posted here.")).toBeVisible();
    await page.getByRole("tab", { name: "People" }).click();
    await expect(page.getByRole("link", { name: /Petros/ })).toBeVisible();
    await expect(page.getByText("Coach", { exact: true })).toBeVisible();

    await page.getByRole("button", { name: "Leave", exact: true }).click();
    const sheet = page.getByRole("dialog", { name: "Leave this squad?" });
    await sheet.getByRole("button", { name: "Leave" }).click();
    await expect.poll(() => calls.left).toBe(1);
    await expect(page).toHaveURL(/\/clubs\/club-1$/);
  });

  test("an invited client opening the squad sees only the invitation and can decline", async ({ page }) => {
    const calls = await client(page);
    await page.goto("/clubs/club-1/squads/squad-1");

    await expect(page.getByText("Nikos invited you to this squad. Join to see its posts and people.")).toBeVisible();
    await expect(page.getByRole("tab", { name: "Posts" })).toHaveCount(0);
    await page.getByRole("button", { name: "Decline" }).click();
    await expect.poll(() => calls.answers).toEqual([{ accept: false }]);
    await expect(page).toHaveURL(/\/clubs\/club-1$/);
  });

  test("a client answers from Box", async ({ page }) => {
    const calls = await client(page);
    await page.goto("/box");

    const invite = page.getByTestId("squad-invite");
    await expect(invite).toContainText("Hyrox crew");
    await invite.getByRole("button", { name: "Join" }).click();
    await expect.poll(() => calls.answers).toEqual([{ accept: true }]);
    await expect(page.getByRole("link", { name: /Hyrox crew/ })).toHaveAttribute("href", "/clubs/club-1/squads/squad-1");
  });

  test("a coach starts a squad with some clients, then invites another and withdraws it", async ({ page }) => {
    const created: unknown[] = [];
    const invited: unknown[] = [];
    const withdrawn: string[] = [];
    let mine: Record<string, unknown>[] = [squad({ id: "squad-0", name: "Morning PT", role: "coach", can_manage: true, member_count: 3 })];
    await common(page, persona("coach-1", "Nikos", ["coach"]));
    await page.route("**/api/me/clubs", (route) =>
      route.fulfill(json({ clubs: [{ ...gymClub(true), role: "staff", channels: gymClub(true).channels.map((c) => ({ ...c, can_post: true })) }] })),
    );
    await page.route("**/api/org/kypseli/community/squads", (route) => {
      if (route.request().method() === "POST") {
        created.push(bodyOf(route.request()));
        mine = [...mine, squad({ role: "coach", can_manage: true, member_count: 0, invite_count: 1 })];
        return route.fulfill(json({ squad: squad({ role: "coach", can_manage: true, member_count: 0, invite_count: 1 }) }, 201));
      }
      return route.fulfill(json(overview({ can_create: true, coached: mine, clients: [petros, anna] })));
    });
    let members = [{ person: anna, status: "member", since: "2026-10-21T10:00:00Z" }];
    await page.route("**/api/org/kypseli/community/squads/squad-1", (route) =>
      route.fulfill(json({ squad: squad({ role: "coach", can_manage: true, member_count: 1, invite_count: members.length - 1, members }) })),
    );
    await page.route("**/api/org/kypseli/community/squads/squad-1/invites", (route) => {
      invited.push(bodyOf(route.request()));
      members = [...members, { person: petros, status: "invited", since: "2026-10-21T10:00:00Z" }];
      return route.fulfill(json({ squad: squad({ role: "coach", members }) }));
    });
    await page.route("**/api/org/kypseli/community/squads/squad-1/members/client-2", (route) => {
      withdrawn.push("client-2");
      members = members.filter((row) => row.person.id !== "client-2");
      return route.fulfill(json({ squad: squad({ role: "coach", members }) }));
    });

    await page.goto("/box");
    await expect(page.getByRole("link", { name: /Morning PT/ })).toContainText("3 members");
    await page.getByRole("button", { name: "+ New squad" }).click();
    const sheet = page.getByRole("dialog", { name: "New squad" });
    await sheet.getByLabel("Name").fill("Hyrox crew");
    await sheet.getByRole("checkbox", { name: "Anna" }).check();
    await sheet.getByRole("button", { name: "Create" }).click();
    await expect.poll(() => created).toEqual([{ name: "Hyrox crew", description: null, client_ids: ["client-1"] }]);
    await expect(sheet).toHaveCount(0);
    await expect(page.getByRole("link", { name: /Hyrox crew/ })).toContainText("1 invitation open");

    await page.goto("/clubs/club-1/squads/squad-1");
    await expect(page.getByText("Only your active clients can be in it. When coaching ends, they leave the squad.")).toBeVisible();
    await page.getByRole("button", { name: "Invite", exact: true }).click();
    const invite = page.getByRole("dialog", { name: "Invite clients" });
    await expect(invite.getByRole("checkbox")).toHaveCount(1);
    await invite.getByRole("checkbox", { name: "Petros" }).check();
    await invite.getByRole("button", { name: "Invite" }).click();
    await expect.poll(() => invited).toEqual([{ user_ids: ["client-2"] }]);

    await page.getByRole("tab", { name: "People" }).click();
    await expect(page.getByText("Invited", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Withdraw" }).click();
    await expect.poll(() => withdrawn).toEqual(["client-2"]);
  });
});
