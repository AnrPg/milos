import { createServer, type Server } from "node:http";

import { expect, test, type Page, type Route } from "./support/test";

import { stubApiPort } from "../playwright.config";

// ADR-291 (mockup «Πληρωμή στην υποδοχή», option 1C): a box without online
// payments shows its packages with «Το θέλω»; asking holds the package 14
// days as «Περιμένει πληρωμή», shown in Box with «Πώς πληρώνω» and «Δεν το
// θέλω»; the desk sees it in Εκκρεμότητες › «Περιμένουν πληρωμή» with the
// person as a link to their account, and «Είσπραξη» starts it. The API is
// stubbed; anything not stubbed answers `{}`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

type Write = { method: string; path: string; body: unknown };

function tokenFor(sub: string, role: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub, role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const MEMBER = {
  id: "maria",
  nickname: "Maria",
  role: "member",
  email: "maria@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

const MEMBER_MEMBERSHIP = {
  id: "m-1",
  role: "member",
  roles: ["member"],
  capabilities: {},
  home_location_id: "loc-1",
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", provider_kind: "gym", activation: "active", timezone: "UTC" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const services = { "group_classes.included": true };
const PACKAGES = [
  { id: "unl", name: "Unlimited", description: "Απεριόριστες επισκέψεις", package_type: "membership", billing_period: "monthly", base_price_cents: 7500, currency: "EUR", services },
  { id: "v12", name: "12 επισκέψεις", description: "Ισχύει 3 μήνες", package_type: "visit_pack", billing_period: "one_off", base_price_cents: 9000, currency: "EUR", services },
];
const DESK_SALES = { packages: PACKAGES, online_payments: false, provider: null, withdrawal_days: 14 };

const HOLD_UNTIL = "2026-11-14";
const REQUEST = {
  id: "req-1",
  user_id: "maria",
  package_id: "unl",
  package_name: "Unlimited",
  price_cents: 7500,
  currency: "EUR",
  status: "pending",
  source: "member",
  requested_at: "2026-10-31T09:00:00Z",
  hold_until: HOLD_UNTIL,
  hold_days: 14,
  days_left: 14,
};

async function stubMember(page: Page, writes: Write[], requests: Array<typeof REQUEST>) {
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (method !== "GET") writes.push({ method, path, body: route.request().postDataJSON() });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(MEMBER.id, "member"), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, MEMBER);
    if (path === "/api/memberships") return json(route, [MEMBER_MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/public/boxes/kypseli/packages") return json(route, DESK_SALES);
    if (path === "/api/me/packages/unl/request") {
      requests.splice(0, requests.length, REQUEST);
      return json(route, { request: REQUEST, created: true }, 201);
    }
    if (path === "/api/me/package-requests") return json(route, { requests });
    if (path === "/api/me/package-requests/req-1/cancel") {
      requests.splice(0, requests.length);
      return json(route, { request: { ...REQUEST, status: "cancelled" } });
    }
    return json(route, {});
  });
}

const publicBox = {
  box: { organization_id: "org-1", slug: "kypseli", name: "Box Kypseli", logo_url: null, primary_color: null },
  followers_count: 3,
  profile: { about: "Box", disciplines: ["crossfit"], audiences: [], services: [], amenities: [], languages: ["el"], cover: null, photos: [], coaches: [] },
  locations: [{ id: "loc-1", name: "Kypseli", neighbourhood: "Κυψέλη", city: "Αθήνα", address: "Φωκίωνος Νέγρη 1", country_code: "GR", accessibility: [], opening_hours: [] }],
};

test.describe("a box without online payments: the sales page", () => {
  let server: Server;

  test.beforeAll(async () => {
    server = createServer((request, response) => {
      if (request.url?.startsWith("/api/public/boxes/kypseli")) {
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

  test("a visitor sees «Το θέλω», no buy button, and the desk steps", async ({ page }) => {
    await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => json(route, {}));
    await page.route("**/api/auth/refresh", (route) => json(route, { error: "unauthorized" }, 401));
    await page.route("**/api/public/boxes/kypseli/packages", (route) => json(route, DESK_SALES));

    await page.goto("/b/kypseli/packages");
    await expect(page.getByTestId("sales-desk-note")).toHaveText("Αυτό το box δέχεται πληρωμές στην υποδοχή.");
    await expect(page.getByRole("button", { name: "Αγορά" })).toHaveCount(0);
    await page.getByTestId("sales-want-unl").click();
    const dialog = page.getByTestId("desk-pay");
    await expect(dialog.getByText("Πλήρωσε εκεί 75,00 €, με μετρητά ή κάρτα.")).toBeVisible();
    await expect(dialog.getByTestId("desk-places")).toContainText("Υποδοχή · Kypseli");
    await expect(dialog.getByTestId("desk-login")).toHaveAttribute("href", `/login?next=${encodeURIComponent("/b/kypseli/packages?buy=unl")}`);
  });

  test("a member's «Το θέλω» holds the package for 14 days", async ({ page }) => {
    const writes: Write[] = [];
    await stubMember(page, writes, []);
    await page.goto("/b/kypseli/packages");
    await page.getByTestId("sales-want-unl").click();
    const dialog = page.getByTestId("desk-held");
    await expect(dialog.getByTestId("desk-held-until")).toHaveText(/Το κρατάμε 14 ημέρες, έως 14 Νοεμβρίου\./);
    // Asking again is safe (the server returns the open request), so only "at least once" matters.
    expect(writes.filter((write) => write.path === "/api/me/packages/unl/request").length).toBeGreaterThan(0);
    await dialog.getByTestId("desk-held-ok").click();
    await expect(dialog).toBeHidden();
  });
});

test("Box shows the package waiting for payment, how to pay, and «Δεν το θέλω»", async ({ page }) => {
  const writes: Write[] = [];
  await stubMember(page, writes, [REQUEST]);
  await page.goto("/box");
  const card = page.getByTestId("pending-packages");
  await expect(card).toContainText("Unlimited");
  await expect(card).toContainText("Περιμένει πληρωμή");
  await expect(card).toContainText("Το κρατάμε έως 14 Νοεμβρίου.");
  await card.getByTestId("pending-how").click();
  const how = page.getByTestId("pending-how-dialog");
  await expect(how.getByText("Το πακέτο ξεκινά μόλις πληρώσεις.")).toBeVisible();
  await how.getByRole("button", { name: "Κατάλαβα" }).click();
  await card.getByTestId("pending-cancel").click();
  await expect(page.getByTestId("pending-packages")).toHaveCount(0);
  expect(writes.some((write) => write.path === "/api/me/package-requests/req-1/cancel")).toBe(true);
});

const DESK = {
  id: "desk-1",
  nickname: "Ελένη",
  role: "admin",
  email: "desk-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "front_desk", settings: {} }],
};

const DESK_MEMBERSHIP = {
  role: "front_desk",
  roles: ["front_desk"],
  capabilities: { take_payments: "all", check_in: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

test("the desk sees «Περιμένουν πληρωμή», opens the person's account and collects", async ({ page }) => {
  const writes: Write[] = [];
  let open = [{ ...REQUEST, person: { user_id: "maria", display_name: "Μαρία Κωνσταντίνου", handle: "maria", avatar_url: null } }];
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (method !== "GET") writes.push({ method, path, body: route.request().postDataJSON() });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(DESK.id, "admin"), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, DESK);
    if (path === "/api/memberships") return json(route, [DESK_MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/finance/queues") return json(route, { queues: {} });
    if (path === "/api/admin/finance/package-catalog") return json(route, { types: [], modules: [] });
    if (path.startsWith("/api/admin/finance/members")) return json(route, { members: [], meta: {} });
    if (path === "/api/admin/payments/attention") return json(route, { payments: [], total: 0 });
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/finance/package-requests") return json(route, { requests: open });
    if (path === "/api/admin/finance/package-requests/req-1/collect") {
      open = [];
      return json(route, {
        request: { ...REQUEST, status: "activated" },
        received: {
          document_type: "receipt",
          reference: "R-0008",
          issued_on: "2026-10-31",
          amount_cents: 7500,
          currency: "EUR",
          description: "Unlimited",
          package_name: "Unlimited",
          replayed: false,
          invoice: { id: "inv-8", status: "paid", balance_due_cents: 0 },
          payment: { id: "pay-8", payment_method: "cash" },
        },
      });
    }
    return json(route, {});
  });

  await page.goto("/admin/finance?tab=queues&queue=package_requests");
  const row = page.getByTestId("desk-request-req-1");
  await expect(row.getByTestId("queue-person-link")).toHaveAttribute("href", /\/admin\/users\/maria/);
  await expect(row).toContainText("Unlimited · 75,00 €");
  await expect(row).toContainText("Αφαιρείται σε 14 ημέρες");
  await row.getByTestId("desk-collect-req-1").click();
  const dialog = page.getByTestId("desk-collect");
  await dialog.getByRole("radio", { name: /Μετρητά/ }).click();
  await dialog.getByTestId("desk-collect-confirm").click();
  await expect(page.getByText("R-0008")).toBeVisible();
  const collect = writes.find((write) => write.path === "/api/admin/finance/package-requests/req-1/collect");
  expect(collect?.body).toEqual({ payment_method: "cash" });
});
