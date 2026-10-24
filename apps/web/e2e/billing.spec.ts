import { expect, test, type Page } from "./support/test";

import { chooseOption } from "./support/select";

// Εγώ › Πληρωμές: a member of one box sees its summary and the three
// segments; someone without a provider never sees the entry and the route
// sends them back to Εγώ; two providers get a dropdown. The API is stubbed;
// anything not stubbed answers `{}`.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const isoDay = (days: number) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
};

function persona(slugs: string[] = ["kypseli"]) {
  const id = "member-1";
  const user = {
    id,
    nickname: "Maria",
    role: "member",
    email: `${id}@example.com`,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: slugs.map((slug) => ({ organization_slug: slug, role: "member", settings: {} })),
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role: "member", memberships: slugs.map((slug) => ({ organization_slug: slug })), exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = (slug: string, name: string, roles: string[], extra: Record<string, unknown> = {}) => ({
  id: `m-${slug}`,
  role: roles[0],
  roles,
  capabilities: {},
  organization: { id: `org-${slug}`, slug, name, provider_kind: "gym", activation: "active", ...extra },
  settings: { brand_name: name, brand_logo_url: null, brand_primary_color: null },
});

function section(slug: string, name: string, overrides: Record<string, unknown> = {}) {
  return {
    organization_id: `org-${slug}`,
    name,
    slug,
    kind: "gym",
    logo_url: null,
    primary_color: null,
    partial: false,
    contact: { box_chat_slug: slug },
    actions: { self_service_purchase: false, self_service_cancel_auto_renew: false, download_invoices: true },
    membership: { status: "active", entitlement_status: "active", starts_on: isoDay(-10), expires_on: null },
    entitlement: {
      status: "active",
      enforcement_mode: "enforce",
      plan: { entitlement_version: 1, channels: [], capabilities: [] },
      allowances: {
        class_visits: { limit: 12, remaining: 5, period: "subscription_period", period_start: isoDay(-10), period_end: isoDay(20), committed: 7, extensions: 0 },
      },
    },
    subscriptions: [
      {
        id: "sub-1",
        status: "active",
        current: true,
        package_name: "12 visits",
        package_type: "visits",
        billing_period: "monthly",
        price_cents: 8900,
        starts_on: isoDay(-10),
        ends_on: isoDay(20),
        commitment_ends_on: null,
        auto_renew: true,
        corporate: false,
      },
      {
        id: "sub-0",
        status: "expired",
        current: false,
        package_name: "Trial month",
        starts_on: isoDay(-60),
        ends_on: isoDay(-30),
        auto_renew: false,
        corporate: false,
      },
    ],
    invoices: [
      {
        id: "inv-1",
        invoice_number: "INV-0042",
        document_kind: "invoice",
        status: "issued",
        issue_date: isoDay(-2),
        due_date: isoDay(5),
        total_cents: 4000,
        balance_due_cents: 4000,
        currency: "EUR",
        downloadable: true,
      },
    ],
    payments: [{ id: "pay-1", amount_cents: 8900, net_amount_cents: 8900, currency: "EUR", paid_on: isoDay(-9), payment_method: "card", payment_status: "paid" }],
    refund_receipts: [],
    promotions: [{ id: "promo-1", campaign_name: "Autumn welcome", discount_type: "percent", discount_value: 20, redeemed_at: `${isoDay(-9)}T10:00:00Z` }],
    seasons: [],
    referrals: { credits: [], credit_total_cents: 0, invited: 2, trials: 1, paid: 1 },
    trials: [],
    available_offers: [{ id: "code-1", code: "AUTUMN20", campaign_name: "Autumn welcome", discount_type: "percent", discount_value: 20, ends_on: isoDay(30) }],
    perks: [],
    outstanding_cents: 4000,
    credit_balance_cents: 0,
    ...overrides,
  };
}

const transactions = [
  {
    id: "invoice:inv-1",
    kind: "invoice",
    source_id: "inv-1",
    counterparty: { organization_id: "org-kypseli", name: "Box Kypseli", kind: "gym", slug: "kypseli" },
    title: "INV-0042",
    amount_cents: 4000,
    currency: "EUR",
    status: "issued",
    date: `${isoDay(-2)}T00:00:00Z`,
    details: {
      document_kind: "invoice",
      invoice_number: "INV-0042",
      due_date: isoDay(5),
      balance_due_cents: 4000,
      downloadable: true,
      lines: [
        { description: "12 visits", quantity: 1, unit_amount_cents: 3000, total_cents: 3000 },
        { description: "Protein bars", quantity: 2, unit_amount_cents: 500, total_cents: 1000 },
      ],
    },
  },
  {
    id: "event_refund:refund-a1",
    kind: "event_refund",
    source_id: "refund-a1",
    counterparty: { organization_id: "org-run", name: "Eleni", kind: "organiser", slug: null },
    title: "Sunrise run",
    amount_cents: -500,
    currency: "EUR",
    status: "refunded",
    date: `${isoDay(-4)}T09:00:00Z`,
    details: { event_id: "ev-1" },
  },
  {
    id: "event_payment:a1",
    kind: "event_payment",
    source_id: "a1",
    counterparty: { organization_id: "org-run", name: "Eleni", kind: "organiser", slug: null },
    title: "Sunrise run",
    amount_cents: 1500,
    currency: "EUR",
    status: "paid",
    date: `${isoDay(-6)}T09:00:00Z`,
    details: { payment_method: "cash", event_id: "ev-1" },
  },
];

async function common(page: Page, memberships: unknown[], providers: unknown[], locale = "en") {
  const me = persona(memberships.length > 0 ? ["kypseli"] : []);
  await page.context().addCookies([{ name: "palee_locale", value: locale, url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: me.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(me.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/billing", (route) => route.fulfill(json({ providers })));
  await page.route("**/api/me/billing/transactions**", (route) =>
    route.fulfill(json({ transactions, next_cursor: null, total: transactions.length, kinds: ["invoice", "event_payment", "event_refund"], partial: false })),
  );
}

test.describe("billing", () => {
  test("a member of one box sees the summary and the three segments", async ({ page }) => {
    await common(page, [membership("kypseli", "Box Kypseli", ["member"])], [section("kypseli", "Box Kypseli")]);
    const downloads: string[] = [];
    await page.route("**/api/org/kypseli/me/invoices/inv-1/download-url", (route) => {
      downloads.push(route.request().url());
      return route.fulfill(json({ download_url: "about:blank", file_name: "INV-0042.pdf" }));
    });

    await page.goto("/me");
    await page.getByRole("link", { name: /Payments & receipts/ }).click();
    await expect(page).toHaveURL(/\/me\/payments/);

    await expect(page.getByRole("heading", { name: "Payments" })).toBeVisible();
    // One provider: no picker.
    await expect(page.getByRole("combobox", { name: "Choose a gym or coach" })).toHaveCount(0);
    await expect(page.getByText("12 visits").first()).toBeVisible();
    await expect(page.getByText("5 of 12 sessions left")).toBeVisible();
    await expect(page.getByRole("progressbar", { name: "Validity" })).toBeVisible();
    await expect(page.getByText("€40.00").first()).toBeVisible();
    await expect(page.getByText("Pay at the box")).toBeVisible();
    await expect(page.getByRole("link", { name: "Contact the box" })).toHaveAttribute("href", "/b/kypseli/chat");

    // «Συνδρομή»: details and history.
    await expect(page.getByText("Package history")).toBeVisible();
    await expect(page.getByText("Trial month")).toBeVisible();

    // «Συναλλαγές»: one feed, events at any host included; a row opens its details.
    await page.getByRole("tab", { name: "Transactions" }).click();
    await expect(page).toHaveURL(/tab=transactions/);
    await expect(page.getByRole("button", { name: /Ticket refund · Sunrise run/ })).toBeVisible();
    await expect(page.getByText("Eleni ·").first()).toBeVisible();
    await expect(page.getByText("Shown: €50.00")).toBeVisible();
    // Ten entries or fewer: no kind filter.
    await expect(page.getByRole("combobox", { name: "Filter transactions" })).toHaveCount(0);
    await page.getByRole("button", { name: /Invoice · INV-0042/ }).click();
    const dialog = page.getByRole("dialog", { name: "Invoice · INV-0042" });
    await expect(dialog.getByText("Protein bars")).toBeVisible();
    await expect(dialog.getByText("2 × €5.00")).toBeVisible();
    await dialog.getByRole("button", { name: "Download" }).click();
    await expect.poll(() => downloads.length).toBe(1);
    await dialog.getByRole("button", { name: "Close" }).last().click();
    await expect(dialog).toHaveCount(0);

    // «Προσφορές»: codes first, then claimed offers and referral counts.
    await page.getByRole("tab", { name: "Offers" }).click();
    await expect(page).toHaveURL(/tab=offers/);
    await expect(page.getByText("Codes you can use")).toBeVisible();
    await expect(page.getByRole("button", { name: "Copy code AUTUMN20" })).toBeVisible();
    await expect(page.getByText("Offers you used")).toBeVisible();
    await expect(page.getByText("2 invited · 1 joined and paid")).toBeVisible();
    await expect(page.getByRole("link", { name: /Bring a friend ›/ })).toHaveAttribute("href", "/me/referrals?box=kypseli");
    // Empty groups stay hidden.
    await expect(page.getByText("Seasons & challenges")).toHaveCount(0);

    // Back returns to the previous segment.
    await page.goBack();
    await expect(page).toHaveURL(/tab=transactions/);
  });

  for (const locale of ["en", "el", "de", "ru", "fr", "bg", "es", "it", "nl", "pt-PT"]) {
    test(`the segment row fits a 320px phone without sideways scroll (${locale})`, async ({ page }) => {
      await page.setViewportSize({ width: 320, height: 700 });
      await common(page, [membership("kypseli", "Box Kypseli", ["member"])], [section("kypseli", "Box Kypseli")], locale);
      await page.goto("/me/payments");
      // One row of three tabs (a dropdown would replace the tablist).
      await expect(page.getByRole("tablist")).toBeVisible();
      await expect(page.getByRole("tab")).toHaveCount(3);
      const tops = await page.getByRole("tab").evaluateAll((tabs) => tabs.map((tab) => Math.round(tab.getBoundingClientRect().top)));
      expect(new Set(tops).size).toBe(1);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      expect(overflow).toBeLessThanOrEqual(0);
    });
  }

  test("someone without a provider sees no entry and is sent back to Εγώ", async ({ page }) => {
    // An athlete with no gym or coach (staff-only roles and demo businesses
    // are covered by the unit and API tests).
    await common(page, [], []);
    let billingCalls = 0;
    await page.route("**/api/me/billing", (route) => {
      billingCalls += 1;
      return route.fulfill(json({ providers: [] }));
    });

    await page.goto("/me");
    await expect(page.getByRole("link", { name: /^Settings/ })).toBeVisible();
    await expect(page.getByRole("link", { name: /Payments & receipts/ })).toHaveCount(0);

    await page.goto("/me/payments");
    await expect(page).toHaveURL(/\/me$/);
    expect(billingCalls).toBe(0);
  });

  test("two providers get a dropdown that switches the section", async ({ page }) => {
    await common(
      page,
      [membership("kypseli", "Box Kypseli", ["member"]), membership("nikos", "Nikos PT", ["member"], { provider_kind: "coach" })],
      [
        section("kypseli", "Box Kypseli"),
        section("nikos", "Nikos PT", {
          kind: "coach",
          contact: { box_chat_slug: null },
          subscriptions: [],
          invoices: [],
          payments: [],
          promotions: [],
          entitlement: null,
          outstanding_cents: 0,
        }),
      ],
    );

    await page.goto("/me/payments");
    const picker = page.getByRole("combobox", { name: "Choose a gym or coach" });
    await expect(picker).toBeVisible();
    await expect(page.getByText("5 of 12 sessions left")).toBeVisible();

    await chooseOption(page, picker, "nikos");
    await expect(page).toHaveURL(/box=nikos/);
    await expect(page.getByText("Personal coach")).toBeVisible();
    await expect(page.getByText("No active package right now.")).toBeVisible();
    await expect(page.getByRole("link", { name: "Message your coach" })).toHaveAttribute("href", "/messages?filter=coach");
  });
});
