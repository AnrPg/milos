import { expect, test, type Page, type Route } from "./support/test";

import { chooseOption } from "./support/select";

// «Είσπραξη» with Tap to Pay on the staff phone (mockup pilot-gaps screen 2,
// alternative A; ADR-249, ADR-264, ADR-272): Ποιος › Τι › Έλεγχος ›
// Viva.com Terminal › Αποτέλεσμα. The API is stubbed and the phone is the
// Android app with a stubbed «PaleeVivaTerminal» plugin; anything not
// stubbed answers `{}`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const USER = {
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

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: USER.id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const MEMBERSHIP = {
  role: "front_desk",
  roles: ["front_desk"],
  capabilities: { take_payments: "all", check_in: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Κυψέλη", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Κυψέλη", brand_logo_url: null, brand_primary_color: null },
};

// The Android app: Capacitor's bridge with the terminal plugin. `pay` answers
// on the `result` listener the way the «Viva.com Terminal» app calls back.
const ANDROID_APP = `
window.androidBridge = { postMessage() {} };
window.__viva = { pays: [], listeners: [], status: "success", installed: true, pending: null };
window.Capacitor = {
  isNativePlatform: () => true,
  getPlatform: () => "android",
  isPluginAvailable: (name) => name === "PaleeVivaTerminal",
  PluginHeaders: [{ name: "PaleeVivaTerminal", methods: [] }],
  Plugins: {
    PaleeVivaTerminal: {
      isAvailable: async () => ({ available: window.__viva.installed }),
      pay: async (options) => {
        window.__viva.pays.push(options);
        const reference = options.params.clientTransactionId;
        setTimeout(() => {
          const url = "palee-terminal://result?status=" + window.__viva.status + "&clientTransactionId=" + encodeURIComponent(reference) + "&transactionId=tx-1";
          window.__viva.listeners.forEach((listener) => listener({ url }));
        }, 50);
        return { launched: true };
      },
      takePendingResult: async () => {
        const url = window.__viva.pending;
        window.__viva.pending = null;
        return { url };
      },
      addListener: async (_event, listener) => {
        window.__viva.listeners.push(listener);
        return { remove: async () => { window.__viva.listeners = window.__viva.listeners.filter((entry) => entry !== listener); } };
      },
    },
  },
};`;

const MARIA = { user_id: "maria", name: "Μαρία Κωνσταντίνου", avatar_url: null, relation: "member", checked_in_at: "2026-10-29T06:58:00Z" };
const NIKOS = { user_id: "nikos", name: "Νίκος Αλεξίου", avatar_url: null, relation: "guest", checked_in_at: "2026-10-29T06:51:00Z" };

const PACKAGES = [
  { id: "pkg-12", name: "12 επισκέψεις", price_cents: 9000, currency: "EUR" },
  { id: "pkg-8", name: "8 επισκέψεις", price_cents: 6500, currency: "EUR" },
];

const DOCUMENT = (overrides: Record<string, unknown> = {}) => ({
  id: "doc-1",
  kind: "receipt",
  number: "R-000420",
  gross_cents: 9180,
  currency: "EUR",
  issued_at: "2026-10-29T07:02:05Z",
  authority: "mydata",
  transmission_status: "accepted",
  receipt_url: null,
  ...overrides,
});

type Write = { method: string; path: string; body: unknown };

type Stub = {
  availability?: { available: boolean; reason: string | null; provider: string | null };
  answer?: (started: Record<string, unknown>) => Record<string, unknown>;
  pendingPayment?: Record<string, unknown>;
};

function payment(overrides: Record<string, unknown>) {
  return {
    id: "pi-1",
    provider: "viva",
    environment: "live",
    user_id: null,
    initiation: "terminal",
    purpose_type: "free_sale",
    purpose_id: "fs-1",
    amount_cents: 1200,
    currency: "EUR",
    description: "Day pass",
    status: "awaiting_payer",
    fulfilment_status: "pending",
    refunded_cents: 0,
    declines: 0,
    retries: 0,
    reference: "pt1.pi-1",
    failure_code: null,
    tip_cents: 0,
    surcharge_cents: 0,
    started_on: "phone",
    started_by_id: USER.id,
    tip_attribution: null,
    tip_recipient_user_id: null,
    tip_recipient_role: null,
    document: null,
    fiscal_document_id: null,
    app_request: {
      scheme: "vivapayclient://pay/v1",
      params: { merchantKey: "m", appId: "palee", action: "sale", clientTransactionId: "pt1.pi-1", amount: "1200", callback: "palee-terminal://result" },
      url: "vivapayclient://pay/v1?clientTransactionId=pt1.pi-1",
    },
    ...overrides,
  };
}

async function stub(page: Page, options: Stub, writes: Write[]) {
  let current: Record<string, unknown> | null = options.pendingPayment ?? null;
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.addInitScript(ANDROID_APP);
  await page.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = tenantless(url.pathname);
    const method = route.request().method();
    const body = method === "GET" || method === "DELETE" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ method, path, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: token(), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, USER);
    if (path === "/api/memberships") return json(route, [MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/payments/terminal/availability") {
      return json(route, options.availability ?? { available: true, reason: null, provider: "viva" });
    }
    if (path === "/api/admin/payments/desk/people") {
      const q = (url.searchParams.get("q") ?? "").toLowerCase();
      const people: Array<Record<string, unknown>> = q ? [MARIA, NIKOS].filter((person) => person.name.toLowerCase().includes(q)) : [MARIA, NIKOS];
      if (q === "kostas@example.com") people.push({ user_id: "kostas", name: "Κώστας Π.", avatar_url: null, relation: "none", checked_in_at: null });
      return json(route, { people });
    }
    if (path === "/api/admin/payments/desk/options") {
      const userId = url.searchParams.get("user_id");
      if (userId === "maria") {
        return json(route, {
          options: {
            user_id: "maria",
            relation: "member",
            renewal: { ...PACKAGES[0], ends_on: "2026-10-29" },
            invoices: [{ id: "inv-212", number: "I-000212", description: "Προσωπική προπόνηση 21/10", balance_due_cents: 3000, currency: "EUR" }],
            packages: PACKAGES,
            shop_orders: [],
          },
        });
      }
      return json(route, {
        options: { user_id: userId, relation: userId ? "guest" : "walk_in", renewal: null, invoices: [], packages: userId ? PACKAGES : [], shop_orders: [] },
      });
    }
    if (path === "/api/admin/payments/desk/guests") {
      const guest = body as { user_id?: string; name?: string; email?: string };
      const person = guest.user_id
        ? { user_id: guest.user_id, name: "Κώστας Π.", avatar_url: null, relation: "guest", checked_in_at: null }
        : { user_id: "new-guest", name: guest.name, avatar_url: null, relation: "guest", checked_in_at: null };
      return json(route, { person, created_profile: !guest.user_id, added: true }, 201);
    }
    if (path === "/api/admin/payments/terminal" && method === "POST") {
      const start = body as Record<string, unknown>;
      current = payment({
        user_id: start.user_id ?? null,
        purpose_type: start.purpose,
        amount_cents: start.amount_cents,
        description: start.description ?? (start.purpose === "membership_package" ? "12 επισκέψεις" : "Πληρωμή"),
      });
      return json(route, { payment: current }, 201);
    }
    if (path === "/api/admin/payments/terminal/result") {
      current = { ...current!, app_request: null, ...(options.answer ? options.answer(current!) : {}) };
      return json(route, { payment: current });
    }
    const one = path.match(/^\/api\/admin\/payments\/terminal\/([^/]+)$/);
    if (one) return json(route, { payment: current });
    if (/^\/api\/admin\/payments\/terminal\/[^/]+\/receipt-email$/.test(path)) {
      return json(route, { email: { id: "mail-1", to: (body as { to?: string }).to ?? "maria@example.com", status: "queued" } }, 202);
    }
    return json(route, {});
  });
}

const paidWithTip = (started: Record<string, unknown>) => ({
  status: "succeeded",
  fulfilment_status: "fulfilled",
  card_brand: "visa",
  card_last4: "4421",
  succeeded_at: "2026-10-29T07:02:00Z",
  tip_cents: 500,
  surcharge_cents: 180,
  tip_attribution: "started_payment",
  tip_recipient_user_id: USER.id,
  document: DOCUMENT({ gross_cents: (started.amount_cents as number) + 180, receipt_url: started.user_id ? null : "http://127.0.0.1/api/public/receipts/signed" }),
});

test("a member's renewal: one button a step, the tip for me apart, the receipt by email", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, { answer: paidWithTip }, writes);
  await page.goto("/admin/collect");

  await expect(page.getByText("Έκαναν check-in σήμερα")).toBeVisible();
  await page.getByTestId("collect-people").getByText("Μαρία Κωνσταντίνου").click();

  await expect(page.getByText("Τι πληρώνει;")).toBeVisible();
  const renewal = page.getByTestId("collect-choice-renewal");
  await expect(renewal).toContainText("Ανανέωση: «12 επισκέψεις»");
  await expect(renewal).toContainText("Προτείνεται");
  await expect(renewal).toHaveAttribute("aria-checked", "true");
  await page.getByTestId("collect-continue").click();

  await expect(page.getByTestId("collect-confirm")).toContainText("90,00 €");
  await page.getByTestId("collect-charge").click();

  const result = page.getByTestId("collect-result-paid");
  await expect(result).toContainText("Πληρώθηκαν 96,80 €");
  await expect(page.getByTestId("collect-tip-owner")).toHaveText("Φιλοδώρημα · για σένα, όχι στην απόδειξη");
  await expect(page.getByTestId("collect-breakdown")).toContainText("Επιβάρυνση κάρτας · στην απόδειξη");
  await expect(page.getByTestId("collect-receipt-title")).toHaveText("Απόδειξη R-000420 · 91,80 €");
  await expect(page.getByTestId("collect-receipt")).toContainText("Μαρία Κωνσταντίνου · Κάρτα (Tap to Pay)");
  await expect(page.getByTestId("collect-tx")).toHaveText("myDATA");
  await expect(page.getByTestId("collect-qr")).toHaveCount(0);

  expect(writes.find((w) => w.path === "/api/admin/payments/terminal")?.body).toMatchObject({
    purpose: "membership_package",
    purpose_id: "pkg-12",
    user_id: "maria",
    amount_cents: 9000,
    started_on: "phone",
  });
  expect(writes.find((w) => w.path === "/api/admin/payments/terminal/result")?.body).toEqual({
    reference: "pt1.pi-1",
    status: "success",
    transaction_id: "tx-1",
    message: null,
  });

  await page.getByTestId("collect-send-email").click();
  await page.getByTestId("collect-email-send").click();
  await expect(page.getByTestId("collect-email-sent")).toContainText("Στάλθηκε με email");
  const email = writes.find((w) => w.path.endsWith("/receipt-email"))?.body as Record<string, unknown>;
  expect(email.to).toBeUndefined();

  await page.getByTestId("collect-new").click();
  await expect(page.getByText("Ποιος πληρώνει;")).toBeVisible();
});

test("a customer without an account: the free sale's errors stay under their fields, then the QR receipt", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, { answer: paidWithTip }, writes);
  await page.goto("/admin/collect");

  await page.getByTestId("collect-walk-in").click();
  await expect(page.getByText("Πακέτο συνδρομής ή τιμολόγιο πληρώνει μόνο μέλος ή επισκέπτης του box.")).toBeVisible();
  await expect(page.getByTestId("collect-choice-free")).toHaveAttribute("aria-checked", "true");

  await page.getByTestId("collect-continue").click();
  const form = page.getByTestId("collect-free-sale");
  await expect(form.getByText("Γράψε τι πουλάς. Τυπώνεται στην απόδειξη.")).toBeVisible();
  await expect(form.getByText("Γράψε ποσό πάνω από 0.")).toBeVisible();
  await expect(page.getByTestId("collect-description")).toHaveAttribute("aria-invalid", "true");

  await page.getByTestId("collect-description").fill("Day pass");
  await page.getByTestId("collect-amount").fill("12");
  await page.getByTestId("collect-category-product").click();
  await page.getByTestId("collect-continue").click();

  await expect(page.getByTestId("collect-confirm")).toContainText("Πελάτης χωρίς λογαριασμό");
  await expect(page.getByTestId("collect-confirm")).toContainText("12,00 €");
  await page.getByTestId("collect-charge").click();

  await expect(page.getByTestId("collect-result-paid")).toBeVisible();
  await expect(page.getByTestId("collect-receipt")).toContainText("Πελάτης λιανικής · Κάρτα (Tap to Pay)");
  await expect(page.getByTestId("collect-qr")).toContainText("Ο πελάτης σκανάρει και κρατά την απόδειξη στο κινητό του.");
  await expect(page.getByTestId("collect-qr").getByRole("img", { name: "QR της απόδειξης" })).toBeVisible();

  expect(writes.find((w) => w.path === "/api/admin/payments/terminal")?.body).toMatchObject({
    purpose: "free_sale",
    user_id: null,
    amount_cents: 1200,
    description: "Day pass",
    charge_category: "product",
  });

  await page.getByTestId("collect-send-email").click();
  await page.getByTestId("collect-email-send").click();
  await expect(page.getByTestId("collect-email-form").getByText("Γράψε ένα σωστό email.")).toBeVisible();
  await page.getByTestId("collect-email-to").fill("walkin@example.com");
  await page.getByTestId("collect-email-send").click();
  await expect(page.getByTestId("collect-email-sent")).toBeVisible();
  expect((writes.find((w) => w.path.endsWith("/receipt-email"))?.body as Record<string, unknown>).to).toBe("walkin@example.com");
});

test("someone not in the box becomes a guest from «Ποιος;», buys a package, and Viva has not confirmed yet", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, { answer: () => ({ status: "awaiting_payer", failure_code: "terminal_unconfirmed" }) }, writes);
  await page.goto("/admin/collect");

  await page.getByTestId("collect-search").fill("kostas@example.com");
  await page.getByTestId("collect-people").getByText("Κώστας Π.").click();
  await expect(page.getByTestId("collect-outsider")).toContainText("Δεν είναι στο box.");
  await page.getByTestId("collect-promote").click();
  expect(writes.find((w) => w.path === "/api/admin/payments/desk/guests")?.body).toEqual({ user_id: "kostas" });

  await expect(page.getByText("Τι πληρώνει;")).toBeVisible();
  await page.getByTestId("collect-choice-package").click();
  await page.getByTestId("collect-continue").click();
  await expect(page.getByText("Διάλεξε πακέτο.")).toBeVisible();
  await chooseOption(page, page.getByTestId("collect-package"), "pkg-8");
  await page.getByTestId("collect-continue").click();
  await expect(page.getByTestId("collect-confirm")).toContainText("65,00 €");
  await page.getByTestId("collect-charge").click();

  const unconfirmed = page.getByTestId("collect-result-unconfirmed");
  await expect(unconfirmed).toContainText("Περιμένουμε τη Viva");
  await expect(unconfirmed.getByText("Μην χρεώσεις ξανά.")).toBeVisible();
  expect(writes.find((w) => w.path === "/api/admin/payments/terminal")?.body).toMatchObject({
    purpose: "membership_package",
    purpose_id: "pkg-8",
    user_id: "kostas",
  });
});

test("a new guest from a walk-in's name and email; a declined card", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, { answer: () => ({ status: "failed", failure_code: "terminal_declined" }) }, writes);
  await page.goto("/admin/collect");

  await page.getByTestId("collect-new-guest").click();
  const form = page.getByTestId("collect-guest-form");
  await page.getByTestId("collect-guest-save").click();
  await expect(form.getByText("Γράψε το όνομά του.")).toBeVisible();
  await expect(form.getByText("Γράψε ένα σωστό email.")).toBeVisible();
  await page.getByTestId("collect-guest-name").fill("Γιώργος Ν.");
  await page.getByTestId("collect-guest-email").fill("giorgos@example.com");
  await page.getByTestId("collect-guest-save").click();
  expect(writes.find((w) => w.path === "/api/admin/payments/desk/guests")?.body).toEqual({ name: "Γιώργος Ν.", email: "giorgos@example.com" });

  await expect(page.getByText("Γιώργος Ν.")).toBeVisible();
  await page.getByTestId("collect-choice-package").click();
  await chooseOption(page, page.getByTestId("collect-package"), "pkg-12");
  await page.getByTestId("collect-continue").click();
  await page.getByTestId("collect-charge").click();
  await expect(page.getByTestId("collect-result-declined")).toContainText("Η κάρτα απορρίφθηκε");
  await expect(page.getByTestId("collect-result-declined")).toContainText("Δεν χρεώθηκε τίποτα και δεν βγήκε απόδειξη.");
});

test("after iOS reset the app at the PIN, the answer waiting in the plugin becomes the result", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, { answer: paidWithTip, pendingPayment: payment({ user_id: "maria", amount_cents: 9000, description: "12 επισκέψεις" }) }, writes);
  await page.addInitScript(() => {
    (window as unknown as { __viva: { pending: string } }).__viva.pending =
      "palee-terminal://result?status=success&clientTransactionId=pt1.pi-1&transactionId=tx-1";
  });
  await page.goto("/admin/collect");
  await expect(page.getByTestId("collect-result-paid")).toContainText("Πληρώθηκαν 96,80 €");
  expect(writes.find((w) => w.path === "/api/admin/payments/terminal/result")?.body).toMatchObject({ reference: "pt1.pi-1", status: "success" });
});

test("without Viva the phone says why and where to connect it", async ({ page }) => {
  await stub(page, { availability: { available: false, reason: "stripe_only", provider: "stripe" } }, []);
  await page.goto("/admin/collect");
  const card = page.getByTestId("collect-unavailable");
  await expect(card).toContainText("Tap to Pay θέλει σύνδεση με Viva");
  await expect(card).toContainText("Με Stripe δεν γίνεται ακόμη.");
  await expect(card.getByRole("link", { name: "Ρυθμίσεις › Πληρωμές" })).toHaveAttribute("href", /\/admin\/settings\?tab=payments$/);
});
