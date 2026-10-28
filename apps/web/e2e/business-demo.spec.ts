import { chooseOption } from "./support/select";
import { expect, test, type Page } from "./support/test";

// ADR-184: business accounts in demo mode. The quiet «Business account» link
// on the register form, the business sign-up, the floating demo button on the
// admin screens of a demo business (fill this screen, fill everything, remove,
// ask for activation), the «Activation by the Palee team» notice on a
// `business_not_activated` refusal, the activation link, and the vendors'
// queue. The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const NOW = "2026-10-23T09:00:00Z";

type Persona = { id: string; nickname: string; role: string; vendor?: boolean };

const OWNER: Persona = { id: "owner-1", nickname: "Apostolos", role: "admin" };
const VENDOR: Persona = { id: "vendor-1", nickname: "Palee", role: "admin", vendor: true };

function userFor(persona: Persona, memberships: { organization_slug: string; role: string }[] = []) {
  return {
    id: persona.id,
    nickname: persona.nickname,
    role: persona.role,
    email: `${persona.id}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: persona.vendor ?? false,
    memberships: memberships.map((membership) => ({ ...membership, settings: {} })),
  };
}

function tokenFor(persona: Persona, slugs: string[] = []) {
  const payload = Buffer.from(
    JSON.stringify({
      sub: persona.id,
      role: persona.role,
      memberships: slugs.map((organization_slug) => ({ organization_slug })),
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

/** An owner's membership of Box Kypseli; `activation` is left out when undefined. */
function ownerMembership(activation?: "demo" | "active") {
  return {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_settings: "all", manage_members: "all" },
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", ...(activation ? { activation } : {}) },
    settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
  };
}

const organization = (extra: Record<string, unknown> = {}) => ({
  id: "org-1",
  slug: "kypseli",
  name: "Box Kypseli",
  provider_kind: "gym",
  activation: "demo",
  demo_started_at: "2026-10-20T09:00:00Z",
  activated_at: null,
  ...extra,
});

const businessRequest = (extra: Record<string, unknown> = {}) => ({
  id: "req-1",
  kind: "activation",
  status: "pending",
  business_kind: "gym",
  business_name: "Box Kypseli",
  city: "Athens",
  phone: "+30 210 000 0000",
  message: null,
  organization_id: "org-1",
  requested_by: "Apostolos",
  requester_email_verified: true,
  inserted_at: NOW,
  decided_at: null,
  decision_note: null,
  ...extra,
});

const activationLink = (extra: Record<string, unknown> = {}) => ({
  id: "link-1",
  organization_id: "org-1",
  user_id: "owner-1",
  nickname: "Apostolos",
  role: "owner",
  state: "live",
  token: "act-token",
  path: "/activate-business#token=act-token",
  expires_at: "2026-10-30T09:00:00Z",
  inserted_at: NOW,
  email_delivery: { status: "queued", error: null, sent_at: null },
  ...extra,
});

/** Signed in as `persona`, with `memberships` as the memberships payload. */
async function signedIn(page: Page, persona: Persona, memberships: ReturnType<typeof ownerMembership>[] = []) {
  const slugs = memberships.map((membership) => membership.organization.slug);
  const user = userFor(persona, memberships.map((membership) => ({ organization_slug: membership.organization.slug, role: membership.role })));
  const token = tokenFor(persona, slugs);
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh", user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(memberships)));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

type DemoCalls = { status: number; seeds: unknown[]; removes: number; activationRequests: unknown[] };

/** The demo business's status and demo-data endpoints, with the server's state kept here. */
async function demoBusiness(page: Page) {
  const calls: DemoCalls = { status: 0, seeds: [], removes: 0, activationRequests: [] };
  const sections = ["members", "schedule", "finance", "workouts"];
  const seeded = new Set<string>();
  let request: ReturnType<typeof businessRequest> | null = null;
  const status = () => ({
    activation: "demo",
    gated: true,
    activation_request: request,
    sections: sections.map((section) => ({ section, seeded: seeded.has(section), rows: seeded.has(section) ? 6 : 0 })),
  });

  await page.route("**/api/org/kypseli/admin/business", (route) => {
    calls.status += 1;
    return route.fulfill(json(status()));
  });
  await page.route("**/api/org/kypseli/admin/business/demo-data", (route) => {
    if (route.request().method() === "DELETE") {
      calls.removes += 1;
      seeded.clear();
      return route.fulfill(json(status()));
    }
    const body = route.request().postDataJSON() as { section: string };
    calls.seeds.push(body);
    // As on the server: a section brings what it requires; "all" seeds everything.
    const plan = body.section === "all" ? sections : body.section === "schedule" ? ["members", "workouts", "schedule"] : [body.section];
    plan.forEach((section) => seeded.add(section));
    return route.fulfill(json(status()));
  });
  await page.route("**/api/org/kypseli/admin/business/activation-request", (route) => {
    calls.activationRequests.push(route.request().postDataJSON());
    request = businessRequest();
    return route.fulfill(json(request, 201));
  });
  return calls;
}

test.describe("business sign-up", () => {
  test("the register form's quiet link opens the business sign-up, which opens a demo business", async ({ page }) => {
    const sent: { registered: unknown[]; businesses: unknown[] } = { registered: [], businesses: [] };
    const persona: Persona = { id: "new-1", nickname: "maria_coach", role: "member" };
    const user = userFor(persona);
    await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => route.fulfill(json({})));
    await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
    await page.route("**/api/auth/register", (route) => {
      sent.registered.push(route.request().postDataJSON());
      // ADR-211: a new account's answer also says where the link went.
      return route.fulfill(
        json({ access_token: tokenFor(persona), confirmation: "email_sent", email: "maria@example.com" }, 201),
      );
    });
    await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
    await page.route("**/api/memberships", (route) => route.fulfill(json([])));
    await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
    await page.route("**/api/business-accounts", (route) => {
      sent.businesses.push(route.request().postDataJSON());
      return route.fulfill(json(organization({ slug: "maria-coaching", name: "Maria Coaching", provider_kind: "coach" }), 201));
    });

    await page.goto("/register");
    const quietLink = page.getByRole("link", { name: "Business account" });
    await expect(quietLink).toHaveAttribute("href", "/register/business");
    await quietLink.click();
    await expect(page).toHaveURL(/\/register\/business$/);

    await page.getByRole("radiogroup", { name: "Kind of business" }).getByRole("radio", { name: /Independent coach/ }).click();
    await page.getByLabel("Your name as a coach", { exact: true }).fill("Maria Coaching");
    await page.getByLabel("City", { exact: true }).fill("Thessaloniki");
    await page.getByLabel("Phone", { exact: true }).fill("+30 690 000 0000");
    await page.getByLabel("Your name", { exact: true }).fill("Maria");
    await page.getByLabel("Handle", { exact: true }).fill("maria_coach");
    await page.getByLabel("Email address", { exact: true }).fill("maria@example.com");
    await page.getByLabel("Password", { exact: true }).fill("secret-pass");
    await page.getByRole("button", { name: "Open my business" }).click();

    await expect(page.getByRole("heading", { name: "Your account is ready" })).toBeVisible();
    await expect(page.getByText("It is in demo mode.", { exact: false })).toBeVisible();
    await expect(page.getByRole("link", { name: "Get recovery codes" })).toHaveAttribute("href", "/me/settings#recovery-codes");

    expect(sent.registered).toEqual([
      expect.objectContaining({ handle: "maria_coach", display_name: "Maria", email: "maria@example.com", password: "secret-pass", role: "member" }),
    ]);
    expect(sent.businesses).toEqual([
      {
        business_kind: "coach",
        business_name: "Maria Coaching",
        city: "Thessaloniki",
        phone: "+30 690 000 0000",
        timezone: expect.any(String),
        default_locale: "en",
      },
    ]);
  });
});

test.describe("demo mode", () => {
  test("an owner of a demo business fills this screen and every screen, removes the demo data and asks for activation", async ({ page }) => {
    await signedIn(page, OWNER, [ownerMembership("demo")]);
    const calls = await demoBusiness(page);
    await page.goto("/admin/users");

    const button = page.getByRole("button", { name: "Demo data" });
    await expect(button).toBeVisible();
    await button.click();
    const popover = page.getByRole("dialog", { name: "Try it with demo data" });
    await expect(popover).toBeVisible();

    // This screen is Members.
    await popover.getByRole("button", { name: "Add mock people" }).click();
    await expect(popover.getByRole("button", { name: "This screen has demo data" })).toBeDisabled();
    expect(calls.seeds).toEqual([{ section: "members" }]);

    await popover.getByRole("button", { name: "Fill every screen" }).click();
    await expect(popover.getByRole("button", { name: "Fill every screen" })).toBeHidden();
    expect(calls.seeds).toEqual([{ section: "members" }, { section: "all" }]);

    // Removing asks first; cancel keeps everything.
    await popover.getByRole("button", { name: "Remove demo data" }).click();
    await expect(popover.getByText("Remove every demo member, class and payment?", { exact: false })).toBeVisible();
    await popover.getByRole("button", { name: "Cancel" }).click();
    expect(calls.removes).toBe(0);
    await popover.getByRole("button", { name: "Remove demo data" }).click();
    await popover.getByRole("button", { name: "Remove", exact: true }).click();
    await expect(popover.getByRole("button", { name: "Add mock people" })).toBeEnabled();
    await expect(popover.getByRole("button", { name: "Remove demo data" })).toBeHidden();
    expect(calls.removes).toBe(1);

    await popover.getByRole("button", { name: "Ask the Palee team to activate" }).click();
    await expect(popover.getByText("Your activation request is with the Palee team.", { exact: false })).toBeVisible();
    await expect(popover.getByRole("button", { name: "Ask the Palee team to activate" })).toBeHidden();
    expect(calls.activationRequests).toEqual([{}]);
  });

  test("a `business_not_activated` refusal opens the activation notice, which files the request", async ({ page }) => {
    await signedIn(page, OWNER, [ownerMembership("demo")]);
    const calls = await demoBusiness(page);
    const profile = {
      about: "A small box in Kypseli.",
      disciplines: ["crossfit"],
      audiences: [],
      amenities: [],
      services: [],
      languages: [],
      cover: null,
      photos: [],
      published: false,
      published_at: null,
      unpublished_changes: false,
      missing: [],
      lock_version: 1,
      coaches: [],
      coach_candidates: [],
    };
    let publishAttempts = 0;
    await page.route("**/api/org/*/admin/public-profile", (route) => route.fulfill(json({ profile })));
    await page.route("**/api/org/*/admin/public-profile/publish", (route) => {
      publishAttempts += 1;
      return route.fulfill(json({ error: "This business is not activated yet", code: "business_not_activated" }, 403));
    });
    await page.goto("/admin/public-page");

    await expect(page.getByRole("heading", { name: "Public page" })).toBeVisible();
    await page.getByRole("button", { name: "Publish", exact: true }).click();

    const notice = page.getByRole("dialog", { name: "Activation by the Palee team" });
    await expect(notice).toBeVisible();
    expect(publishAttempts).toBe(1);
    await expect(notice.getByText("no real payments are taken")).toBeVisible();
    await notice.getByRole("button", { name: "Ask the Palee team to activate" }).click();
    await expect(notice.getByText("Your activation request is with the Palee team.", { exact: false })).toBeVisible();
    expect(calls.activationRequests).toEqual([{}]);

    await notice.getByRole("button", { name: "Close" }).first().click();
    await expect(notice).toBeHidden();
  });

  for (const [label, activation] of [
    ["an active business", "active"],
    ["a membership payload without the field", undefined],
  ] as const) {
    test(`${label} shows no demo button`, async ({ page }) => {
      await signedIn(page, OWNER, [ownerMembership(activation)]);
      const calls = await demoBusiness(page);
      await page.route("**/api/org/*/admin/public-profile", (route) =>
        route.fulfill(json({ profile: { about: null, disciplines: [], audiences: [], amenities: [], services: [], languages: [], cover: null, photos: [], published: false, missing: ["about"], lock_version: 0, coaches: [], coach_candidates: [] } })),
      );
      await page.goto("/admin/public-page");

      await expect(page.getByRole("heading", { name: "Public page" })).toBeVisible();
      await expect(page.getByRole("button", { name: "Demo data" })).toHaveCount(0);
      expect(calls.status).toBe(0);
    });
  }
});

test.describe("activation link", () => {
  // ADR-205: emails carry the token in the fragment; older links in the query.
  for (const [form, url] of [
    ["fragment", "/activate-business#token=act-token"],
    ["query", "/activate-business?token=act-token"],
  ] as const) {
    test(`the link (${form} form) shows what activation does, activates the business and opens its console`, async ({ page }) => {
      const sent: { inspected: unknown[]; redeemed: unknown[] } = { inspected: [], redeemed: [] };
      await signedIn(page, OWNER, [ownerMembership("demo")]);
      await page.route("**/api/business-activation/inspect", (route) => {
        sent.inspected.push(route.request().postDataJSON());
        return route.fulfill(
          json({
            organization: organization(),
            role: "owner",
            demo: { rows: 42, people: 8, sections: ["members", "schedule"] },
            expires_at: "2026-10-30T09:00:00Z",
          }),
        );
      });
      await page.route("**/api/business-activation/redeem", (route) => {
        sent.redeemed.push(route.request().postDataJSON());
        return route.fulfill(
          json({ organization: organization({ activation: "active", activated_at: NOW }), removed: { rows: 42, people: 8 }, roles: ["owner"] }),
        );
      });
      await page.goto(url);

      const main = page.getByRole("main");
      await expect(main.getByText("Box Kypseli", { exact: true })).toBeVisible();
      await expect(main.getByText("Gym or box · Owner")).toBeVisible();
      await expect(main.getByText("The demo data is removed (42 records, including 8 demo people).")).toBeVisible();
      expect(sent.inspected).toEqual([{ token: "act-token" }]);

      await page.getByRole("button", { name: "Activate", exact: true }).click();
      await expect(page.getByText("Box Kypseli is active.", { exact: false })).toBeVisible();
      expect(sent.redeemed).toEqual([{ token: "act-token" }]);
      // ADR-216: live is not findable yet; the next step is the public page.
      await expect(page.getByText("One more step so people find you", { exact: false })).toBeVisible();
      await expect(page.getByRole("button", { name: "Publish the public page" })).toBeVisible();

      await page.getByRole("button", { name: "Go to my console" }).click();
      await expect(page).toHaveURL(/\/org\/kypseli\/admin/);
    });
  }
});

test.describe("vendor queue", () => {
  test("the Palee team approves an activation request with the chosen role and issues a link for a demo business", async ({ page }) => {
    const sent: { decisions: unknown[]; links: unknown[] } = { decisions: [], links: [] };
    await signedIn(page, VENDOR);
    await page.route("**/api/platform/business-accounts", (route) =>
      route.fulfill(
        json({
          requests: [businessRequest()],
          demo_businesses: [
            {
              organization: organization({ id: "org-2", slug: "maria-coaching", name: "Maria Coaching", provider_kind: "coach" }),
              owners: [{ user_id: "maria-1", nickname: "Maria", email_verified: true }],
              link: null,
            },
          ],
        }),
      ),
    );
    await page.route("**/api/platform/business-requests/req-1/decision", (route) => {
      const body = route.request().postDataJSON() as { role?: string };
      sent.decisions.push(body);
      return route.fulfill(
        json({ request: businessRequest(), organization: organization(), activation_link: activationLink({ role: body.role }) }),
      );
    });
    await page.route("**/api/platform/organizations/org-2/activation-links", (route) => {
      const body = route.request().postDataJSON() as { role: string; user_id: string };
      sent.links.push(body);
      return route.fulfill(
        json(
          activationLink({ id: "link-2", organization_id: "org-2", user_id: body.user_id, nickname: "Maria", role: body.role, token: "maria-token", path: "/activate-business#token=maria-token" }),
          201,
        ),
      );
    });
    await page.goto("/platform/business-accounts");

    await expect(page.getByRole("heading", { name: "Business accounts" })).toBeVisible();
    const requests = page.getByRole("region", { name: "Requests" });
    const request = requests.getByRole("article").filter({ hasText: "Box Kypseli" });
    await expect(request.getByText("Activation · Gym or box · Apostolos", { exact: false })).toBeVisible();
    await chooseOption(page, request.getByRole("combobox", { name: "Role it grants" }), "admin");
    await request.getByRole("button", { name: "Issue activation link" }).click();

    await expect(request.getByText("Activation link (Admin).", { exact: false })).toBeVisible();
    await expect(request.getByRole("textbox", { name: "Activation link" })).toHaveValue(/\/activate-business#token=act-token$/);
    // ADR-205: the link is also emailed to the account.
    await expect(request.getByText("Email on its way")).toBeVisible();
    expect(sent.decisions).toEqual([{ decision: "approve", note: null, role: "admin" }]);

    const demo = page.getByRole("region", { name: "In demo mode" }).getByRole("article").filter({ hasText: "Maria Coaching" });
    await expect(demo.getByText("Independent coach · /maria-coaching", { exact: false })).toBeVisible();
    await demo.getByRole("button", { name: "Issue activation link" }).click();
    await expect(demo.getByRole("textbox", { name: "Activation link" })).toHaveValue(/\/activate-business#token=maria-token$/);
    expect(sent.links).toEqual([{ role: "owner", user_id: "maria-1" }]);

    // «Send a new link» issues a fresh link (and email) for the same account and role.
    await demo.getByRole("button", { name: "Send a new link" }).click();
    await expect.poll(() => sent.links.length).toBe(2);
    expect(sent.links[1]).toEqual({ role: "owner", user_id: "maria-1" });
  });

  // ADR-205: a link goes only to a confirmed email.
  test("an account without a confirmed email is flagged and gets no link; a failed email says so", async ({ page }) => {
    await signedIn(page, VENDOR);
    await page.route("**/api/platform/business-accounts", (route) =>
      route.fulfill(
        json({
          requests: [businessRequest({ requester_email_verified: false })],
          demo_businesses: [
            {
              organization: organization({ id: "org-2", slug: "maria-coaching", name: "Maria Coaching", provider_kind: "coach" }),
              owners: [{ user_id: "maria-1", nickname: "Maria", email_verified: false }],
              link: null,
            },
            {
              organization: organization({ id: "org-3", slug: "nikos-box", name: "Nikos Box" }),
              owners: [{ user_id: "nikos-1", nickname: "Nikos", email_verified: true }],
              link: activationLink({
                id: "link-3",
                organization_id: "org-3",
                user_id: "nikos-1",
                nickname: "Nikos",
                token: null,
                path: null,
                email_delivery: { status: "failed", error: null, sent_at: null },
              }),
            },
          ],
        }),
      ),
    );
    await page.goto("/platform/business-accounts");

    const request = page.getByRole("region", { name: "Requests" }).getByRole("article").filter({ hasText: "Box Kypseli" });
    await expect(request.getByText("Email not confirmed")).toBeVisible();
    await expect(request.getByRole("button", { name: "Issue activation link" })).toBeDisabled();

    const demos = page.getByRole("region", { name: "In demo mode" });
    const maria = demos.getByRole("article").filter({ hasText: "Maria Coaching" });
    await expect(maria.getByText("Email not confirmed")).toBeVisible();
    await expect(maria.getByRole("button", { name: "Issue activation link" })).toBeDisabled();

    const nikos = demos.getByRole("article").filter({ hasText: "Nikos Box" });
    await expect(nikos.getByText("The email didn't arrive.", { exact: false })).toBeVisible();
  });
});
