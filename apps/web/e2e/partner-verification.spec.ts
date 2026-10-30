import { expect, test, type Page } from "./support/test";

// ADR-280: Partners verification for people without a box or coach. Asking a
// Buddy to vouch, the QR/link screen for someone met in person, the mobile
// number and its SMS code, the selfie holding the code sent to the Palee
// team, and the sponsor's side (a vouch request and a sponsor link). The API
// is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGM4EaABRww4OQAsNg8BoqhHXQAAAABJRU5ErkJggg==", "base64");

const limits = {
  code_attempts: 5,
  code_minutes: 10,
  link_minutes: 10,
  selfie_content_types: ["image/heic", "image/jpeg", "image/png", "image/webp"],
  selfie_max_bytes: 8388608,
  selfie_retention_days: 7,
  sponsors_required: 2,
};

const person = (id: string, nickname: string) => ({ id, nickname, avatar_url: null });

type Request = Record<string, unknown>;

function request(extra: Request = {}): Request {
  return {
    id: "req-1",
    status: "collecting",
    consent_at: "2026-10-30T09:00:00Z",
    decided_at: null,
    decision_reason: null,
    missing: ["sponsors", "phone"],
    phone: null,
    phone_verified: false,
    selfie_code: "4827",
    selfie_expires_at: null,
    selfie_uploaded_at: null,
    sponsors: [],
    sponsors_required: 2,
    submitted_at: null,
    vouches: 0,
    ...extra,
  };
}

const collecting = (extra: Request = {}) => ({
  eligibility: { status: "needs_verification", method: null, next_step: "sponsors" },
  request: request(extra),
  limits,
});

async function signedIn(page: Page) {
  const user = {
    id: "person-1",
    nickname: "Giorgos",
    role: "member",
    email: "giorgos@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [],
  };
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: "member", memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString(
    "base64url",
  );
  const token = `stub.${payload}.signature`;
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh", user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

/** The verification endpoint answering whatever `state.overview` holds now. */
async function verification(page: Page, initial: unknown) {
  const state = { overview: initial };
  await page.route("**/api/me/partners/verification", (route) => route.fulfill(json(state.overview)));
  return state;
}

test.describe("partners verification", () => {
  test("a person verified through a membership only sees that they are verified", async ({ page }) => {
    await signedIn(page);
    await verification(page, { eligibility: { status: "verified", method: "membership", next_step: null }, request: null, limits });
    await page.goto("/partners/verify");

    await expect(page.getByText("You are verified")).toBeVisible();
    await expect(page.getByRole("link", { name: "Go to Training partners" })).toHaveAttribute("href", "/partners");
    await expect(page.getByTestId("verify-step-consent")).toHaveCount(0);
  });

  test("consent, then asking a verified Buddy to vouch and cancelling", async ({ page }) => {
    await signedIn(page);
    const state = await verification(page, {
      eligibility: { status: "needs_verification", method: null, next_step: "consent" },
      request: null,
      limits,
    });
    let consents = 0;
    await page.route("**/api/me/partners/verification/consent", (route) => {
      consents += 1;
      state.overview = collecting();
      return route.fulfill(json(state.overview));
    });
    const sponsorship: { status: string | null } = { status: null };
    const candidates = () => ({
      required: 2,
      vouches: 0,
      candidates: [
        { person: person("dimitra", "Dimitra"), eligible: true, reason: null, sponsorship: sponsorship.status ? { id: "sp-1", channel: "buddy", status: sponsorship.status } : null },
        { person: person("anna", "Anna"), eligible: false, reason: "not_verified", sponsorship: null },
      ],
    });
    await page.route("**/api/me/partners/verification/sponsor-candidates", (route) => route.fulfill(json(candidates())));
    const asked: unknown[] = [];
    await page.route("**/api/me/partners/verification/sponsors", (route) => {
      asked.push(route.request().postDataJSON());
      sponsorship.status = "requested";
      return route.fulfill(
        json({ sponsorship: { id: "sp-1", channel: "buddy", status: "requested", person: person("dimitra", "Dimitra"), requested_at: "2026-10-30T09:05:00Z", decided_at: null } }),
      );
    });
    const cancelled: string[] = [];
    await page.route("**/api/me/partners/verification/sponsors/*", (route) => {
      cancelled.push(route.request().method());
      sponsorship.status = "cancelled";
      return route.fulfill(
        json({ sponsorship: { id: "sp-1", channel: "buddy", status: "cancelled", person: person("dimitra", "Dimitra"), requested_at: "2026-10-30T09:05:00Z", decided_at: null } }),
      );
    });
    await page.goto("/partners/verify");

    const consent = page.getByTestId("verify-step-consent");
    await expect(consent.getByRole("link", { name: "How we use your data" })).toHaveAttribute("href", "/privacy#partners");
    await consent.getByRole("button", { name: "I agree, continue" }).click();
    await expect.poll(() => consents).toBe(1);

    const sponsors = page.getByTestId("sponsors-step");
    await expect(sponsors.getByTestId("sponsors-count")).toHaveText("0/2 vouched");
    await expect(sponsors.getByTestId("sponsor-anna")).toContainText("Not verified through a box or coach");
    await expect(sponsors.getByTestId("sponsor-anna").getByRole("button")).toHaveCount(0);

    await sponsors.getByRole("button", { name: "Ask Dimitra to vouch for you" }).click();
    await expect.poll(() => asked).toEqual([{ sponsor_id: "dimitra" }]);
    await expect(sponsors.getByTestId("sponsor-dimitra")).toContainText("Waiting for an answer");

    await sponsors.getByRole("button", { name: "Cancel your request to Dimitra" }).click();
    await expect.poll(() => cancelled).toEqual(["DELETE"]);
    await expect(sponsors.getByRole("button", { name: "Ask Dimitra to vouch for you" })).toBeVisible();
  });

  test("the QR and single-use link for someone met in person, with its countdown", async ({ page }) => {
    await signedIn(page);
    await verification(page, collecting());
    await page.route("**/api/me/partners/verification/sponsor-candidates", (route) => route.fulfill(json({ required: 2, vouches: 0, candidates: [] })));
    let links = 0;
    await page.route("**/api/me/partners/verification/link", (route) => {
      links += 1;
      return route.fulfill(
        json(
          {
            token: "tok-123",
            path: "/partners/vouch#token=tok-123",
            url: "http://127.0.0.1/partners/vouch#token=tok-123",
            expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
          },
          201,
        ),
      );
    });
    await page.goto("/partners/verify");

    const sponsors = page.getByTestId("sponsors-step");
    await expect(sponsors.getByText("You have no Buddies yet.", { exact: false })).toBeVisible();
    const toggle = sponsors.getByRole("button", { name: "The person who knows you is not here?" });
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await toggle.click();
    await sponsors.getByRole("button", { name: "Show QR code or link" }).click();

    const dialog = page.getByTestId("sponsor-link-dialog");
    await expect(dialog.getByRole("heading", { name: "Vouching in person" })).toBeVisible();
    await expect(dialog.getByRole("img", { name: "QR code for your sponsor" })).toBeVisible();
    await expect(dialog.getByTestId("sponsor-link-countdown")).toHaveText(/Expires in (10:00|9:\d\d)/);
    await expect(dialog.getByText("Works for one sponsor only.")).toBeVisible();
    expect(links).toBe(1);
    await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
    await dialog.getByRole("button", { name: "Copy link" }).click();
    await expect(dialog.getByRole("button", { name: "Link copied" })).toBeVisible();
  });

  test("the mobile number and its SMS code, with errors under the field", async ({ page }) => {
    await signedIn(page);
    const state = await verification(page, collecting({ vouches: 2 }));
    await page.route("**/api/me/partners/verification/sponsor-candidates", (route) => route.fulfill(json({ required: 2, vouches: 2, candidates: [] })));
    const sent: unknown[] = [];
    await page.route("**/api/me/partners/verification/phone", (route) => {
      sent.push(route.request().postDataJSON());
      return route.fulfill(json({ phone: "+30 69•• •••• 78", expires_at: new Date(Date.now() + 600_000).toISOString(), code_minutes: 10 }));
    });
    const codes: string[] = [];
    await page.route("**/api/me/partners/verification/phone/confirm", (route) => {
      const { code } = route.request().postDataJSON() as { code: string };
      codes.push(code);
      if (code !== "123456") return route.fulfill(json({ code: "partner_code_invalid", error: "That code is not right" }, 422));
      state.overview = { ...collecting({ vouches: 2, phone: "+30 69•• •••• 78", phone_verified: true }), eligibility: { status: "needs_verification", method: null, next_step: "selfie" } };
      return route.fulfill(json(state.overview));
    });
    await page.goto("/partners/verify");

    const phone = page.getByTestId("verify-step-phone");
    const number = phone.getByLabel("Mobile number");
    await number.fill("12");
    await expect(phone.getByRole("button", { name: "Send code" })).toBeDisabled();
    await number.fill("6912345678");
    await phone.getByRole("button", { name: "Send code" }).click();
    await expect.poll(() => sent).toEqual([{ phone: "6912345678" }]);

    await expect(phone.getByText("We sent a code to +30 69•• •••• 78. It is valid for 10 minutes.")).toBeVisible();
    await expect(phone.getByRole("button", { name: /Send again in \d+s/ })).toBeDisabled();
    const code = phone.getByLabel("6-digit code");
    await code.fill("111111");
    await phone.getByRole("button", { name: "Confirm" }).click();
    await expect(code).toHaveAttribute("aria-invalid", "true");
    await expect(phone.getByText("That code is not right.")).toBeVisible();

    await code.fill("123456");
    await phone.getByRole("button", { name: "Confirm" }).click();
    expect(codes).toEqual(["111111", "123456"]);
    await expect(page.getByTestId("verify-step-phone")).toHaveAttribute("data-state", "done");
    await expect(page.getByTestId("verify-step-selfie")).toHaveAttribute("data-state", "open");
  });

  test("the selfie holding the code goes to the Palee team, and the page shows «In review»", async ({ page }) => {
    await signedIn(page);
    const state = await verification(page, {
      ...collecting({ vouches: 2, phone: "+30 69•• •••• 78", phone_verified: true, sponsors: [] }),
      eligibility: { status: "needs_verification", method: null, next_step: "selfie" },
    });
    const uploads: string[] = [];
    await page.route("**/api/me/partners/verification/selfie/upload-url", (route) => {
      uploads.push((route.request().postDataJSON() as { content_type: string }).content_type);
      return route.fulfill(
        json({
          upload_url: "/__upload/selfie",
          method: "PUT",
          required_headers: { "content-type": "image/png" },
          file_key: "users/person-1/partner-verification/req-1.png",
          content_type: "image/png",
          max_bytes: 8388608,
          selfie_code: "4827",
        }),
      );
    });
    let put = 0;
    await page.route("**/__upload/**", (route) => {
      put += 1;
      return route.fulfill({ status: 200, body: "" });
    });
    const submitted: unknown[] = [];
    await page.route("**/api/me/partners/verification/submit", (route) => {
      submitted.push(route.request().postDataJSON());
      state.overview = {
        eligibility: { status: "in_review", method: null, next_step: null },
        request: request({ status: "in_review", vouches: 2, phone_verified: true, submitted_at: "2026-10-30T10:00:00Z" }),
        limits,
      };
      return route.fulfill(json(state.overview));
    });
    await page.goto("/partners/verify");

    const selfie = page.getByTestId("selfie-step");
    await expect(selfie.getByTestId("selfie-code")).toHaveText("4827");
    await selfie.getByTestId("selfie-file").setInputFiles({ name: "selfie.png", mimeType: "image/png", buffer: PNG });
    await expect(selfie.getByRole("img", { name: "Your selfie" })).toBeVisible();
    await selfie.getByRole("button", { name: "Send for review" }).click();

    await expect(page.getByTestId("verify-in-review")).toContainText("In review by the Palee team");
    expect(uploads).toEqual(["image/png"]);
    expect(put).toBe(1);
    expect(submitted).toEqual([{ file_key: "users/person-1/partner-verification/req-1.png" }]);
    // Withdrawing asks first, inside the page.
    await page.getByRole("button", { name: "Cancel and delete my details" }).click();
    await expect(page.getByText("Cancel your verification?")).toBeVisible();
    await page.getByRole("button", { name: "No, go back" }).click();
    await expect(page.getByText("Cancel your verification?")).toHaveCount(0);
  });

  test("a sponsor reads what vouching means and vouches from the request", async ({ page }) => {
    await signedIn(page);
    let requests = [{ id: "sp-9", person: person("giorgos-l", "Giorgos L."), requested_at: "2026-10-30T08:00:00Z" }];
    await page.route("**/api/me/partners/vouch-requests", (route) =>
      route.fulfill(
        json({ requests, vouching: { can_vouch: true, left: 4, quota: 5, used: 1, window_days: 30, penalty_until: null, reason: null } }),
      ),
    );
    const decisions: unknown[] = [];
    await page.route("**/api/me/partners/vouch-requests/sp-9", (route) => {
      decisions.push(route.request().postDataJSON());
      requests = [];
      return route.fulfill(json({ id: "sp-9", status: "vouched", decided_at: "2026-10-30T10:00:00Z" }));
    });
    await page.goto("/partners/vouch-requests");

    await expect(page.getByTestId("vouching-standing")).toHaveText("You can vouch for 4 more of 5 people in 30 days.");
    const card = page.getByTestId("vouch-request-sp-9");
    await expect(card.getByText("Giorgos L. asks you to be their sponsor")).toBeVisible();
    await expect(card.getByText("You confirm that you know them in person", { exact: false })).toBeVisible();
    await card.getByRole("button", { name: "I vouch" }).click();

    await expect(page.getByText("You vouched for Giorgos L.")).toBeVisible();
    expect(decisions).toEqual([{ decision: "vouch" }]);
    await expect(page.getByText("Nobody is asking you to vouch right now.")).toBeVisible();
  });

  test("a paused sponsor sees until when, and cannot vouch through a link", async ({ page }) => {
    await signedIn(page);
    await page.route("**/api/me/partners/vouch-links/inspect", (route) =>
      route.fulfill(
        json({ person: person("eleni", "Eleni"), can_vouch: false, reason: "partner_sponsor_penalty", expires_at: new Date(Date.now() + 300_000).toISOString() }),
      ),
    );
    await page.route("**/api/me/partners/vouching", (route) =>
      route.fulfill(json({ can_vouch: false, left: 0, quota: 5, used: 0, window_days: 30, penalty_until: "2026-12-29T00:00:00Z", reason: "penalty" })),
    );
    await page.goto("/partners/vouch#token=tok-123");

    await expect(page.getByText("Eleni asks you to be their sponsor")).toBeVisible();
    await expect(page.getByText("Vouching is paused for now.")).toBeVisible();
    await expect(page.getByTestId("vouching-standing")).toContainText("You can vouch again from");
    await expect(page.getByRole("button", { name: "I vouch" })).toHaveCount(0);
  });
});
