import { expect, test, type Page, type Request } from "./support/test";

// Mockups s1 and s2 (ADR-240–245): Settings › «Στοιχεία τιμολόγησης» as a
// checklist with panels, and Finance › «Παραστατικά» grouped per day with a
// closed/open badge, the document panel, the credit note, the audit archive
// and the export for the accountant. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const pad = (value: number) => String(value).padStart(2, "0");
const localDay = (offset: number) => {
  const date = new Date();
  date.setDate(date.getDate() + offset);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};

async function signIn(page: Page) {
  const user = {
    id: "user-1",
    nickname: "Apostolos",
    role: "member",
    email: "owner@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_settings: "all", manage_finance: "all" },
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  };

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "staff");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  // The finance page around the documents tab.
  await page.route("**/api/org/box1/admin/finance/package-catalog", (route) => route.fulfill(json({ types: [], modules: [] })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
  await page.route("**/api/org/box1/admin/finance/summary**", (route) => route.fulfill(json({ totals: {} })));
  await page.route("**/api/org/box1/admin/finance/queues**", (route) => route.fulfill(json({ queues: {} })));
}

const GR = {
  country: "GR",
  currency: "EUR",
  languages: ["el", "en"],
  tax_system: "vat",
  authority: "mydata",
  register: "standard",
  till_device: "none",
  einvoicing: [],
  required_fields: ["legal_name", "street", "postal_code", "city", "tax_id", "tax_office"],
  tax_categories: ["standard"],
  tax_office: true,
  retention_years: 5,
};
const DE = { ...GR, country: "DE", authority: "none", till_device: "tse", required_fields: ["legal_name", "street", "postal_code", "city", "tax_id_or_vat_number"], tax_office: false };

// ADR-273: the «Συνδέσεις» card.
const MYDATA = {
  authority: "mydata",
  environment: "production",
  user_id: "kypseli_box",
  has_subscription_key: true,
  status: "active",
  error_code: null,
  checked_at: null,
  updated_at: "2026-10-29T12:32:00Z",
  updated_by_platform: false,
  updated_by_name: "Apostolos",
};
const connections = (saved: Record<string, unknown>, extra: Record<string, unknown> = {}) => ({
  country: "GR",
  kinds: ["mydata", "registry"],
  managed_by: "owner",
  connections: { mydata: null, registry: null, ...saved },
  ...extra,
});
const greekIdentity = {
  identity: {
    id: "identity-1",
    country_code: "GR",
    currency: "EUR",
    vat_scheme: "standard",
    branch_code: 0,
    fiscal_year_start_month: 1,
    legal_name: "KYPSELI ATHLETIC P.C.",
    tax_id: "801234567",
    tax_office: "Z Athens",
    street: "Fokionos Negri 12",
    postal_code: "11361",
    city: "Athens",
  },
  profile: GR,
  missing: [],
  complete: true,
};

test.describe("Settings › Billing details", () => {
  test("chooses the country first, then fills one row at a time", async ({ page }) => {
    await signIn(page);
    let identity: Record<string, unknown> | null = null;
    const sent: Record<string, unknown>[] = [];
    const status = () => {
      if (!identity) return { identity: null, profile: null, missing: ["country_code"], complete: false };
      const missing = ["legal_name", "tax_id", "tax_office", "street", "postal_code", "city"].filter((field) => !identity?.[field]);
      return { identity, profile: GR, missing, complete: missing.length === 0 };
    };
    await page.route("**/api/org/box1/admin/fiscal/countries", (route) => route.fulfill(json({ countries: [DE, GR], vat_schemes: ["standard", "small_business", "exempt"] })));
    await page.route("**/api/org/box1/admin/fiscal/connections", (route) =>
      route.fulfill(json(connections({ mydata: { ...MYDATA, status: "active" } }))),
    );
    await page.route("**/api/org/box1/admin/fiscal/identity", (route) => {
      if (route.request().method() === "PUT") {
        const body = bodyOf(route.request());
        sent.push(body);
        if (body.tax_id === "801234568") return route.fulfill(json({ code: "validation_failed", errors: { tax_id: ["check_digit"] } }, 422));
        identity = { id: "identity-1", currency: "EUR", vat_scheme: "standard", branch_code: 0, fiscal_year_start_month: 1, ...(identity ?? {}), ...body };
      }
      return route.fulfill(json(status()));
    });

    await page.goto("/admin/settings/billing");
    await expect(page.getByRole("heading", { name: "Billing details" })).toBeVisible();
    await expect(page.getByTestId("fiscal-row-business")).toBeDisabled();

    await page.getByTestId("fiscal-row-country").click();
    const countries = page.getByTestId("fiscal-country-panel");
    await countries.getByTestId("fiscal-country-GR").click();
    await countries.getByTestId("fiscal-country-done").click();
    await expect.poll(() => sent[0]).toEqual({ country_code: "GR" });
    await expect(page.getByTestId("fiscal-row-business")).toHaveAttribute("data-state", "next");

    await page.getByTestId("fiscal-row-business").click();
    const business = page.getByTestId("fiscal-panel-business");
    await business.getByTestId("fiscal-field-legal_name").fill("KYPSELI ATHLETIC P.C.");
    await business.getByTestId("fiscal-field-tax_id").fill("801234568");
    await business.getByTestId("fiscal-field-tax_office").fill("Z Athens");
    await business.getByTestId("fiscal-panel-save").click();
    await expect(business.getByText("This number is not valid: a digit is wrong.", { exact: false })).toBeVisible();
    await business.getByTestId("fiscal-field-tax_id").fill("801234567");
    await business.getByTestId("fiscal-panel-save").click();
    await expect(business).toBeHidden();
    await expect(page.getByTestId("fiscal-row-business")).toHaveAttribute("data-state", "done");

    await page.getByTestId("fiscal-row-address").click();
    const address = page.getByTestId("fiscal-panel-address");
    await address.getByTestId("fiscal-field-street").fill("Fokionos Negri 12");
    await address.getByTestId("fiscal-field-postal_code").fill("11361");
    await address.getByTestId("fiscal-field-city").fill("Athens");
    await address.getByTestId("fiscal-panel-save").click();

    await expect(page.getByTestId("fiscal-identity-ready")).toContainText("Receipts and invoices are issued legally.");
    await expect(page.getByTestId("fiscal-connection-mydata-status")).toHaveText("Connected");
    await expect(page.getByTestId("fiscal-connection-registry-status")).toHaveText("Not connected");
    await expect(page.getByRole("img", { name: "100% complete" })).toBeVisible();
  });

  test("fills the business row from the ΑΦΜ through AADE's registry (ADR-265)", async ({ page }) => {
    await signIn(page);
    const sent: Record<string, unknown>[] = [];
    const lookups: string[] = [];
    await page.route("**/api/org/box1/admin/fiscal/countries", (route) => route.fulfill(json({ countries: [DE, GR], vat_schemes: ["standard", "small_business", "exempt"] })));
    await page.route("**/api/org/box1/admin/fiscal/connections", (route) => route.fulfill(json(connections({}))));
    await page.route("**/api/org/box1/admin/fiscal/identity", (route) => {
      if (route.request().method() === "PUT") sent.push(bodyOf(route.request()));
      const identity = { id: "identity-1", country_code: "GR", currency: "EUR", vat_scheme: "standard", branch_code: 0, fiscal_year_start_month: 1, ...Object.assign({}, ...sent) };
      return route.fulfill(json({ identity, profile: GR, missing: sent.length ? [] : ["legal_name", "tax_id", "tax_office"], complete: sent.length > 0 }));
    });
    await page.route("**/api/org/box1/admin/fiscal/registry/businesses/*", (route) => {
      lookups.push(route.request().url().split("/").pop() ?? "");
      return route.fulfill(
        json({
          business: {
            tax_id: "090000045",
            legal_name: "KYPSELI ATHLETIC P.C.",
            trade_name: "KYPSELI STRONG",
            tax_office: "Z ATHENS",
            tax_office_code: "1118",
            street: "FOKIONOS NEGRI",
            building_number: "12",
            postal_code: "11361",
            city: "ATHENS",
            activity_code: "93130000",
            activity_description: "GYM SERVICES",
            activities: [],
            active: true,
            legal_status: "IKE",
            vat_registered: true,
          },
        }),
      );
    });

    await page.goto("/admin/settings/billing");
    await page.getByTestId("fiscal-row-business").click();
    const business = page.getByTestId("fiscal-panel-business");
    const lookup = business.getByTestId("fiscal-registry-lookup");
    await expect(lookup).toHaveText("Fill in from the tax ID");
    await expect(lookup).toBeDisabled();

    // A wrong check digit never reaches AADE.
    await business.getByTestId("fiscal-field-tax_id").fill("090000046");
    await expect(lookup).toBeDisabled();
    await business.getByTestId("fiscal-field-tax_id").fill("090000045");
    await expect(business).toContainText("Check digits: correct.");
    await lookup.click();

    await expect(business.getByTestId("fiscal-registry-found")).toContainText("Found in AADE's registry. Please check them.");
    await expect(business.getByTestId("fiscal-field-legal_name")).toHaveValue("KYPSELI ATHLETIC P.C.");
    await expect(business.getByTestId("fiscal-field-tax_office")).toHaveValue("Z ATHENS");
    expect(lookups).toEqual(["090000045"]);

    await business.getByTestId("fiscal-panel-save").click();
    await expect(business).toBeHidden();
    expect(sent[0]).toMatchObject({ tax_id: "090000045", street: "FOKIONOS NEGRI 12", postal_code: "11361", city: "ATHENS", activity_code: "93130000" });
  });

  test("connects myDATA in the side panel and runs «Connection test» (ADR-273)", async ({ page }) => {
    await signIn(page);
    const saves: Record<string, unknown>[] = [];
    let saved: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/fiscal/countries", (route) => route.fulfill(json({ countries: [DE, GR], vat_schemes: ["standard", "small_business", "exempt"] })));
    await page.route("**/api/org/box1/admin/fiscal/identity", (route) => route.fulfill(json(greekIdentity)));
    await page.route("**/api/org/box1/admin/fiscal/connections", (route) => route.fulfill(json(connections(saved ? { mydata: saved } : {}))));
    await page.route("**/api/org/box1/admin/fiscal/authority-connection", (route) => {
      const body = bodyOf(route.request());
      saves.push(body);
      if (!body.user_id) return route.fulfill(json({ code: "validation_failed", errors: { user_id: ["required"] } }, 422));
      if (body.subscription_key === "wrong-key") {
        saved = { ...MYDATA, status: "invalid", error_code: "credentials_rejected" };
        return route.fulfill(json({ connection: saved, check: { result: "invalid", error_code: "credentials_rejected", detail: {} } }));
      }
      saved = { ...MYDATA, status: "active", checked_at: "2026-10-29T12:33:00Z" };
      return route.fulfill(json({ connection: saved, check: { result: "ok", error_code: null, detail: {} } }));
    });
    await page.route("**/api/org/box1/admin/fiscal/connections/mydata/check", (route) =>
      route.fulfill(json({ connection: saved, check: { result: "ok", error_code: null, detail: {} } })),
    );

    await page.goto("/admin/settings/billing");
    const card = page.getByTestId("fiscal-connections");
    await expect(card.getByTestId("fiscal-connection-mydata-status")).toHaveText("Not connected");
    await expect(card.getByTestId("fiscal-connection-tse")).toHaveCount(0);

    await card.getByTestId("fiscal-connection-mydata").click();
    const panel = page.getByTestId("fiscal-connection-panel-mydata");
    await expect(panel.getByTestId("fiscal-connection-check")).toBeDisabled();
    // The environment waits under Advanced.
    await expect(panel.getByTestId("fiscal-connection-env-test")).toHaveCount(0);

    await panel.getByTestId("fiscal-connection-save").click();
    await expect(panel.getByTestId("fiscal-connection-user_id")).toHaveAttribute("aria-invalid", "true");

    await panel.getByTestId("fiscal-connection-user_id").fill("kypseli_box");
    await panel.getByTestId("fiscal-connection-subscription_key").fill("wrong-key");
    await panel.getByTestId("fiscal-connection-save").click();
    await expect(panel.getByText("AADE did not accept the key.", { exact: false })).toBeVisible();
    await expect(panel.getByTestId("fiscal-connection-subscription_key")).toHaveAttribute("aria-invalid", "true");

    await panel.getByTestId("fiscal-connection-subscription_key").fill("right-key");
    await panel.getByTestId("fiscal-connection-save").click();
    await expect(panel.getByTestId("fiscal-connection-saved")).toHaveText("Saved. Secrets are not shown again.");
    expect(saves.at(-1)).toEqual({ environment: "production", user_id: "kypseli_box", subscription_key: "right-key" });
    // The key is now only «Saved», with «Replace».
    await expect(panel.getByTestId("fiscal-connection-subscription_key")).toHaveAttribute("data-saved", "true");
    await expect(panel.getByTestId("fiscal-connection-subscription_key-replace")).toBeVisible();

    await panel.getByTestId("fiscal-connection-check").click();
    await expect(panel.getByTestId("fiscal-connection-check-result")).toHaveText("The connection works.");
    await panel.getByRole("button", { name: "Cancel" }).click();
    await expect(card.getByTestId("fiscal-connection-mydata-status")).toHaveText("Connected");
  });

  test("shows that the Palee team manages the connections (ADR-273)", async ({ page }) => {
    await signIn(page);
    await page.route("**/api/org/box1/admin/fiscal/countries", (route) => route.fulfill(json({ countries: [DE, GR], vat_schemes: ["standard", "small_business", "exempt"] })));
    await page.route("**/api/org/box1/admin/fiscal/identity", (route) => route.fulfill(json(greekIdentity)));
    await page.route("**/api/org/box1/admin/fiscal/connections", (route) =>
      route.fulfill(json(connections({ mydata: { ...MYDATA, updated_by_platform: true, updated_by_name: null } }, { managed_by: "palee" }))),
    );

    await page.goto("/admin/settings/billing?connection=mydata");
    await expect(page.getByTestId("fiscal-connections-managed")).toHaveText("The Palee team manages this connection");
    const panel = page.getByTestId("fiscal-connection-panel-mydata");
    await expect(panel.getByTestId("fiscal-connection-managed")).toBeVisible();
    await expect(panel.getByTestId("fiscal-connection-save")).toHaveCount(0);
    await expect(panel.getByTestId("fiscal-connection-check")).toBeEnabled();
  });
});

const today = localDay(0);
const yesterday = localDay(-1);
const base = {
  content_hash: "h",
  country_code: "GR",
  currency: "EUR",
  journal_position: 1,
  language: "el",
  net_cents: 0,
  prices_include_tax: true,
  seller: { legal_name: "KYPSELI ATHLETIC P.C.", tax_id: "801234567" },
  sequence: 1,
  series: "R",
  tax_breakdown: [],
  tax_cents: 0,
  buyer: null,
  payment_method: "card",
};
const tx = (id: string, status: string) => ({ id: `t-${id}`, document_id: id, authority: "mydata", attempts: 1, status, mark: status === "accepted" ? "400001234567890" : null });
const r418 = { ...base, id: "d1", number: "R-000418", kind: "receipt", gross_cents: 12400, issue_date: today, issued_at: `${today}T10:42:00`, transmission: tx("d1", "accepted") };
const r417 = { ...base, id: "d2", number: "R-000417", kind: "receipt", gross_cents: 1500, issue_date: today, issued_at: `${today}T09:05:00`, transmission: tx("d2", "pending") };
const i031 = { ...base, id: "d3", number: "I-000031", kind: "invoice", gross_cents: 45000, issue_date: yesterday, issued_at: `${yesterday}T18:20:00`, buyer: { name: "ACME S.A." }, transmission: tx("d3", "accepted") };
const lines = [
  { position: 1, description: "Package «12 visits»", quantity: 1, rate_bp: 2400, gross_cents: 9000, net_cents: 7258, tax_cents: 1742, amount_cents: 9000, discount_cents: 0, unit_price_cents: 9000, tax_category: "standard" },
  { position: 2, description: "Pull-up grips", quantity: 1, rate_bp: 2400, gross_cents: 3400, net_cents: 2742, tax_cents: 658, amount_cents: 3400, discount_cents: 0, unit_price_cents: 3400, tax_category: "standard" },
];

test.describe("Finance › Documents", () => {
  test("groups documents per day, opens one and issues a partial credit note", async ({ page }) => {
    await signIn(page);
    let credited: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/fiscal/documents?**", (route) => route.fulfill(json({ documents: [r418, r417, i031], total: 3 })));
    await page.route("**/api/org/box1/admin/fiscal/closings?**", (route) =>
      route.fulfill(
        json({
          closings: [
            { id: "c1", period_kind: "day", period_start: yesterday, period_end: yesterday, closed_at: `${today}T00:05:00Z`, journal_position: 9, totals: { EUR: { documents: 14, gross_cents: 61200, grand_total_cents: 4821000 } } },
          ],
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/fiscal/documents/d1", (route) =>
      route.fulfill(
        json({
          document: {
            ...r418,
            lines,
            tax_breakdown: [{ tax_category: "standard", rate_bp: 2400, net_cents: 10000, tax_cents: 2400, gross_cents: 12400 }],
            credit_notes: credited ? [{ ...r418, id: "c10", number: "C-000010", kind: "credit_note", gross_cents: 3400 }] : [],
          },
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/fiscal/documents/d1/credit-notes", (route) => {
      credited = bodyOf(route.request());
      return route.fulfill(json({ document: { ...r418, id: "c10", number: "C-000010", kind: "credit_note", gross_cents: 3400 } }, 201));
    });

    await page.goto("/admin/finance?tab=documents");
    const todayGroup = page.getByTestId(`fiscal-day-${today}`);
    await expect(todayGroup.getByTestId("fiscal-day-state")).toHaveText("Open");
    await expect(page.getByTestId(`fiscal-day-${yesterday}`).getByTestId("fiscal-day-state")).toHaveText("Closed");
    await expect(todayGroup.getByTestId("fiscal-doc-R-000417")).toContainText("Transmission pending");

    await page.getByTestId("fiscal-doc-R-000418").click();
    const panel = page.getByTestId("fiscal-document-panel");
    await expect(panel).toContainText("Pull-up grips");
    await expect(panel).toContainText("400001234567890");

    await panel.getByTestId("fiscal-doc-credit").click();
    const credit = page.getByTestId("fiscal-credit-panel");
    await credit.getByTestId("fiscal-credit-part").click();
    await credit.getByTestId("fiscal-credit-line-2").click();
    await expect(credit.getByTestId("fiscal-credit-amount")).toHaveText("-€34.00");
    await expect(credit.getByTestId("fiscal-credit-issue")).toBeDisabled();
    await credit.getByTestId("fiscal-credit-reason-product_return").click();
    await credit.getByTestId("fiscal-credit-issue").click();

    await expect.poll(() => credited?.lines).toEqual([{ position: 2, quantity: 1 }]);
    expect(credited).toMatchObject({ reason: "product_return" });
    expect(credited).not.toHaveProperty("refund");
    await expect(page.getByTestId("fiscal-document-panel").getByTestId("fiscal-doc-credit-note")).toContainText("C-000010");
  });

  test("refunds the card with the credit note and emails the PDF (ADR-265)", async ({ page }) => {
    await signIn(page);
    let credited: Record<string, unknown> | null = null;
    let emailed: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/fiscal/documents?**", (route) => route.fulfill(json({ documents: [r418], total: 1 })));
    await page.route("**/api/org/box1/admin/fiscal/closings?**", (route) => route.fulfill(json({ closings: [] })));
    const note = { ...r418, id: "c11", number: "C-000011", kind: "credit_note", gross_cents: 12400, credit_reason: "subscription_cancelled" };
    await page.route("**/api/org/box1/admin/fiscal/documents/d1", (route) =>
      route.fulfill(
        json({
          document: {
            ...r418,
            buyer: { name: "Maria P.", email: "maria@example.com" },
            lines,
            tax_breakdown: [{ tax_category: "standard", rate_bp: 2400, net_cents: 10000, tax_cents: 2400, gross_cents: 12400 }],
            credit_notes: credited ? [note] : [],
            refund_option: credited ? null : { provider: "viva", card_brand: "visa", card_last4: "4242", refundable_cents: 12400 },
          },
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/fiscal/documents/d1/credit-notes", (route) => {
      credited = bodyOf(route.request());
      return route.fulfill(json({ document: note, refund: { id: "rf1", status: "succeeded", amount_cents: 12400 } }, 201));
    });
    await page.route("**/api/org/box1/admin/fiscal/documents/d1/email", (route) => {
      emailed = bodyOf(route.request());
      return route.fulfill(json({ email: { id: "e1", status: "queued", to: "maria@example.com", recipient: "buyer" } }, 202));
    });

    await page.goto("/admin/finance?tab=documents");
    await page.getByTestId("fiscal-doc-R-000418").click();
    const panel = page.getByTestId("fiscal-document-panel");
    await panel.getByTestId("fiscal-doc-credit").click();

    const credit = page.getByTestId("fiscal-credit-panel");
    const refund = credit.getByRole("switch", { name: "Refund to the card ••4242" });
    await expect(refund).toHaveAttribute("aria-checked", "true");
    await expect(credit).toContainText("Through Viva, together with the credit note.");
    await credit.getByTestId("fiscal-credit-reason-subscription_cancelled").click();
    await credit.getByTestId("fiscal-credit-issue").click();

    await expect.poll(() => credited).toMatchObject({ reason: "subscription_cancelled", refund: true });
    const issued = page.getByTestId("fiscal-document-panel").getByTestId("fiscal-doc-credit-note");
    await expect(issued).toContainText("C-000011");
    await expect(issued).toContainText("Subscription cancelled");
    await expect(issued).toContainText("The money is going back to the card ••4242 (2–5 working days).");

    await page.getByTestId("fiscal-doc-email").click();
    const dialog = page.getByTestId("fiscal-email-dialog");
    await expect(dialog.getByTestId("fiscal-email-to")).toHaveValue("maria@example.com");
    await dialog.getByTestId("fiscal-email-send").click();
    await expect(page.getByTestId("fiscal-doc-email-sent")).toHaveText("Sent to maria@example.com.");
    expect(emailed).toMatchObject({ to: "maria@example.com" });
    expect(String(emailed?.["idempotency_key"] ?? "")).not.toBe("");
  });

  test("checks the audit archive and lists the export formats", async ({ page }) => {
    await signIn(page);
    await page.route("**/api/org/box1/admin/fiscal/documents?**", (route) => route.fulfill(json({ documents: [r418], total: 1 })));
    await page.route("**/api/org/box1/admin/fiscal/closings?**", (route) => route.fulfill(json({ closings: [] })));
    await page.route("**/api/org/box1/admin/fiscal/journal/verification", (route) => route.fulfill(json({ verification: { valid: true, entries: 1284 } })));
    let archive: string | null = null;
    await page.route("**/api/org/box1/admin/fiscal/archive?**", (route) => {
      archive = route.request().url();
      return route.fulfill({ status: 200, contentType: "application/zip", body: "PK" });
    });
    await page.route("**/api/org/box1/admin/fiscal/exports/formats", (route) =>
      route.fulfill(
        json({
          formats: [{ id: "datev", name: "DATEV", description: "DATEV EXTF bookings", file_extension: "csv", file_prefix: "EXTF", content_type: "text/csv", options: [] }],
          settings: [],
        }),
      ),
    );

    await page.goto("/admin/finance?tab=documents");
    await page.getByTestId("fiscal-audit-open").click();
    const audit = page.getByTestId("fiscal-audit-dialog");
    await audit.getByTestId("fiscal-audit-verify").click();
    await expect(audit.getByTestId("fiscal-audit-result")).toHaveText("OK");
    await audit.getByTestId("fiscal-audit-download").click();
    await expect(audit.getByTestId("fiscal-audit-started")).toContainText("palee-fiscal-");
    expect(archive).toContain("from=");
    await audit.getByRole("button", { name: "Close" }).click();

    await page.getByTestId("fiscal-export-open").click();
    await expect(page.getByTestId("fiscal-export-format-datev")).toHaveAttribute("aria-checked", "true");
  });
});
