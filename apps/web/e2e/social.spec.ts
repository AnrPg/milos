import { expect, test, type Page } from "./support/test";

// ADR-142 (P2-M2): follow requests with the one-time booking-sharing offer
// (board 5 Q6), the connections screen and a person's profile. The API is
// stubbed; every route not listed answers an empty object.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const since = new Date().toISOString();
const nikos = { id: "person-2", nickname: "Nikos", avatar_url: null };

async function stub(page: Page) {
  const state = { followers: 0, requests: 1, sharing: { enabled: false, offered: false }, puts: [] as unknown[] };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", roles: ["member"], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/social", (route) =>
    route.fulfill(
      json({ posts_count: 3, followers_count: state.followers, following_count: 2, requests_count: state.requests, booking_sharing: state.sharing }),
    ),
  );
  await page.route("**/api/me/social/booking-sharing", (route) => {
    const body = route.request().postDataJSON() as { enabled: boolean };
    state.puts.push(body);
    state.sharing = { enabled: body.enabled, offered: true };
    return route.fulfill(json(state.sharing));
  });
  await page.route("**/api/me/follow-requests", (route) =>
    route.fulfill(
      json({ entries: state.requests ? [{ follow_id: "follow-1", status: "requested", since, person: { ...nikos, my_status: "none" } }] : [], next_cursor: null }),
    ),
  );
  await page.route("**/api/me/follow-requests/follow-1/accept", (route) => {
    state.requests = 0;
    state.followers = 1;
    return route.fulfill({ status: 204, body: "" });
  });
  await page.route("**/api/me/followers**", (route) => {
    // The API matches names (board 5 Q4); this stub knows only Nikos.
    const q = new URL(route.request().url()).searchParams.get("q") ?? "";
    const entries = "nikos".includes(q.toLowerCase())
      ? [{ follow_id: "follow-1", status: "active", since, person: { ...nikos, my_status: "none" } }]
      : [];
    return route.fulfill(json({ entries, next_cursor: null }));
  });
  await page.route("**/api/me/following**", (route) =>
    route.fulfill(json({ entries: [{ follow_id: "follow-2", status: "active", since, person: { id: "person-3", nickname: "Eleni", avatar_url: null, my_status: "active" } }], next_cursor: null })),
  );
  await page.route("**/api/people/person-2", (route) =>
    route.fulfill(json({ ...nikos, is_me: false, followers_count: 10, following_count: 4, my_status: "none", follows_me: true })),
  );
  await page.route("**/api/people/person-2/posts**", (route) => route.fulfill(json({ posts: [], next_cursor: null })));
  await page.route("**/api/pr-sharing/shared-with-me", (route) => route.fulfill(json({ shared: [] })));
  await page.route("**/api/me/follows/user/person-2", (route) => route.fulfill(json({ status: "none" })));
  return state;
}

test.describe("social", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("accepting the first follower offers booking sharing once", async ({ page }) => {
    const state = await stub(page);
    await page.goto("/me/follow-requests");
    await expect(page.getByText("Nikos")).toBeVisible();
    await expect(page.getByText("Let your followers see which classes you go to?")).toHaveCount(0);

    await page.getByRole("button", { name: "Accept" }).click();
    await expect(page.getByText("Let your followers see which classes you go to?")).toBeVisible();
    await page.getByRole("button", { name: "Yes, let them see" }).click();
    await expect.poll(() => state.puts).toEqual([{ enabled: true }]);
    await expect(page.getByText("Let your followers see which classes you go to?")).toHaveCount(0);
  });

  test("connections list followers and the people you follow in tabs", async ({ page }) => {
    const state = await stub(page);
    state.followers = 1;
    state.requests = 0;
    await page.goto("/me/connections");
    // The tabs fall back to a dropdown when they don't fit one row (SegmentPicker).
    const tabs = page.getByRole("combobox", { name: "Connections" });
    await expect(tabs).toContainText("1 follower");
    await expect(page.getByRole("link", { name: /Nikos/ })).toHaveAttribute("href", "/people/person-2");
    await page.getByRole("searchbox", { name: "Search people" }).fill("maria");
    await expect(page.getByText("Nothing matches that search.")).toBeVisible();
    await page.getByRole("searchbox", { name: "Search people" }).fill("NIK");
    await expect(page.getByRole("link", { name: /Nikos/ })).toBeVisible();
    await tabs.click();
    await page.getByRole("option", { name: "Following 2" }).click();
    await expect(page).toHaveURL(/tab=following/);
    await expect(page.getByRole("link", { name: /Eleni/ })).toBeVisible();
  });

  test("a person's profile offers follow back and keeps followers posts locked", async ({ page }) => {
    await stub(page);
    await page.goto("/people/person-2");
    await expect(page.getByRole("heading", { name: "Nikos" })).toBeVisible();
    await expect(page.getByText("Follows you")).toBeVisible();
    await expect(page.getByRole("button", { name: "Follow back" })).toBeVisible();
    await expect(page.getByText("Follow to also see followers-only posts.")).toBeVisible();
    await page.getByRole("tab", { name: "PRs" }).click();
    await expect(page.getByText("They don't share their PRs with you.")).toBeVisible();
  });
});
