import { expect, test, type Page } from "./support/test";

// ANR 2026-10-24/25: the Μηνύματα tabs never cut a label (a row only when
// every label fits its share, else a full grid or a dropdown), «People» files
// chats with other people, «Partners» shows only to someone who has one; the
// Find bubble is a magnifying glass and the bottom bar's current tab has no
// Spark fill; accounts start public. The API is stubbed; every route not
// listed answers an empty object.

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

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const match = {
  id: "match-1",
  status: "active",
  matched_at: new Date().toISOString(),
  last_message_at: null,
  unread: 0,
  person: { id: "person-9", nickname: "Eleni", avatar_url: null },
};

async function stub(page: Page, { partners = false }: { partners?: boolean } = {}) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", roles: ["member"], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/threads**", (route) => route.fulfill(json({ threads: [] })));
  await page.route("**/api/me/conversations**", (route) => route.fulfill(json({ entries: [], next_cursor: null, count: 0 })));
  await page.route("**/api/me/partners/matches", (route) => route.fulfill(json({ matches: partners ? [match] : [] })));
  await page.route("**/api/pr-sharing", (route) => route.fulfill(json({ grants: [] })));
  await page.route("**/api/prs", (route) => route.fulfill(json({ prs: [] })));
  await page.route("**/api/me/buddies", (route) => route.fulfill(json({ buddies: [], supporting: [], invitations: [] })));
  // No settings stored yet: the account reads as public and searchable.
  await page.route("**/api/me/social", (route) =>
    route.fulfill(
      json({
        posts_count: 0,
        followers_count: 0,
        following_count: 0,
        requests_count: 0,
        booking_sharing: { enabled: false, offered: false },
        privacy: { private_account: false, searchable: true },
        follow_groups: { buddies: 0, followers_only: 0, following_only: 0 },
      }),
    ),
  );
}

/** Every segment option's label, whichever form the picker settled on. */
async function expectSegments(page: Page, expected: string[]) {
  await expect.poll(() => segmentLabels(page), { timeout: 15_000 }).toEqual(expected);
}

async function segmentLabels(page: Page) {
  const select = page.getByRole("combobox", { name: "Which messages to show" });
  if (await select.count()) {
    // The themed dropdown (ui/Select) lists its options once opened.
    await select.click();
    const options = page.getByRole("listbox").getByRole("option");
    await options.first().waitFor({ timeout: 2_000 }).catch(() => undefined);
    const labels = await options.allTextContents();
    await page.keyboard.press("Escape");
    return labels.map((label) => label.trim());
  }
  return (await page.getByRole("tablist", { name: "Which messages to show" }).getByRole("tab").allTextContents()).map((label) => label.trim());
}

for (const width of [320, 375, 430, 1024]) {
  test(`Messages tabs never cut a label at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 860 });
    await stub(page, { partners: true });
    await page.goto("/messages");

    await expectSegments(page, ["All", "People", "Coach", "Clubs", "Partners"]);

    const tabs = page.getByRole("tablist", { name: "Which messages to show" }).getByRole("tab");
    for (const tab of await tabs.all()) {
      const cut = await tab.locator("span").first().evaluate((label) => label.scrollWidth > label.clientWidth);
      expect(cut).toBe(false);
    }
  });
}

test("Partners shows only to someone with a partner; People lists chats with other people", async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 860 });
  await stub(page);
  await page.goto("/messages?filter=partners");

  // No partner yet: no «Partners» tab, and its address falls back to «All».
  await expectSegments(page, ["All", "People", "Coach", "Clubs"]);
  await expect(page.getByRole("tab", { name: "All" })).toHaveAttribute("aria-selected", "true");

  await page.getByRole("tab", { name: "People" }).click();
  await expect(page).toHaveURL(/filter=people/);
  await expect(page.getByText("No conversations yet. Search to start one.")).toBeVisible();
});

test("the Find bubble is a magnifying glass and the current tab has no fill", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 860 });
  await stub(page);
  await page.goto("/clubs/find");

  await expect(page.getByRole("heading", { name: "Find clubs and people" })).toBeVisible();
  const find = page.getByRole("link", { name: "Find" });
  await expect(find.locator("svg")).toHaveCount(1);
  await expect(find).not.toContainText("+");

  await page.goto("/messages");
  const current = page.locator('nav a[aria-current="page"]').filter({ hasText: "Messages" }).first();
  await expect(current).toBeVisible();
  const fill = await current.locator("span").first().evaluate((el) => getComputedStyle(el).backgroundColor);
  expect(fill).toBe("rgba(0, 0, 0, 0)");
});

test("a new account reads as public and searchable", async ({ page }) => {
  await stub(page);
  await page.goto("/me/sharing");
  const privateAccount = page.getByRole("switch", { name: "Private account", exact: true });
  await expect(privateAccount).toHaveAttribute("aria-checked", "false");
  await expect(page.getByText(/Your account is public/)).toBeVisible();
});
