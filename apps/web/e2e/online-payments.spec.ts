import { expect, test, type Page, type Route } from "./support/test";

import { chooseOption } from "./support/select";

// Online payments for staff (mockup s3, option B; ADR-246/260/261):
// Ρυθμίσεις › Πληρωμές is one card with defaults, and failed saved-card
// charges that need a person show in Οικονομικά › Εκκρεμότητες. The API is stubbed;
// anything not stubbed answers `{}`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const USER = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: USER.id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const MEMBERSHIP = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, manage_billing: true, take_payments: "all", view_finance_reports: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const OPTIONS = {
  purposes: { packages: true, autopay: true, drop_in: true, shop: true, personal_training: true },
  notify_member: true,
  notify_staff: true,
};

type Write = { method: string; path: string; body: unknown };

type Stub = {
  connect?: string[];
  connected?: boolean;
  connectUrl?: string;
  failed?: Array<Record<string, unknown>>;
};

async function stub(page: Page, options: Stub, writes: Write[]) {
  let account: Record<string, unknown> | null = options.connected
    ? {
        id: "acc-1",
        provider: "viva",
        environment: "live",
        status: "active",
        settings: { source_code: "1234" },
        credentials_set: ["client_id", "client_secret", "merchant_id", "api_key"],
        webhook_url: "https://palee.app/api/webhooks/payments/org-1/acc-1",
        options: OPTIONS,
        connection: "keys",
      }
    : null;
  let grace = 7;
  const status = () => ({
    account,
    providers: ["viva", "stripe"],
    environments: ["test", "live"],
    connect_providers: { live: options.connect ?? [], test: [] },
  });

  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" || method === "DELETE" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ method, path, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: token(), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, USER);
    if (path === "/api/memberships") return json(route, [MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/settings") {
      if (method === "PATCH") grace = (body as { finance: { subscription_grace_days: number } }).finance.subscription_grace_days;
      return json(route, { gamification: {}, finance: { subscription_grace_days: grace, payment_reminder_interval_days: 7 }, scheduling: {} });
    }
    if (path === "/api/admin/payments/account" && method === "PUT") {
      const update = body as { provider: string; environment: string; settings?: Record<string, string> };
      account = {
        id: "acc-1",
        provider: update.provider,
        environment: update.environment,
        status: "active",
        settings: update.settings ?? {},
        credentials_set: ["client_id", "client_secret", "merchant_id", "api_key"],
        webhook_url: "https://palee.app/api/webhooks/payments/org-1/acc-1",
        options: OPTIONS,
        connection: "keys",
      };
      return json(route, status());
    }
    if (path === "/api/admin/payments/account" && method === "DELETE") {
      account = account ? { ...account, status: "disabled" } : null;
      return json(route, status());
    }
    if (path === "/api/admin/payments/account") return json(route, status());
    if (path === "/api/admin/payments/account/options") {
      const update = body as { purposes?: Record<string, boolean>; notify_member?: boolean; notify_staff?: boolean };
      const current = account!.options as typeof OPTIONS;
      account = {
        ...account,
        options: { ...current, ...update, purposes: { ...current.purposes, ...(update.purposes ?? {}) } },
      };
      return json(route, status());
    }
    if (path === "/api/admin/payments/connect") return json(route, { url: options.connectUrl ?? "/admin/settings?tab=payments&connect=ok" });
    if (path === "/api/admin/payments/attention") return json(route, { payments: options.failed ?? [], total: (options.failed ?? []).length });
    const action = path.match(/^\/api\/admin\/payments\/([^/]+)\/(retry-charge|card-link|dismiss)$/);
    if (action) {
      const charge = (options.failed ?? []).find((row) => row.id === action[1]);
      return json(route, { payment: { ...charge, status: action[2] === "retry-charge" ? "succeeded" : charge?.status } });
    }
    if (path === "/api/admin/finance/queues") return json(route, { queues: {} });
    if (path === "/api/admin/finance/package-catalog") return json(route, { types: [], modules: [] });
    if (path.startsWith("/api/admin/finance/members")) return json(route, { members: [], meta: {} });
    return json(route, {});
  });
}

test("a box without one-button connect pastes its Viva keys, then sees one sentence and the policy", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, {}, writes);
  await page.goto("/admin/settings?tab=payments");

  const card = page.getByTestId("online-payments");
  await expect(card.getByText("Δέξου κάρτες στο app και στη σελίδα αγοράς")).toBeVisible();
  await card.getByRole("button", { name: "Σύνδεση με Viva" }).click();
  await expect(card.getByText("Σύνδεση Viva με κλειδιά API")).toBeVisible();

  const form = card.getByRole("form", { name: "Κλειδιά API" }).first();
  await form.getByLabel("Merchant ID").fill("merchant-1");
  await form.getByLabel("API key").fill("api-key-1");
  await form.getByLabel("Client ID").fill("client-1");
  await form.getByLabel("Client secret").fill("secret-1");
  await form.getByLabel("Κωδικός πηγής πληρωμών (source code)").fill("4321");
  await form.getByRole("button", { name: "Έλεγχος και αποθήκευση" }).click();

  await expect(card.getByText("Συνδεδεμένο με Viva")).toBeVisible();
  expect(writes.find((w) => w.path === "/api/admin/payments/account")?.body).toEqual({
    provider: "viva",
    environment: "live",
    credentials: { merchant_id: "merchant-1", api_key: "api-key-1", client_id: "client-1", client_secret: "secret-1" },
    settings: { source_code: "4321" },
  });
  await expect(card.getByTestId("online-sentence")).toContainText("Τα μέλη box πληρώνουν online πακέτα συνδρομής");

  // «Αλλαγή»: the shop stays at the desk.
  await card.getByRole("button", { name: "Αλλαγή" }).click();
  await card.getByRole("switch", { name: "Κατάστημα" }).click();
  await card.getByRole("button", { name: "Τέλος" }).click();
  await expect(card.getByTestId("online-sentence")).not.toContainText("κατάστημα");
  expect(writes.find((w) => w.path === "/api/admin/payments/account/options")?.body).toEqual({ purposes: { shop: false } });

  // «Προχωρημένα»: the grace days are Finance's own setting.
  await card.getByRole("button", { name: /Προχωρημένα/ }).click();
  await expect(card.getByText("3 φορές: σε 1, 3 και 7 ημέρες")).toBeVisible();
  await chooseOption(page, card.getByRole("combobox", { name: "Περίοδος χάριτος" }), "14");
  await expect.poll(() => writes.find((w) => w.path === "/api/admin/settings")?.body).toEqual({ finance: { subscription_grace_days: 14 } });

  // «Αποσύνδεση» asks first.
  await card.getByRole("button", { name: "Αποσύνδεση", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "Αποσύνδεση από Viva;" });
  await expect(dialog.getByText("Οι αποθηκευμένες κάρτες σταματούν να χρεώνονται.")).toBeVisible();
  await dialog.getByRole("button", { name: "Αποσύνδεση" }).click();
  await expect(card.getByText("Δέξου κάρτες στο app και στη σελίδα αγοράς")).toBeVisible();
  expect(writes.some((w) => w.method === "DELETE" && w.path === "/api/admin/payments/account")).toBe(true);
});

test("one button sends the owner to the provider and back to the settings", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, { connect: ["stripe"], connectUrl: "/admin/settings?tab=payments&connect=access_denied" }, writes);
  await page.goto("/admin/settings?tab=payments");

  await page.getByTestId("online-payments").getByRole("button", { name: "Stripe" }).click();
  await page.waitForURL(/connect=access_denied|tab=payments$/);
  await expect(page.getByText("Ακύρωσες στη σελίδα του παρόχου. Δεν άλλαξε τίποτα.")).toBeVisible();
  expect(writes.find((w) => w.path === "/api/admin/payments/connect")?.body).toEqual({ provider: "stripe", environment: "live" });
  await expect(page).toHaveURL(/\/admin\/settings\?tab=payments$/);
});

test("coming back connected says so", async ({ page }) => {
  await stub(page, { connected: true }, []);
  await page.goto("/admin/settings?tab=payments&connect=ok");
  await expect(page.getByText("Οι online πληρωμές συνδέθηκαν.")).toBeVisible();
  await expect(page.getByText("Συνδεδεμένο με Viva")).toBeVisible();
});

test("failed charges that need a person wait in Finance › Pending items", async ({ page }) => {
  const writes: Write[] = [];
  await stub(
    page,
    {
      connected: true,
      failed: [
        {
          id: "c1",
          member_name: "Ελένη Νικολάου",
          purpose_type: "finance_invoice",
          amount_cents: 7500,
          currency: "EUR",
          description: "Πακέτο συνδρομής «Unlimited»",
          status: "scheduled",
          failure_code: "insufficient_funds",
          next_attempt_at: new Date(Date.now() + 26 * 3600_000).toISOString(),
          declines: 2,
          retries: 3,
        },
        {
          id: "c2",
          member_name: "Δημήτρης Λαμπρόπουλος",
          purpose_type: "finance_invoice",
          amount_cents: 6000,
          currency: "EUR",
          description: "Πακέτο συνδρομής «3 φορές την εβδομάδα»",
          status: "failed",
          failure_code: "expired_card",
          next_attempt_at: null,
          declines: 3,
          retries: 3,
        },
      ],
    },
    writes,
  );
  await page.goto("/admin/finance?tab=queues&queue=failed_charges");

  const group = page.getByTestId("failed-charges");
  await expect(group.getByText("Το Palee ξαναδοκιμάζει μόνο του")).toBeVisible();
  const [first, second] = [group.getByTestId("failed-charge").nth(0), group.getByTestId("failed-charge").nth(1)];
  await expect(first.getByText("Ελένη Νικολάου")).toBeVisible();
  await expect(first.getByText("Ανεπαρκές υπόλοιπο")).toBeVisible();
  await expect(first.getByText(/\(2 από 3\)/)).toBeVisible();
  await expect(second.getByText("Η κάρτα έληξε")).toBeVisible();
  await expect(second.getByText("Περιμένουμε νέα κάρτα από το μέλος")).toBeVisible();

  await second.getByRole("button", { name: "Πληρώθηκε στο ταμείο" }).click();
  await expect(second.getByText(/Έγινε/)).toBeVisible();
  expect(writes.some((w) => w.path === "/api/admin/payments/c2/dismiss")).toBe(true);

  await first.getByRole("button", { name: "Σύνδεσμος για νέα κάρτα" }).click();
  await expect(first.getByText("Στάλθηκε σύνδεσμος αλλαγής κάρτας")).toBeVisible();
});
