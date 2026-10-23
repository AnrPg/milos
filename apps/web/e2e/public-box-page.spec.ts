import { createServer, type Server } from "node:http";

import { expect, test, type Page } from "./support/test";

import { stubApiPort } from "../playwright.config";

import { chooseOption } from "./support/select";

// The public box page (ADR-142, plan §5a board 4, board 5 Q1–Q2). The page is
// server-rendered, so its read goes to a stub API on `stubApiPort`; what the
// browser fetches afterwards is stubbed with page.route.

const pixel = (color: string) =>
  `data:image/svg+xml;utf8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630"><rect width="100%" height="100%" fill="${color}"/></svg>`)}`;

const box = { organization_id: "org-1", slug: "crossfit-kypseli", name: "CrossFit Kypseli", logo_url: null, primary_color: "#D9743D" };

const publicBox = {
  box,
  followers_count: 12,
  profile: {
    about: "A friendly box in Kypseli.\nCoaches who know your name.",
    disciplines: ["crossfit", "olympic_lifting", "yoga", "pilates", "hyrox", "gymnastics", "running", "mobility"],
    audiences: ["beginners", "over_40"],
    services: ["personal_training", "open_gym"],
    amenities: ["showers", "towels", "wifi"],
    languages: ["el", "en"],
    cover: { id: "cover", url: pixel("#7a3b1d"), width: 1200, height: 630 },
    photos: [
      { id: "p1", url: pixel("#335577"), width: 1200, height: 630 },
      { id: "p2", url: pixel("#557733"), width: 1200, height: 630 },
    ],
    coaches: [{ id: "coach-1", nickname: "Stelios", avatar_url: null, class_types: ["CrossFit", "Olympic lifting"] }],
  },
  locations: [
    {
      id: "loc-1",
      name: "Kypseli",
      address: "Fokionos Negri 10",
      neighbourhood: "Kypseli",
      city: "Athens",
      country_code: "GR",
      latitude: 38.0035,
      longitude: 23.7369,
      accessibility: [],
      opening_hours: [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({ weekday, opens: "07:00", closes: "22:00" })),
    },
  ],
};

let server: Server;

test.beforeAll(async () => {
  server = createServer((request, response) => {
    const match = request.url?.match(/^\/api\/public\/boxes\/([^/?]+)/);
    if (match && (match[1] === box.slug || match[1] === "kypseli-old")) {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify(publicBox));
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

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [] as { organization_slug: string; role: string; settings: object }[],
};

function token() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

async function asGuest(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
}

async function signedIn(page: Page, { member = false } = {}) {
  const follows: unknown[] = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json({ memberships: [] })));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) =>
    route.fulfill(
      json({
        clubs: member
          ? [{ id: "club-1", kind: "gym", name: box.name, organization_id: box.organization_id, organization_slug: box.slug, role: "member", notify_level: "all", logo_url: null, primary_color: null, channels: [] }]
          : [],
      }),
    ),
  );
  await page.route("**/api/me/follows/organization/org-1", (route) => route.fulfill(json({ status: follows.length ? "active" : "none" })));
  await page.route("**/api/me/follows", (route) => {
    follows.push(route.request().postDataJSON());
    return route.fulfill(json({ status: "active" }));
  });
  await page.route(`**/api/boxes/${box.slug}/schedule**`, (route) =>
    route.fulfill(
      json({
        box,
        start_at: todayAt(0),
        end_at: todayAt(23),
        slots: [
          {
            id: "slot-1",
            name: "CrossFit",
            scheduled_at: todayAt(23),
            duration_minutes: 60,
            capacity: 12,
            spots_remaining: 4,
            location_id: "loc-1",
            coach: { id: "coach-1", nickname: "Stelios", avatar_url: null },
            class_type: { id: "type-1", name: "CrossFit", level: "all_levels", audiences: [] },
          },
          {
            id: "slot-2",
            name: "Yoga 40+",
            scheduled_at: todayAt(23),
            duration_minutes: 45,
            capacity: 10,
            spots_remaining: 0,
            location_id: "loc-1",
            coach: null,
            class_type: { id: "type-2", name: "Yoga", level: "beginner", audiences: ["over_40"] },
          },
        ],
      }),
    ),
  );
  await page.route(`**/api/boxes/${box.slug}/posts**`, (route) => route.fulfill(json({ box, posts: [], next_cursor: null })));
  return follows;
}

test.describe("public box page", () => {
  test("logged out: Σχετικά is open, the other tabs ask to sign in, and previews carry the name", async ({ page }) => {
    await asGuest(page);
    await page.goto(`/b/${box.slug}`);

    await expect(page.getByRole("heading", { name: box.name }).first()).toBeVisible();
    await expect(page).toHaveTitle(/CrossFit Kypseli/);
    await expect(page.locator('meta[property="og:title"]')).toHaveAttribute("content", box.name);
    await expect(page.getByText("A friendly box in Kypseli.")).toBeVisible();
    await expect(page.getByText("Ελληνικά · English")).toBeVisible();
    await expect(page.getByText("Stelios")).toBeVisible();
    await expect(page.getByRole("button", { name: "2 more disciplines" })).toBeVisible();
    if ((page.viewportSize()?.width ?? 0) >= 1024) {
      // Desktop (board 5 Q1): the side card's map opens the location in Maps.
      await expect(page.getByRole("link", { name: "Open in Maps" })).toHaveAttribute(
        "href",
        "https://www.google.com/maps/search/?api=1&query=38.0035,23.7369",
      );
    }

    await page.getByRole("tab", { name: "Schedule" }).click();
    await expect(page).toHaveURL(/#schedule$/);
    await expect(page.getByText("Sign in to see the schedule")).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in" })).toHaveAttribute("href", `/login?next=${encodeURIComponent(`/b/${box.slug}#schedule`)}`);
  });

  test("a retired slug redirects to the canonical page", async ({ page }) => {
    await asGuest(page);
    await page.goto("/b/kypseli-old");
    await expect(page).toHaveURL(new RegExp(`/b/${box.slug}$`));
  });

  test("photos open full screen with a counter", async ({ page }) => {
    await asGuest(page);
    await page.goto(`/b/${box.slug}`);
    await page.getByRole("button", { name: "Photo 2" }).click();
    const viewer = page.getByRole("dialog", { name: "Photos" });
    await expect(viewer.getByText("3 of 3")).toBeVisible();
    await viewer.getByRole("button", { name: "Close" }).click();
    await expect(viewer).toBeHidden();
  });

  test("signed in: the schedule lists classes with filters and a sheet, and the box can be followed", async ({ page }) => {
    const follows = await signedIn(page);
    await page.goto(`/b/${box.slug}#schedule`);

    await expect(page.getByRole("button", { name: /Yoga 40\+/ })).toBeVisible();
    await page.getByRole("button", { name: "Filters", exact: true }).click();
    await chooseOption(page, page.getByLabel("Level"), "beginner");
    await expect(page.getByRole("button", { name: /CrossFit.*Stelios/ })).toBeHidden();
    await page.getByRole("button", { name: /Yoga 40\+/ }).click();
    const sheet = page.getByRole("dialog", { name: "Yoga 40+" });
    // Trials are off at this box: no trial action on the class.
    await expect(sheet.getByRole("button", { name: "Book as a trial" })).toBeHidden();
    // The header × and the footer button both close it.
    await sheet.getByRole("button", { name: "Close" }).first().click();

    await page.getByRole("button", { name: "Follow" }).first().click();
    await expect.poll(() => follows).toEqual([{ target_type: "organization", target_id: "org-1" }]);
  });

  test("a member of the gym opens the club instead of following", async ({ page }) => {
    await signedIn(page, { member: true });
    await page.goto(`/b/${box.slug}`);
    await expect(page.getByRole("link", { name: "Member · Open the club" }).first()).toHaveAttribute("href", "/clubs/club-1");
  });
});
