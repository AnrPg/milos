import { expect, test, type Page } from "./support/test";

// Partner perks (ADR-191): the «From the box's partners» group under
// Me › Payments › Offers, the perk page (claim → code, copy, themed QR),
// the public verification page a store opens from a Palee QR, and the
// console list + form under Finance › Offers › Partners.
// The API is stubbed; anything not stubbed answers `{}`.
// Not run yet: the owner asked to skip Playwright until the perks API branch
// is merged. Stubs follow PaleeWeb.Schemas.Perks.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function persona(role: "member" | "admin") {
  const id = `${role}-1`;
  const user = {
    id,
    nickname: role === "admin" ? "Nikos" : "Maria",
    role,
    email: `${id}@example.com`,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = (role: "member" | "admin", activation = "active") => ({
  id: "m-kypseli",
  role,
  roles: [role],
  capabilities: {},
  organization: { id: "org-kypseli", slug: "kypseli", name: "Box Kypseli", provider_kind: "gym", activation },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
});

const provider = { organization_id: "org-kypseli", name: "Box Kypseli", slug: "kypseli", kind: "gym", logo_url: null };

const common = {
  id: "perk-1",
  organization_id: "org-kypseli",
  partner_name: "Nutri Shop",
  partner_url: "https://nutri.example",
  partner_address: null,
  logo_media_id: null,
  logo_url: null,
  redemption_method: "code_pool",
  version: 1,
  benefit: { type: "percent", percent: 15, text: "all supplements" },
  benefit_label: "15%",
  rules: { limits: { max_per_member: 1 } },
  terms: "One use per member.",
  instructions: null,
  valid_from: null,
  valid_until: null,
  status: "published",
};

const claim = {
  id: "claim-1",
  perk_id: "perk-1",
  perk_version: 1,
  organization_id: "org-kypseli",
  provider,
  partner_name: "Nutri Shop",
  benefit_label: "15%",
  redemption_method: "code_pool",
  terms: "One use per member.",
  instructions: null,
  valid_until: null,
  partner_url: "https://nutri.example",
  code: "NUTRI-7Q2K",
  reference: "PK-1",
  url: null,
  show_membership: false,
  status: "claimed",
  usable: true,
  claimed_at: new Date().toISOString(),
  used_at: null,
  verification: null,
};

async function signIn(page: Page, role: "member" | "admin", activation = "active") {
  const me = persona(role);
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: me.token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(me.user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership(role, activation)])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

test.describe("partner perks · member", () => {
  test("Offers lists the perk and its page hands out the code with copy and QR", async ({ page }) => {
    await signIn(page, "member");
    let claimed = false;
    await page.route("**/api/me/perks", (route) =>
      route.fulfill(json({ perks: [{ ...common, provider, claimable: !claimed, unavailable_reason: null, claim: claimed ? claim : null }] })),
    );
    await page.route("**/api/me/perks/perk-1/claim", (route) => {
      claimed = true;
      return route.fulfill(json({ claim, created: true }, 201));
    });
    await page.goto("/me/payments/perks/perk-1");
    await page.getByTestId("perk-claim").click();
    await expect(page.getByTestId("perk-code")).toContainText("NUTRI-7Q2K");
    await expect(page.getByRole("button", { name: "Copy" })).toBeVisible();
    await page.getByRole("button", { name: "Show QR" }).click();
    await expect(page.getByTestId("perk-code-qr")).toBeVisible();
  });
});

test.describe("partner perks · public verification", () => {
  test("a store sees the perk is valid and marks it used without logging in", async ({ page }) => {
    await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    let used = false;
    const check = () => ({
      status: used ? "used" : "valid",
      code: "Q-7781",
      member_first_name: "Maria",
      claimed_at: new Date().toISOString(),
      used_at: used ? new Date().toISOString() : null,
      perk: { partner_name: "Nutri Shop", benefit_label: "15%", terms: null, valid_until: null },
      business: { name: "Box Kypseli", logo_url: null },
    });
    await page.route("**/api/public/perk-verifications/tok-1", (route) => route.fulfill(json(check())));
    await page.route("**/api/public/perk-verifications/tok-1/redeem", (route) => {
      used = true;
      return route.fulfill(json(check()));
    });
    await page.goto("/perks/verify/tok-1");
    await expect(page.getByTestId("perk-check-status")).toContainText("Valid");
    await page.getByTestId("perk-check-redeem").click();
    await expect(page.getByTestId("perk-check-status")).toContainText("Already used");
  });
});

test.describe("partner perks · console", () => {
  const staff = {
    ...common,
    redemption: { low_pool_threshold: null },
    all_locations: true,
    location_ids: [],
    claims_count: 12,
    uses_count: 7,
    remaining: null,
    codes: { total: 50, free: 38, low: false },
    published_at: new Date().toISOString(),
  };

  test("the partner segment lists perks with claim and use counts", async ({ page }) => {
    await signIn(page, "admin");
    await page.route("**/api/org/kypseli/admin/perks", (route) => route.fulfill(json({ perks: [staff] })));
    await page.goto("/admin/finance?tab=promotions&offers=partners");
    const row = page.getByTestId("perk-row");
    await expect(row).toContainText("12 claimed");
    await expect(row).toContainText("12/50");
  });

  test("a demo business can draft a perk but not publish it", async ({ page }) => {
    await signIn(page, "admin", "demo");
    await page.route("**/api/org/kypseli/admin/perks", (route) => route.fulfill(json({ perks: [] })));
    await page.goto("/admin/finance?tab=promotions&offers=partners");
    await page.getByTestId("perk-new").click();
    await page.getByTestId("perk-method-code_pool").click();
    await page.getByTestId("perk-codes-input").fill("A1\nA2\nA1");
    await expect(page.getByText("2 codes ready")).toBeVisible();
    await expect(page.getByTestId("perk-publish")).toBeDisabled();
    await expect(page.getByText("More conditions")).toBeVisible();
  });
});
