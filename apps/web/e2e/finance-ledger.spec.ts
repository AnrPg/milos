import { expect, test, type Page } from "./support/test";

import { chooseOption } from "./support/select";

// Finance › Ledger (the members tab). Staff assign a πακέτο συνδρομής from a
// member's row: the package list opens in its own layer, and picking from it
// must not close the «Assign» menu before the choice lands. Staff also record
// money a member handed over (ADR-222) and get the document the box's billing
// setup calls for. The API is stubbed; anything not stubbed answers `{}`.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const MEMBER_ID = "a11ce000-0000-4000-8000-000000000001";
const PACKAGE_ID = "9ac4a9e0-0000-4000-8000-000000000001";

function owner() {
  const user = {
    id: "owner-1",
    nickname: "Apostolos",
    role: "admin",
    email: "owner-1@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

type Reply = { status: number; body: unknown };

async function ledger(
  page: Page,
  assign: (body: unknown) => Reply,
  money: {
    documentMode?: "invoice" | "receipt";
    profile?: Record<string, unknown>;
    receive?: (body: Record<string, unknown>) => Reply;
    /** ADR-274: fields of the ledger row (status, period, values set by hand). */
    row?: Record<string, unknown>;
  } = {},
) {
  const persona = owner();
  const assigned: unknown[] = [];
  let member: Record<string, unknown> = {
    id: MEMBER_ID,
    nickname: "Maria",
    identity_role: "member",
    user_type: "member",
    membership: { status: "active" },
    active_package_subscription: null,
    ...money.row,
  };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: persona.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(persona.user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: {
            take_payments: "all",
            manage_billing: "all",
            manage_memberships: "all",
            manage_packages: "all",
            view_package_catalog: "all",
          },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/kypseli/admin/finance/package-catalog", (route) => route.fulfill(json({ types: [], modules: [] })));
  await page.route("**/api/org/kypseli/admin/finance/packages**", (route) =>
    route.fulfill(json({ packages: [{ id: PACKAGE_ID, name: "Unlimited monthly", code: "unlimited", active: true }] })),
  );
  await page.route("**/api/org/kypseli/admin/finance/members?**", (route) => route.fulfill(json({ members: [member], meta: {} })));
  await page.route("**/api/org/kypseli/admin/finance/members", (route) => route.fulfill(json({ members: [member], meta: {} })));
  await page.route(`**/api/org/kypseli/admin/finance/members/${MEMBER_ID}/packages`, (route) => {
    const body = route.request().postDataJSON();
    assigned.push(body);
    const reply = assign(body);
    if (reply.status < 300) {
      member = {
        ...member,
        active_package_subscription: { id: "sub-1", status: "active", membership_package_id: PACKAGE_ID, package_name: "Unlimited monthly" },
      };
    }
    return route.fulfill(json(reply.body, reply.status));
  });
  await page.route("**/api/org/kypseli/admin/settings", (route) =>
    route.fulfill(json({ finance: { document_mode: money.documentMode ?? "invoice", payment_reminder_interval_days: 7 } })),
  );
  await page.route(`**/api/org/kypseli/admin/finance/members/${MEMBER_ID}`, (route) =>
    route.fulfill(
      json({
        membership: { status: "active" },
        package_subscriptions: [],
        invoices: [],
        payments: [],
        payment_reversals: [],
        credit_ledger_entries: [],
        ...money.profile,
      }),
    ),
  );
  await page.route(`**/api/org/kypseli/admin/finance/members/${MEMBER_ID}/payments/receive`, (route) => {
    const reply = money.receive?.(route.request().postDataJSON()) ?? { status: 500, body: {} };
    return route.fulfill(json(reply.body, reply.status));
  });
  await page.goto("/org/kypseli/admin/finance?tab=members");
  return assigned;
}

const SUBSCRIPTION = { id: "sub-1", status: "active", package_name: "Unlimited monthly", price_cents_snapshot: 6000 };

function received(overrides: Record<string, unknown>) {
  return {
    document_type: "receipt",
    reference: "R-0007",
    issued_on: "2026-10-28",
    amount_cents: 6000,
    currency: "EUR",
    description: "Unlimited monthly",
    package_name: "Unlimited monthly",
    replayed: false,
    invoice: { id: "inv-r7", status: "paid", balance_due_cents: 0 },
    payment: { id: "pay-1", payment_method: "card_manual" },
    ...overrides,
  };
}

test.describe("finance ledger", () => {
  test("staff assign a subscription package from a member's row", async ({ page }) => {
    const assigned = await ledger(page, () => ({ status: 201, body: { package_subscription: { id: "sub-1" } } }));

    await page.getByRole("button", { name: "+ Assign" }).click();
    const menu = page.getByRole("dialog", { name: "Assign" });
    await chooseOption(page, menu.getByRole("combobox"), PACKAGE_ID);
    // The menu is still open after the pick, with the package chosen.
    await expect(menu).toBeVisible();
    await menu.getByRole("button", { name: "Assign", exact: true }).click();

    await expect.poll(() => assigned).toEqual([{ membership_package_id: PACKAGE_ID }]);
    await expect(menu).toBeHidden();
    await expect(page.getByRole("button", { name: /Unlimited monthly/ })).toBeVisible();
  });

  test("a refused assignment stays in the menu with the reason", async ({ page }) => {
    await ledger(page, () => ({
      status: 422,
      body: { error: { code: "package_not_eligible", message: "This package cannot be combined with the member's current one." } },
    }));

    await page.getByRole("button", { name: "+ Assign" }).click();
    const menu = page.getByRole("dialog", { name: "Assign" });
    await chooseOption(page, menu.getByRole("combobox"), PACKAGE_ID);
    await menu.getByRole("button", { name: "Assign", exact: true }).click();

    await expect(menu).toBeVisible();
    await expect(menu.getByRole("alert")).toBeVisible();
  });

  test("staff record a card payment for a package and a receipt-mode box issues the receipt", async ({ page }) => {
    const sent: Record<string, unknown>[] = [];
    await ledger(page, () => ({ status: 201, body: {} }), {
      documentMode: "receipt",
      profile: { package_subscriptions: [SUBSCRIPTION] },
      receive: (body) => {
        sent.push(body);
        return { status: 201, body: { received: received({}) } };
      },
    });

    await page.getByRole("button", { name: "Record a payment from Maria" }).click();
    const dialog = page.getByRole("dialog", { name: "Record payment" });
    await expect(dialog.getByRole("combobox", { name: "For" })).toHaveText(/Unlimited monthly/);
    await expect(dialog.getByRole("textbox", { name: "Amount received (€)" })).toHaveValue("60.00");
    await expect(dialog.getByTestId("receive-payment-outcome")).toHaveText("A paid receipt is issued, as your billing settings say.");
    await dialog.getByRole("radio", { name: "Card" }).click();
    await dialog.getByRole("button", { name: "Record payment" }).click();

    const done = page.getByRole("dialog", { name: /recorded/ });
    await expect(done).toContainText("Receipt R-0007");
    await expect(done).toContainText("Fully paid");
    await expect(done.getByRole("button", { name: "Download receipt (PDF)" })).toBeVisible();
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ amount_cents: 6000, payment_method: "card_manual", membership_package_subscription_id: "sub-1" });
    expect(typeof sent[0].idempotency_key).toBe("string");
    await done.getByRole("button", { name: "Done" }).click();
    await expect(page).not.toHaveURL(/receive=/);
  });

  test("a partial payment goes against the open invoice and the amount is checked in the form", async ({ page }) => {
    const sent: Record<string, unknown>[] = [];
    await ledger(page, () => ({ status: 201, body: {} }), {
      documentMode: "invoice",
      profile: {
        package_subscriptions: [SUBSCRIPTION],
        invoices: [{ id: "inv-7", invoice_number: "INV-7", status: "issued", balance_due_cents: 6000, due_date: "2026-10-20" }],
      },
      receive: (body) => {
        sent.push(body);
        return {
          status: 201,
          body: {
            received: received({
              document_type: "invoice",
              reference: "INV-7",
              amount_cents: 2000,
              invoice: { id: "inv-7", status: "partially_paid", balance_due_cents: 4000 },
              payment: { id: "pay-2", payment_method: "bank_transfer" },
            }),
          },
        };
      },
    });

    await page.getByRole("button", { name: "Record a payment from Maria" }).click();
    const dialog = page.getByRole("dialog", { name: "Record payment" });
    await expect(dialog.getByTestId("receive-payment-outcome")).toHaveText("The payment goes against invoice INV-7.");
    const amount = dialog.getByRole("textbox", { name: "Amount received (€)" });
    await expect(amount).toHaveValue("60.00");

    await amount.fill("75");
    await dialog.getByRole("button", { name: "Record payment" }).click();
    await expect(amount).toHaveAttribute("aria-invalid", "true");
    await expect(dialog.getByText("That is more than this invoice still owes.", { exact: false })).toBeVisible();
    expect(sent).toHaveLength(0);

    await amount.fill("20,00");
    await dialog.getByRole("radio", { name: "Bank transfer" }).click();
    await dialog.getByRole("button", { name: "Record payment" }).click();

    const done = page.getByRole("dialog", { name: /recorded/ });
    await expect(done).toContainText("Invoice INV-7");
    await expect(done).toContainText("still due");
    await expect(done.getByRole("button", { name: "Attach invoice file" })).toBeVisible();
    expect(sent[0]).toMatchObject({ amount_cents: 2000, payment_method: "bank_transfer", finance_invoice_id: "inv-7" });
  });

  test("a refusal from the server shows inside the form, under its field", async ({ page }) => {
    await ledger(page, () => ({ status: 201, body: {} }), {
      profile: { invoices: [{ id: "inv-7", invoice_number: "INV-7", status: "issued", balance_due_cents: 6000 }] },
      receive: () => ({ status: 409, body: { code: "invoice_already_paid", error: "Invoice already paid" } }),
    });

    await page.getByRole("button", { name: "Record a payment from Maria" }).click();
    const dialog = page.getByRole("dialog", { name: "Record payment" });
    await dialog.getByRole("button", { name: "Record payment" }).click();
    await expect(dialog.getByText("This invoice is already fully paid.")).toBeVisible();
    await expect(dialog.getByRole("combobox", { name: "For" })).toHaveAttribute("aria-invalid", "true");
  });

  test("the status follows payments, and a value set by hand shows who changed it (ADR-274)", async ({ page }) => {
    const calls: Array<{ method: string; url: string; body: unknown }> = [];
    await ledger(page, () => ({ status: 201, body: {} }), {
      row: {
        membership: { status: "active", status_shown: "unpaid" },
        active_package_subscription: {
          id: "sub-1",
          status: "active",
          package_name: "Unlimited monthly",
          membership_package_id: PACKAGE_ID,
          current_period: { starts_on: "2026-10-29", ends_on: "2026-11-28", renews: true },
        },
        outstanding_balance_cents: 4500,
        oldest_unpaid_due_on: "2026-10-29",
        last_payment_on: "2026-10-29",
        last_payment_amount_cents: 500,
        overrides: [
          {
            id: "ov-1",
            field: "ends_on",
            subject_id: "sub-1",
            computed_value: "2026-11-28",
            value: "2026-12-15",
            reason: "Injury",
            set_by_name: "Apostolos",
            set_at: "2026-10-29T21:50:00Z",
          },
        ],
      },
    });

    // Registered after the catch-all stubs, so these win.
    await page.route(`**/api/org/kypseli/admin/finance/members/${MEMBER_ID}/overrides/**`, (route) => {
      const request = route.request();
      calls.push({ method: request.method(), url: request.url(), body: request.postDataJSON() });
      return route.fulfill(json({ override: { id: "ov-2", field: "status", value: "active", set_at: "2026-10-29T21:41:00Z" } }));
    });

    const row = page.getByRole("row", { name: /Maria/ });
    await expect(row.locator("[data-member-status]")).toHaveText("Unpaid");
    await expect(row).toContainText("€5.00");
    await expect(row).toContainText("since 2026-10-29");

    // The end date set by hand: a dot in its corner, and on hover who, when, from and to.
    const dot = row.getByRole("button", { name: "Changed by hand" });
    await expect(dot).toBeVisible();
    await dot.hover();
    const card = page.getByRole("dialog", { name: "Changed by hand" });
    await expect(card).toContainText("Apostolos");
    await expect(card).toContainText("Injury");
    await card.getByRole("button", { name: "Back to automatic" }).click();
    await expect.poll(() => calls.map((call) => call.method)).toEqual(["DELETE"]);
    expect(calls[0].url).toContain("/overrides/ends_on?subscription_id=sub-1");

    // Setting the status by hand asks for an optional reason and records it.
    await row.getByRole("button", { name: "Set status" }).click();
    const editor = page.getByRole("dialog", { name: "Set status" });
    await expect(editor).toContainText("Automatic: Unpaid");
    await chooseOption(page, editor.getByRole("combobox", { name: "Set status" }), "active");
    await editor.getByRole("textbox", { name: "Reason (optional)" }).fill("Pays on Friday");
    await editor.getByRole("button", { name: "Save" }).click();
    await expect.poll(() => calls.length).toBe(2);
    expect(calls[1]).toMatchObject({ method: "PUT", body: { value: "active", reason: "Pays on Friday" } });
    await expect(editor).toBeHidden();
  });

  test("«Debts» lists who owes, oldest first, with a payment button (ADR-274)", async ({ page }) => {
    await ledger(page, () => ({ status: 201, body: {} }));
    await page.route("**/api/org/kypseli/admin/finance/queues**", (route) =>
      route.fulfill(
        json({
          queues: {
            open_charges: [
              { id: "m-2", user_id: "u-2", user_label: "nikos", balance_due_cents: 5000, oldest_due_on: "2026-10-05", state: "overdue" },
              { id: "m-1", user_id: MEMBER_ID, user_label: "Maria", balance_due_cents: 4500, oldest_due_on: "2026-10-29", state: "unpaid" },
            ],
          },
        }),
      ),
    );
    await page.goto("/org/kypseli/admin/finance?tab=queues");

    const debts = page.getByRole("button", { name: /Debts/ });
    await expect(debts).toBeVisible();
    await expect(page.locator("[data-debt-state]")).toHaveText(["Overdue", "Unpaid"]);
    await expect(page.getByText("€45.00")).toBeVisible();
    await page.getByRole("button", { name: "+ Payment" }).nth(1).click();
    await expect(page.getByRole("dialog", { name: "Record payment" })).toBeVisible();
  });
});
