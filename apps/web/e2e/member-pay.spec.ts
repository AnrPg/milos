import { createServer, type Server } from "node:http";

import { expect, test, type Page, type Request } from "./support/test";

import { stubApiPort } from "../playwright.config";

// Mockup s4 option B (member pays a subscription package, or one visit when
// booking without one), the /pay/return page with the sandbox provider's
// page, the failed-charge link (/me/payments?payment=) and mockup s5 option C
// (the box's public sales page). The API is stubbed; anything not stubbed
// answers `{}`. The sandbox provider sends the payer to our own /pay/return
// with `sandbox_checkout=`, exactly as the API's sandbox gateway does.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const PAYMENT = "5f1d0c2b-7a3e-4c9d-8b21-0e6f4a3b2c1d";
const CHARGE = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d";

const user = {
  id: "member-1",
  nickname: "Maria",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const membership = {
  id: "m-1",
  role: "member",
  roles: ["member"],
  capabilities: {},
  home_location_id: "loc-1",
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", provider_kind: "gym", activation: "active", timezone: "UTC" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const services = { "group_classes.included": true };
const packages = [
  { id: "trial", name: "Δοκιμαστικό", description: null, package_type: "trial", billing_period: "one_off", base_price_cents: 1000, currency: "EUR", services },
  { id: "unl", name: "Unlimited", description: "Απεριόριστες επισκέψεις", package_type: "membership", billing_period: "monthly", base_price_cents: 7500, currency: "EUR", services },
  { id: "w3", name: "3 φορές την εβδομάδα", description: "Έως 12 επισκέψεις τον μήνα", package_type: "membership", billing_period: "monthly", base_price_cents: 6000, currency: "EUR", services },
  { id: "v12", name: "12 επισκέψεις", description: "Ισχύει 3 μήνες", package_type: "visit_pack", billing_period: "one_off", base_price_cents: 9000, currency: "EUR", services },
  { id: "drop", name: "Μία επίσκεψη", description: null, package_type: "drop_in", billing_period: "one_off", base_price_cents: 1500, currency: "EUR", services },
  { id: "am", name: "Πρωινά", description: "Τμήματα έως τις 12:00", package_type: "membership", billing_period: "monthly", base_price_cents: 5000, currency: "EUR", services },
];
const sales = { packages, online_payments: true, provider: "viva", withdrawal_days: 14 };

const intent = (over: Record<string, unknown> = {}) => ({
  id: PAYMENT,
  provider: "sandbox",
  environment: "test",
  initiation: "payer",
  purpose_type: "membership_package",
  purpose_id: "unl",
  amount_cents: 7500,
  currency: "EUR",
  description: "Unlimited",
  status: "awaiting_payer",
  fulfilment_status: "pending",
  refunded_cents: 0,
  declines: 0,
  retries: 3,
  card_last4: null,
  metadata: {},
  ...over,
});

async function stubMember(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/public/boxes/kypseli/packages", (route) => route.fulfill(json(sales)));
}

/** The sandbox checkout: the API answers with a redirect to our own /pay/return. */
async function stubSandboxCheckout(page: Page, calls: Array<{ path: string; body: Record<string, unknown> }>, paid: Record<string, unknown>) {
  const redirect = (baseURL: string) => `${baseURL}/pay/return?payment=${PAYMENT}&sandbox_checkout=sbxo_${PAYMENT}&sandbox_decline=0`;
  await page.route(`**/api/org/kypseli/me/payments/${PAYMENT}`, (route) => route.fulfill(json({ payment: intent(paid) })));
  await page.route("**/api/org/kypseli/me/payments/sandbox/complete", (route) => {
    calls.push({ path: "sandbox/complete", body: bodyOf(route.request()) });
    return route.fulfill(json({ payment: intent({ ...paid, status: "succeeded", fulfilment_status: "done", card_last4: "4242" }) }));
  });
  await page.route("**/api/org/kypseli/me/payments/return", (route) => {
    calls.push({ path: "return", body: bodyOf(route.request()) });
    return route.fulfill(json({ payment: intent({ ...paid, status: "succeeded", fulfilment_status: "done", card_last4: "4242" }) }));
  });
  return redirect;
}

test.describe("member pays online (mockup s4 option B)", () => {
  test("renews from Box: package, «Πριν πληρώσεις», the sandbox provider's page and back", async ({ page, baseURL }) => {
    await stubMember(page);
    const calls: Array<{ path: string; body: Record<string, unknown> }> = [];
    const redirect = await stubSandboxCheckout(page, calls, {});
    await page.route("**/api/org/kypseli/me/packages/unl/purchase-terms**", (route) =>
      route.fulfill(
        json({
          package: packages[1],
          available: true,
          provider: "sandbox",
          withdrawal_days: 14,
          start_now_text: "Ζητώ να ξεκινήσει το πακέτο αμέσως. Γνωρίζω ότι μπορώ να υπαναχωρήσω μέσα σε 14 ημέρες από την αγορά, πληρώνοντας μόνο το μέρος που χρησιμοποίησα.",
          consent_text: "Επιτρέπω στην επιχείρηση «Box Kypseli» να χρεώνει αυτή την κάρτα για τις επόμενες χρεώσεις του πακέτου «Unlimited», έως 75,00 € ανά χρέωση, μέχρι να το ανακαλέσω.",
          consent_version: "2026-10-v1",
        }),
      ),
    );
    await page.route("**/api/org/kypseli/me/packages/unl/buy", (route) => {
      calls.push({ path: "buy", body: bodyOf(route.request()) });
      return route.fulfill(json({ payment: intent({ redirect_url: redirect(baseURL!) }) }));
    });

    await page.goto("/box");
    await page.getByTestId("pay-renew").click();
    const sheet = page.getByTestId("pay-sheet");
    await expect(sheet.getByRole("radio", { name: /Unlimited/ })).toHaveAttribute("aria-checked", "true");
    // Three packages, the rest one «Όλα» away; single visits and trials are not renewals.
    await expect(sheet.getByRole("radio")).toHaveCount(3);
    await expect(sheet.getByText("Μία επίσκεψη")).toHaveCount(0);
    await sheet.getByRole("button", { name: "Συνέχεια" }).click();

    await expect(sheet.getByText("Πριν πληρώσεις")).toBeVisible();
    await expect(sheet.getByText(/Ζητώ να ξεκινήσει το πακέτο αμέσως/)).toBeVisible();
    const pay = sheet.getByTestId("pay-submit");
    await expect(pay).toBeDisabled();
    await sheet.getByTestId("pay-start-now").click();
    await sheet.getByTestId("pay-auto-yes").click();
    await expect(pay).toHaveText(/Πληρωμή 75,00\s€ με Sandbox/);
    await pay.click();

    await expect(page.getByTestId("pay-sandbox")).toBeVisible();
    await expect(page.getByText("Η κάρτα σου αποθηκεύεται στον πάροχο", { exact: false })).toBeVisible();
    await page.getByTestId("pay-sandbox-pay").click();

    await expect(page.getByTestId("pay-result-ok")).toContainText("Έτοιμο!");
    await expect(page.getByText("Το πακέτο συνδρομής «Unlimited» ξεκινά σήμερα.")).toBeVisible();
    await expect(page.getByText(/κάρτα ••4242/)).toBeVisible();
    await expect(page.getByTestId("pay-back")).toHaveAttribute("href", "/box");

    expect(calls.find((call) => call.path === "buy")?.body).toMatchObject({
      start_now: true,
      save_card: true,
      consent_accepted: true,
      autopay: true,
      language: "el",
    });
    expect(calls.find((call) => call.path === "sandbox/complete")?.body).toEqual({
      provider_ref: `sbxo_${PAYMENT}`,
      outcome: "succeeded",
      decline_card: false,
    });
    expect(calls.find((call) => call.path === "return")?.body).toEqual({ payment_id: PAYMENT });
  });

  test("cancelling on the provider's page comes back not charged", async ({ page, baseURL }) => {
    await stubMember(page);
    await page.route(`**/api/org/kypseli/me/payments/${PAYMENT}`, (route) => route.fulfill(json({ payment: intent() })));
    await page.route("**/api/org/kypseli/me/payments/sandbox/complete", (route) => route.fulfill(json({ payment: intent({ status: "cancelled" }) })));
    await page.route("**/api/org/kypseli/me/payments/return", (route) => route.fulfill(json({ payment: intent({ status: "cancelled" }) })));

    await page.goto(`${baseURL}/pay/return?payment=${PAYMENT}&sandbox_checkout=sbxo_1&sandbox_decline=0`);
    await page.getByTestId("pay-sandbox-cancel").click();
    await expect(page.getByTestId("pay-result-bad")).toContainText("Η πληρωμή ακυρώθηκε");
    await expect(page).toHaveURL(/cancelled=1/);
  });

  test("a declined saved-card charge is paid with another card from the notification's link", async ({ page }) => {
    await stubMember(page);
    const calls: Array<{ path: string; body: Record<string, unknown> }> = [];
    await page.route("**/api/me/billing", (route) =>
      route.fulfill(
        json({
          providers: [
            {
              organization_id: "org-1",
              name: "Box Kypseli",
              slug: "kypseli",
              kind: "gym",
              partial: false,
              contact: { box_chat_slug: null },
              actions: { self_service_purchase: false, self_service_cancel_auto_renew: false, self_service_leave: false, download_invoices: true },
              membership: { status: "active", entitlement_status: "active", starts_on: "2026-01-01" },
              entitlement: null,
              subscriptions: [],
              invoices: [],
              payments: [],
              refund_receipts: [],
              promotions: [],
              seasons: [],
              referrals: { credits: [], credit_total_cents: 0, invited: 0, trials: 0, paid: 0 },
              trials: [],
              available_offers: [],
              perks: [],
              outstanding_cents: 7500,
              credit_balance_cents: 0,
            },
          ],
        }),
      ),
    );
    await page.route(`**/api/org/kypseli/me/payments/${CHARGE}`, (route) =>
      route.fulfill(
        json({
          payment: intent({
            id: CHARGE,
            initiation: "merchant",
            purpose_type: "finance_invoice",
            purpose_id: "inv-7",
            description: "INV-0007 · Unlimited",
            status: "scheduled",
            declines: 1,
            card_last4: "4421",
            next_attempt_at: "2026-11-01T09:00:00Z",
          }),
        }),
      ),
    );
    await page.route("**/api/org/kypseli/me/invoices/inv-7/payment-terms**", (route) =>
      route.fulfill(json({ available: true, provider: "viva", amount_cents: 7500, currency: "EUR", consent_text: "Επιτρέπω στην επιχείρηση «Box Kypseli» να χρεώνει αυτή την κάρτα…", consent_version: "2026-10-v1" })),
    );
    await page.route("**/api/org/kypseli/me/invoices/inv-7/pay", (route) => {
      calls.push({ path: "pay", body: bodyOf(route.request()) });
      return route.fulfill(json({ payment: intent({ id: PAYMENT, redirect_url: `http://127.0.0.1:1/pay/return?payment=${PAYMENT}` }) }));
    });
    // The real provider's page is outside Palee: stop there.
    await page.route("http://127.0.0.1:1/**", (route) => route.fulfill({ status: 200, contentType: "text/html", body: "<p>provider page</p>" }));

    await page.goto(`/me/payments?payment=${CHARGE}`);
    const card = page.getByTestId("pay-focus");
    await expect(card.getByText("Η χρέωση της κάρτας ••4421 δεν έγινε.", { exact: false })).toBeVisible();
    await card.getByTestId("pay-other-card").click();
    const sheet = page.getByTestId("pay-invoice-sheet");
    await sheet.getByTestId("pay-auto-yes").click();
    await expect(sheet.getByTestId("pay-submit")).toHaveText(/Πληρωμή 75,00\s€ με Viva/);
    await sheet.getByTestId("pay-submit").click();
    await expect.poll(() => calls.length).toBe(1);
    expect(calls[0].body).toMatchObject({ save_card: true, consent_accepted: true, autopay: true, language: "el" });
  });
});

const publicBox = {
  box: { organization_id: "org-1", slug: "kypseli", name: "Box Kypseli", logo_url: null, primary_color: null },
  followers_count: 3,
  profile: { about: "Box", disciplines: ["crossfit"], audiences: [], services: [], amenities: [], languages: ["el"], cover: null, photos: [], coaches: [] },
  locations: [{ id: "loc-1", name: "Kypseli", neighbourhood: "Κυψέλη", city: "Αθήνα", country_code: "GR", accessibility: [], opening_hours: [] }],
};

test.describe("the box's sales page (mockup s5 option C)", () => {
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

  test("a visitor sees the trial first, three packages, «Όλα», and signs in to buy", async ({ page }) => {
    await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
    await page.route("**/api/public/boxes/kypseli/packages", (route) => route.fulfill(json(sales)));

    await page.goto("/b/kypseli/packages");
    await expect(page.getByRole("heading", { name: "Box Kypseli" })).toBeVisible();
    const trial = page.getByTestId("sales-trial");
    await expect(trial.getByText(/Δοκιμαστικό τμήμα με 10,00/)).toBeVisible();
    await expect(page.getByTestId("sales-package-unl")).toBeVisible();
    await expect(page.getByTestId("sales-package-w3")).toBeVisible();
    await expect(page.getByTestId("sales-package-v12")).toBeVisible();
    await expect(page.getByText("Πρωινά")).toHaveCount(0);
    await page.getByTestId("sales-all").click();
    await expect(page.getByText("Πρωινά")).toBeVisible();
    await expect(page.getByText(/Πληρωμές μέσω Viva/)).toBeVisible();

    await page.getByTestId("sales-package-unl").getByRole("button", { name: "Αγορά" }).click();
    const dialog = page.getByTestId("sales-buy");
    await expect(dialog.getByText("Για να αγοράσεις, συνδέσου ή φτιάξε λογαριασμό Palee.")).toBeVisible();
    await expect(dialog.getByTestId("sales-login")).toHaveAttribute("href", `/login?next=${encodeURIComponent("/b/kypseli/packages?buy=unl")}`);
    await expect(page).toHaveURL(/buy=unl/);
  });
});
