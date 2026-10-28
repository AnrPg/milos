import { expect, test, type Page, type Request } from "./support/test";

// ADR-209: a box sends client and staff invitations by email, follows their
// delivery, resends them and invites several people at once; the emailed
// link opens /invite. The API is stubbed.

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  completed_tours: ["admin", "gym"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

const organization = { id: "org-1", slug: "kypseli", name: "Box Kypseli" };
const TOKEN = "t".repeat(43);

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const pending = [
  { id: "inv-1", role: "member", roles: ["member"], location_scope: { all_locations: true, location_ids: [] }, expires_at: "2026-11-03T10:00:00Z", issued_at: "2026-10-27T10:00:00Z", email_bound: true, email: "nikos@example.com", email_locale: "el", delivery_status: "bounced" },
  { id: "inv-2", role: "coach", roles: ["coach"], location_scope: { all_locations: true, location_ids: [] }, expires_at: "2026-11-03T10:00:00Z", issued_at: "2026-10-27T10:00:00Z", email_bound: true, email: "eleni@example.com", email_locale: "en", delivery_status: "sent" },
  { id: "inv-3", role: "member", roles: ["member"], location_scope: { all_locations: true, location_ids: [] }, expires_at: "2026-11-03T10:00:00Z", issued_at: "2026-10-27T10:00:00Z", email_bound: false, email: null, email_locale: null, delivery_status: null },
];

async function stubAdmin(page: Page, { activation = "active" }: { activation?: string } = {}) {
  const requests: Request[] = [];
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(owner), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(owner)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          id: "m-1",
          role: "owner",
          roles: ["owner"],
          coach_scope: "all",
          capabilities: { invite_clients: "all", manage_settings: "all" },
          location_scope: { all_locations: true, location_ids: [] },
          organization: { ...organization, provider_kind: "gym", activation },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null, default_locale: "el" },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/onboarding", (route) =>
    route.fulfill(json({ audience: "gym", steps: [], completed_count: 0, total: 0, finished: true, dismissed: true, tour_completed: true })),
  );
  await page.route("**/api/org/*/admin/locations**", (route) => route.fulfill(json([])));
  await page.route("**/api/org/kypseli/invitations", (route) => {
    if (route.request().method() === "GET") return route.fulfill(json(pending));
    requests.push(route.request());
    const body = route.request().postDataJSON();
    return route.fulfill(
      json(
        {
          organization,
          role: body.roles?.[0] ?? body.role,
          roles: body.roles ?? [body.role],
          location_scope: { all_locations: true, location_ids: [] },
          expires_at: "2026-11-03T10:00:00Z",
          id: "inv-new",
          email: body.intended_email,
          delivery_status: "queued",
        },
        201,
      ),
    );
  });
  await page.route("**/api/org/kypseli/invitations/bulk", (route) => {
    requests.push(route.request());
    return route.fulfill(
      json(
        {
          results: [
            { email: "a@example.com", status: "queued", invitation_id: "i-a" },
            { email: "b@example.com", error: "suppressed" },
          ],
          sent: 1,
          failed: 1,
          skipped: ["nope"],
        },
        201,
      ),
    );
  });
  await page.route("**/api/org/kypseli/invitations/inv-1/resend", (route) => {
    requests.push(route.request());
    return route.fulfill(json({ ...pending[0], id: "inv-4", delivery_status: "queued" }, 201));
  });
  return requests;
}

async function openInviteDialog(page: Page) {
  await page.goto("/org/kypseli/admin");
  await page.getByRole("button", { name: "Invite clients" }).first().click();
  const dialog = page.getByRole("dialog", { name: "Invite clients" });
  await expect(dialog).toBeVisible();
  return dialog;
}

test.describe("invitations sent by email", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
  });

  test("a client invitation goes by email in the box's language", async ({ page }) => {
    const requests = await stubAdmin(page);
    const dialog = await openInviteDialog(page);

    await expect(dialog.getByRole("button", { name: "Create invite link" })).toBeVisible();
    await dialog.getByLabel(/Email \(optional\)/).fill("maria@example.com");
    await expect(dialog.getByRole("combobox", { name: /Email language/ })).toContainText("Ελληνικά (your box’s language)");
    await dialog.getByRole("button", { name: "Send invitation" }).click();

    await expect(dialog.getByText("Invitation sent to maria@example.com.")).toBeVisible();
    await expect(dialog.getByRole("button", { name: "Copy" })).toHaveCount(0);
    expect(requests[0].postDataJSON()).toMatchObject({ role: "member", intended_email: "maria@example.com", send_email: true, email_locale: "el" });
  });

  test("a staff invitation goes by email with its roles and a chosen language", async ({ page }) => {
    const requests = await stubAdmin(page);
    const dialog = await openInviteDialog(page);

    await dialog.getByRole("radio", { name: "Staff" }).click();
    await dialog.getByRole("button", { name: "Coach", exact: true }).click();
    await dialog.getByLabel(/Email \(optional\)/).fill("eleni@example.com");
    await dialog.getByRole("combobox", { name: /Email language/ }).click();
    await page.getByRole("option", { name: "English" }).click();
    await dialog.getByRole("button", { name: "Send invitation" }).click();

    await expect(dialog.getByText("Invitation sent to eleni@example.com.")).toBeVisible();
    expect(requests[0].postDataJSON()).toMatchObject({ roles: ["coach"], intended_email: "eleni@example.com", send_email: true, email_locale: "en" });
  });

  test("pending invitations show delivery and resend the emailed ones", async ({ page }) => {
    const requests = await stubAdmin(page);
    const dialog = await openInviteDialog(page);

    await dialog.getByRole("tab", { name: /Pending/ }).click();
    await expect(dialog.getByText("nikos@example.com")).toBeVisible();
    await expect(dialog.getByText("Bounced")).toBeVisible();
    await expect(dialog.getByText("Sent", { exact: true })).toBeVisible();
    await expect(dialog.getByRole("button", { name: "Resend" })).toHaveCount(2);

    await dialog.getByRole("button", { name: "Resend" }).first().click();
    await expect(dialog.getByText("Sent again to nikos@example.com. The previous link no longer works.")).toBeVisible();
    expect(requests.some((request) => request.url().endsWith("/invitations/inv-1/resend"))).toBe(true);
  });

  test("several people at once, each with their own invitation", async ({ page }) => {
    const requests = await stubAdmin(page);
    const dialog = await openInviteDialog(page);

    await dialog.getByRole("tab", { name: "Several people" }).click();
    await dialog.getByLabel(/^Email addresses/).fill("a@example.com, B@example.com\nnope");
    await expect(dialog.getByText("2 addresses")).toBeVisible();
    await dialog.getByRole("button", { name: "Send 2 invitations" }).click();

    await expect(dialog.getByText("1 invitation sent.")).toBeVisible();
    await expect(dialog.getByText(/b@example.com: Emails to this address bounce/)).toBeVisible();
    expect(requests[0].postDataJSON()).toMatchObject({ emails: ["a@example.com", "b@example.com"], role: "member" });
  });

  test("a box in demo mode is told why it cannot invite", async ({ page }) => {
    await stubAdmin(page, { activation: "demo" });
    const dialog = await openInviteDialog(page);

    await expect(dialog.getByRole("note")).toContainText("demo mode");
    await expect(dialog.getByRole("button", { name: "Send invitation" })).toHaveCount(0);
  });
});

test.describe("the emailed invitation link", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
  });

  const inspection = {
    organization,
    role: "member",
    roles: ["member"],
    location_scope: { all_locations: true, location_ids: [] },
    expires_at: "2026-11-03T10:00:00Z",
    email_bound: true,
  };

  test("signed out: the token stays out of the URL and sign-up carries it", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "invalid_refresh_token" }, 401)));
    await page.route("**/api/auth/invitations/inspect", (route) => route.fulfill(json(inspection)));

    await page.goto(`/invite#token=${TOKEN}`);
    await expect(page.getByRole("heading", { name: "Join Box Kypseli" })).toBeVisible();
    await expect(page.getByText(/This invitation is for one email address/)).toBeVisible();
    expect(new URL(page.url()).hash).toBe("");
    await expect(page.getByRole("link", { name: "Create an account" })).toHaveAttribute("href", `/register#token=${TOKEN}`);
    await expect(page.getByRole("link", { name: "I already have an account" })).toHaveAttribute("href", "/login?next=%2Finvite");
  });

  test("a revoked invitation says so", async ({ page }) => {
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "invalid_refresh_token" }, 401)));
    await page.route("**/api/auth/invitations/inspect", (route) =>
      route.fulfill(json({ code: "invitation_revoked", error: "The box revoked this invitation" }, 410)),
    );

    await page.goto(`/invite#token=${TOKEN}`);
    await expect(page.getByRole("heading", { name: "This invitation was revoked" })).toBeVisible();
  });

  test("signed in with another address: a clear message without the invited one", async ({ page }) => {
    const member = { ...owner, id: "member-1", role: "member", email: "someone@example.com", memberships: [] };
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(member), refresh_token: "refresh" })));
    await page.route("**/api/auth/me", (route) => route.fulfill(json(member)));
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));
    await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
    await page.route("**/api/auth/invitations/inspect", (route) => route.fulfill(json(inspection)));
    await page.route("**/api/memberships/redeem", (route) =>
      route.fulfill(json({ code: "invitation_email_mismatch", error: "This invitation was issued to a different email address" }, 403)),
    );

    await page.goto(`/invite#token=${TOKEN}`);
    await page.getByRole("button", { name: "Join Box Kypseli" }).click();
    await expect(page.getByText(/signed in with a different email address/)).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign out" })).toBeVisible();
  });
});
