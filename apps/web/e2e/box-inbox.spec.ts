import { expect, test, type Page } from "./support/test";

// ADR-282: the box answers from one shared inbox. Μηνύματα › Clubs shows
// the box's threads with «Unanswered» first while someone waits, flags a
// newcomer «New», and «Bring in a coach» adds a coach of the box to the
// conversation. The API is stubbed; every route not listed answers {}.

const user = {
  id: "desk-1",
  nickname: "Eleni",
  role: "front_desk",
  email: "desk-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "front_desk", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const boxThread = (id: string, person: string, nickname: string, lastFrom: string, newcomer: boolean) => ({
  id,
  context_type: "box",
  context_id: person,
  created_by_id: person,
  inserted_at: "2026-10-30T08:00:00Z",
  joined_as: "staff",
  participants: [
    { id: `${id}-p`, user_id: person, nickname, last_read_message_id: null, joined_as: "member" },
    { id: `${id}-me`, user_id: user.id, nickname: user.nickname, last_read_message_id: null, joined_as: "staff" },
  ],
  last_message: { id: `${id}-m`, sender_id: lastFrom, body: `Last from ${lastFrom}`, message_type: "chat", topic: null, inserted_at: "2026-10-30T09:00:00Z" },
  box_person: { newcomer, blocked: false },
});

async function stub(page: Page) {
  const brought: unknown[] = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "front_desk",
          roles: ["front_desk"],
          status: "active",
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: {},
          capabilities: { message_from_box: true },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/conversations**", (route) => route.fulfill(json({ entries: [], next_cursor: null, count: 0 })));
  await page.route("**/api/me/box-conversations", (route) => route.fulfill(json({ conversations: [] })));
  await page.route("**/me/threads**", (route) =>
    route.fulfill(json({ threads: [boxThread("t-new", "person-1", "Giorgos", "person-1", true), boxThread("t-done", "person-2", "Maria", user.id, false)] })),
  );
  await page.route("**/me/threads/t-new/messages**", (route) => route.fulfill(json({ messages: [] })));
  await page.route("**/me/threads/t-new/coaches", (route) => {
    if (route.request().method() === "POST") {
      brought.push(route.request().postDataJSON());
      const thread = boxThread("t-new", "person-1", "Giorgos", "person-1", true);
      return route.fulfill(
        json({ thread: { ...thread, participants: [...thread.participants, { id: "c", user_id: "coach-1", nickname: "Stelios", last_read_message_id: null, joined_as: "coach" }] } }),
      );
    }
    return route.fulfill(json({ coaches: [{ id: "coach-1", nickname: "Stelios", avatar_url: null, in_thread: false, coaches_person: true }] }));
  });
  return brought;
}

test("the box's inbox shows who waits, flags a newcomer and brings a coach in", async ({ page }) => {
  const brought = await stub(page);
  await page.goto("/messages?filter=clubs");

  const filter = page.getByTestId("box-inbox-filter");
  await expect(filter.getByRole("button", { name: "Unanswered · 1" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByText("Giorgos")).toBeVisible();
  await expect(page.getByText("New", { exact: true })).toBeVisible();
  await expect(page.getByText("Maria")).toHaveCount(0);

  await filter.getByRole("button", { name: "All" }).click();
  await expect(page.getByText("Maria")).toBeVisible();

  await page.getByText("Giorgos").click();
  await page.getByTestId("box-bring-coach").click();
  await expect(page.getByText("Their coach")).toBeVisible();
  await page.getByTestId("box-coach-option").click();
  await expect.poll(() => brought).toEqual([{ user_id: "coach-1" }]);
});
