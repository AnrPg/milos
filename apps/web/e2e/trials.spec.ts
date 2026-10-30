import { createServer, type Server } from "node:http";

import { expect, test, type Page } from "./support/test";

import { stubApiPort } from "../playwright.config";

// Trials (ADR-144, plan §5a board 6): a visitor books a trial from the box
// page or from a class in Πρόγραμμα, sees «Τι να φέρεις», follows the trial
// on its page and, after the visit, tells the box they want to join.

const box = { organization_id: "org-1", slug: "crossfit-kypseli", name: "CrossFit Kypseli", logo_url: null, primary_color: "#D9743D" };
const location = { id: "loc-1", name: "Kypseli", address: "Fokionos Negri 10", neighbourhood: "Kypseli", city: "Athens", latitude: 38.0035, longitude: 23.7369 };

const publicBox = {
  box,
  followers_count: 3,
  profile: { about: "A friendly box.", disciplines: ["crossfit"], audiences: [], services: [], amenities: [], languages: [], cover: null, photos: [], coaches: [] },
  locations: [{ ...location, country_code: "GR", accessibility: [], opening_hours: [] }],
};

let server: Server;

test.beforeAll(async () => {
  server = createServer((request, response) => {
    if (request.url?.startsWith(`/api/public/boxes/${box.slug}`)) {
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
  id: "visitor-1",
  nickname: "Nikos",
  role: "member",
  email: "visitor-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [],
};

function token() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

// Late today, so the class is upcoming and on the day Πρόγραμμα opens on.
function todayAt(hour: number, minute = 0) {
  const date = new Date();
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
}

const slot = {
  id: "slot-1",
  name: "CrossFit Basics",
  scheduled_at: todayAt(23, 30),
  duration_minutes: 60,
  capacity: 12,
  spots_remaining: 4,
  location_id: "loc-1",
  coach: { id: "coach-1", nickname: "Stelios", avatar_url: null },
  class_type: { id: "type-1", name: "CrossFit", level: "beginner", audiences: [] },
  trial_seats: 2,
};
const closedSlot = { ...slot, id: "slot-2", name: "Competitors", class_type: { id: "type-2", name: "Comp", level: "advanced", audiences: [] }, trial_seats: null };

const trial = (overrides: Record<string, unknown> = {}) => ({
  id: "trial-1",
  organization_id: box.organization_id,
  user_id: user.id,
  scheduled_class_id: slot.id,
  booking_id: "booking-1",
  status: "booked",
  note: "First time",
  class_starts_at: slot.scheduled_at,
  inserted_at: new Date().toISOString(),
  class: { id: slot.id, name: slot.name, scheduled_at: slot.scheduled_at, duration_minutes: 60, location_id: "loc-1", class_type: null },
  box,
  location,
  bring_note: "Trainers and water.",
  follow_up: false,
  ...overrides,
});

async function visitor(page: Page, { trials = [] as unknown[] } = {}) {
  const asks: unknown[] = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json({ memberships: [] })));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/follows/organization/org-1", (route) => route.fulfill(json({ status: "none" })));
  await page.route(`**/api/boxes/${box.slug}/schedule**`, (route) =>
    route.fulfill(
      json({
        box,
        start_at: todayAt(0),
        end_at: todayAt(23, 59),
        trial_offer: { enabled: true, approval: "auto", bring_note: "Trainers and water.", horizon_days: null, blocked_reason: null, mine: null },
        slots: [slot, closedSlot],
      }),
    ),
  );
  await page.route(`**/api/boxes/${box.slug}/trials`, (route) => {
    asks.push(route.request().postDataJSON());
    return route.fulfill(json({ trial: trial() }, 201));
  });
  await page.route("**/api/me/trials", (route) => route.fulfill(json({ trials })));
  return asks;
}

test.describe("trials", () => {
  test("a visitor books a trial from the box page and sees what to bring", async ({ page }) => {
    const asks = await visitor(page);
    await page.goto(`/b/${box.slug}`);

    await page.getByRole("button", { name: /Ask for a trial/ }).first().click();
    const sheet = page.getByRole("dialog", { name: "Trial class" });
    await expect(sheet.getByRole("button", { name: /Competitors/ })).toBeHidden();
    await sheet.getByRole("button", { name: /CrossFit Basics/ }).click();
    await sheet.getByLabel("Note for the coach (optional)").fill("First time");
    await sheet.getByRole("button", { name: "Book the trial" }).click();

    await expect(page.getByRole("dialog", { name: "Booked" })).toBeVisible();
    await expect(page.getByText("Trainers and water.")).toBeVisible();
    await expect(page.getByRole("link", { name: "See your trial" })).toHaveAttribute("href", "/trials/trial-1");
    expect(asks).toEqual([expect.objectContaining({ scheduled_class_id: slot.id, note: "First time", source: "box_page" })]);
  });

  test("Πρόγραμμα tags trial classes, filters them, and books one from its sheet", async ({ page }) => {
    const asks = await visitor(page);
    // The class sits at 23:30 today; pin the browser clock to midday so it
    // is still upcoming whenever the suite runs.
    await page.clock.setFixedTime(todayAt(12));
    await page.goto(`/b/${box.slug}#schedule`);

    await expect(page.getByRole("button", { name: /Competitors/ })).toBeVisible();
    // The filters sit behind the filter button (CollapsibleFilterBar).
    await page.getByRole("button", { name: "Filters", exact: true }).click();
    await page.getByRole("button", { name: "Trial classes" }).click();
    await expect(page.getByRole("button", { name: /Competitors/ })).toBeHidden();
    await page.getByRole("button", { name: /CrossFit Basics/ }).click();
    await page.getByRole("button", { name: "Book as a trial" }).click();
    await page.getByRole("dialog", { name: "Trial class" }).getByRole("button", { name: "Book the trial" }).click();

    await expect(page.getByRole("dialog", { name: "Booked" })).toBeVisible();
    expect(asks).toEqual([expect.objectContaining({ scheduled_class_id: slot.id, source: "schedule" })]);
  });

  test("after the visit, «I want to join» opens the chat with the box, prefilled", async ({ page }) => {
    const attended = trial({ status: "attended", follow_up: true, attended_at: new Date().toISOString() });
    await visitor(page, { trials: [attended] });
    await page.route("**/api/me/trials/trial-1", (route) => route.fulfill(json({ trial: attended })));
    await page.route("**/api/me/trials/trial-1/follow-up", (route) =>
      route.fulfill(json({ trial: { ...attended, follow_up: false, join_interest_at: new Date().toISOString() }, conversation: null })),
    );
    await page.route(`**/api/boxes/${box.slug}/conversation**`, (route) =>
      route.fulfill(json({ conversation: { thread_id: "thread-1", box, member: false, staff: [], last_read_message_id: null, conversion_package: { id: "pkg-1", name: "Unlimited", base_price_cents: 8000, currency: "EUR", billing_period: "monthly" }, messages: [] } })),
    );

    await page.goto("/trials/trial-1");
    await expect(page.getByText("How did it go?")).toBeVisible();
    await expect(page.getByRole("link", { name: /Directions/ })).toHaveAttribute("href", /38\.0035,23\.7369/);
    await page.getByRole("button", { name: "I want to join" }).click();

    await expect(page).toHaveURL(new RegExp(`/b/${box.slug}/chat\\?draft=join`));
    await expect(page.getByText("Offer for new box members")).toBeVisible();
    await expect(page.getByLabel("Write a message")).toHaveValue(/I'd like to join/);
  });

  test("«Contact the box» opens the chat with its topic, and a newcomer waits for an answer (ADR-282)", async ({ page }) => {
    await visitor(page);
    const sent: Record<string, unknown>[] = [];
    await page.route(`**/api/boxes/${box.slug}/conversation**`, (route) =>
      route.fulfill(json({ conversation: { thread_id: "thread-1", box, member: true, blocked: false, staff: [], last_read_message_id: null, conversion_package: null, messages: [] } })),
    );
    await page.route(`**/api/boxes/${box.slug}/conversation/messages`, (route) => {
      sent.push(route.request().postDataJSON());
      return sent.length === 1
        ? route.fulfill(json({ message: { id: "m-1", sender_id: user.id, body: "Card declined?", message_type: "chat", topic: "payment", inserted_at: new Date().toISOString() } }, 201))
        : route.fulfill(json({ code: "awaiting_box_reply", error: "awaiting_box_reply" }, 429));
    });

    await page.goto(`/b/${box.slug}/chat?topic=payment`);
    const topics = page.getByTestId("box-chat-topics");
    await expect(topics.getByRole("button", { name: "Payment" })).toHaveAttribute("aria-pressed", "true");
    await topics.getByRole("button", { name: "Training" }).click();
    await expect(topics.getByRole("button", { name: "Training" })).toHaveAttribute("aria-pressed", "true");
    await topics.getByRole("button", { name: "Payment" }).click();

    await page.getByLabel("Write a message").fill("Card declined?");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect.poll(() => sent[0]?.topic).toBe("payment");

    await page.getByLabel("Write a message").fill("Hello?");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect(page.getByText("Wait for the box to answer before you send more.")).toBeVisible();
  });
});
