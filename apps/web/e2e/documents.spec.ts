import { expect, test, type Page, type Route } from "./support/test";

// ADR-252, mockup s7 «Έγγραφα με υπογραφή» option B (changed by the product
// owner): staff mark each document mandatory or optional and only the
// mandatory ones block booking. Staff see who is missing per document; the
// client signs in Box › Documents or right inside the booking sheet after
// the booking answered 409 `documents_required`. The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function account(id: string, role: string) {
  return {
    id,
    nickname: id === "owner-1" ? "Xristoforos" : "Maria L",
    role: "member",
    email: `${id}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role, settings: {} }],
  };
}

function tokenFor(id: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub: id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

async function signIn(page: Page, id: string, role: string, capabilities: Record<string, string>) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(id), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(account(id, role))));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role,
          roles: [role],
          capabilities,
          home_location_id: "loc-1",
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
}

/** One handler for every documents path, keyed by method and the path after /api/org/kypseli. */
async function documentsApi(page: Page, handle: (method: string, path: string, route: Route) => unknown) {
  await page.route(
    (url) => /\/api\/org\/[^/]+\/(admin|me)\/documents/.test(url.pathname),
    async (route) => {
      const url = new URL(route.request().url());
      const path = url.pathname.replace(/^\/api\/org\/[^/]+/, "");
      const body = await handle(route.request().method(), path, route);
      if (body !== undefined) await route.fulfill(json(body));
      else await route.fulfill(json({}));
    },
  );
}

const template = (id: string, title: string, requirement: "mandatory" | "optional") => ({
  id,
  kind: "terms",
  title,
  requirement,
  status: "active",
  current_version_id: `${id}-v3`,
  current_version_number: 3,
  required_version_number: 3,
  archived_at: null,
  inserted_at: "2026-10-01T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
});

const settings = {
  block_booking_on_unsigned: true,
  health_certificate_required: true,
  block_booking_on_health_certificate: true,
  health_certificate_validity_months: 12,
  health_certificate_reminder_days: 30,
};

const termsVersion = {
  id: "terms-v3",
  template_id: "terms",
  number: 3,
  title: "Terms of participation",
  body: "1. I train at my own risk.\n2. I tell the coach about any injury.",
  change_kind: "major",
  language: "en",
  content_hash: "hash",
  published_at: "2026-10-01T00:00:00Z",
};

test.describe("signed documents (ADR-252)", () => {
  test("staff see who is missing per document and are warned before a mandatory document blocks booking", async ({ page }) => {
    await signIn(page, "owner-1", "owner", { manage_settings: "all", manage_memberships: "all", manage_health_certificates: "all" });
    const requests: unknown[] = [];
    await documentsApi(page, (method, path, route) => {
      if (path === "/admin/documents/templates" && method === "GET")
        return { templates: [template("terms", "Terms of participation", "mandatory"), template("privacy", "Privacy notice", "optional")] };
      if (path === "/admin/documents/outstanding")
        return {
          templates: [
            {
              template_id: "terms",
              signed: 6,
              outstanding: 2,
              clients: [
                { user_id: "maria", display_name: "Maria K.", handle: null, status: "resign_required" },
                { user_id: "anna", display_name: "Anna Z.", handle: null, status: "unsigned" },
              ],
            },
            { template_id: "privacy", signed: 8, outstanding: 0, clients: [] },
          ],
        };
      if (path === "/admin/documents/settings") return { settings };
      if (path === "/admin/documents/health-certificates") return { required: true, full_access: true, health_certificates: [] };
      if (path === "/admin/documents/requests") return { requests: [], total: 0 };
      if (path === "/admin/documents/signatures") return { signatures: [], total: 0 };
      if (path === "/admin/documents/starters")
        return {
          starters: [
            { kind: "waiver", language: "en", title: "Waiver", body: "DRAFT FOR LEGAL REVIEW\nText", requirement: "mandatory", draft: true, legal_review_required: true },
          ],
        };
      if (path === "/admin/documents/templates/terms/requests" && method === "POST") {
        requests.push(route.request().postDataJSON());
        return { batch_id: "b", audience: "person", recipients: 1, created: 1, skipped: 0, requests: [] };
      }
      return undefined;
    });

    await page.goto("/admin/documents");
    const terms = page.getByTestId("documents-row-terms");
    await expect(terms).toContainText("2 missing");
    await expect(terms).toContainText("blocks booking");
    await expect(page.getByTestId("documents-row-privacy")).toContainText("Optional");

    await terms.click();
    const missing = page.getByTestId("missing-list");
    await expect(missing.getByText("Maria K.")).toBeVisible();
    await missing.getByRole("listitem").filter({ hasText: "Anna Z." }).getByRole("button", { name: "Ask" }).click();
    await expect.poll(() => requests).toEqual([{ audience: "person", user_id: "anna" }]);
    await page.keyboard.press("Escape");

    await page.getByRole("button", { name: "New document" }).click();
    const dialog = page.getByTestId("new-document-dialog");
    await expect(dialog.getByText("Draft for legal review")).toBeVisible();
    await dialog.getByRole("button", { name: /Waiver/ }).click();
    await expect(page.getByTestId("draft-banner")).toBeVisible();
    await expect(page.getByTestId("booking-block-warning")).toBeVisible();
    await page.getByRole("radio", { name: "Optional" }).click();
    await expect(page.getByTestId("booking-block-warning")).toHaveCount(0);
  });

  test("a client signs what is missing from Box › Documents", async ({ page }) => {
    await signIn(page, "member-1", "member", {});
    let signed = false;
    const signatures: unknown[] = [];
    await documentsApi(page, (method, path, route) => {
      if (path === "/me/documents")
        return {
          outstanding: signed ? 0 : 1,
          documents: [
            {
              template_id: "terms",
              kind: "terms",
              title: "Terms of participation",
              requirement: "mandatory",
              current_version_id: "terms-v3",
              current_version_number: 3,
              status: signed ? "signed" : "resign_required",
              outstanding: !signed,
              requested: true,
              signature: signed ? { id: "sig-1", version_number: 3, signed_at: "2026-10-29T10:00:00Z", content_hash: "hash" } : null,
            },
          ],
          health_certificate: { required: false, status: "missing", certificate: null },
        };
      if (path === "/me/documents/signatures")
        return {
          signatures: signed ? [{ id: "sig-1", template_id: "terms", version_id: "terms-v3", version_number: 3, signed_at: "2026-10-29T10:00:00Z" }] : [],
          total: signed ? 1 : 0,
        };
      if (path === "/me/documents/terms") return { template: template("terms", "Terms of participation", "mandatory"), version: termsVersion, status: "resign_required" };
      if (path === "/me/documents/terms/sign" && method === "POST") {
        signatures.push(route.request().postDataJSON());
        signed = true;
        return { signature: { id: "sig-1" } };
      }
      return undefined;
    });

    await page.goto("/box/documents");
    const row = page.getByTestId("my-doc-terms");
    await expect(row).toContainText("New version: needs a new signature");
    await row.click();

    await expect(page.getByText("1. I train at my own risk.")).toBeVisible();
    await page.getByLabel("Or type your full name").fill("Maria Lambrou");
    await page.getByRole("button", { name: "Sign", exact: true }).click();

    await expect(page).toHaveURL(/\/box\/documents$/);
    await expect.poll(() => signatures).toEqual([{ version_id: "terms-v3", agreed: true, typed_name: "Maria Lambrou" }]);
    await expect(page.getByTestId("my-doc-terms")).toContainText("Signed");
    await expect(page.getByRole("button", { name: "Certificate (PDF)" })).toBeVisible();
  });

  test("a booking blocked by a missing signature is signed inside the sheet, then booked", async ({ page }) => {
    await signIn(page, "member-1", "member", {});
    const now = new Date();
    now.setHours(6, 0, 0, 0);
    await page.clock.setFixedTime(now);
    const classAt = new Date(now);
    classAt.setHours(18);
    const day = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    const crossfit = { id: "ct-1", name: "CrossFit", kind: "class", level: "all_levels", audiences: [] };

    await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
    await page.route("**/api/me/places**", (route) => route.fulfill(json({ places: [] })));
    await page.route("**/api/me/filters/box_schedule", (route) => route.fulfill(json({ surface: "box_schedule", last_used: null, saved: [] })));
    await page.route("**/api/org/*/schedule?**", (route) =>
      route.fulfill(
        json({
          start_date: day,
          end_date: day,
          days: 14,
          class_types: [crossfit],
          coaches: [{ id: "coach-1", nickname: "Nikos", avatar_url: null }],
          slots: [
            {
              id: "s-1",
              name: "CrossFit",
              duration_minutes: 60,
              scheduled_at: classAt.toISOString(),
              class_type_id: "ct-1",
              class_type: crossfit,
              capacity: 12,
              auto_approve: true,
              booking_timeout_minutes: 30,
              approved_booking_count: 4,
              spots_remaining: 8,
              coach_user_id: "coach-1",
              location_id: null,
              covered_by_package: true,
              workout: null,
              current_user_booking: null,
              bookings: [],
            },
          ],
        }),
      ),
    );

    let signed = false;
    let bookings = 0;
    await page.route("**/api/org/*/bookings", async (route) => {
      if (route.request().method() !== "POST") return route.fulfill(json({}));
      bookings += 1;
      if (!signed)
        return route.fulfill(
          json(
            {
              error: "Sign the box's documents before you book",
              code: "documents_required",
              params: {
                documents: [{ template_id: "terms", title: "Terms of participation", kind: "terms", reason: "unsigned" }],
                health_certificate: null,
              },
            },
            409,
          ),
        );
      return route.fulfill(
        json({ booking: { id: "b-1", slot_id: "s-1", user_id: "member-1", status: "approved", inserted_at: now.toISOString() } }, 201),
      );
    });
    await documentsApi(page, (method, path) => {
      if (path === "/me/documents/terms") return { template: template("terms", "Terms of participation", "mandatory"), version: termsVersion, status: "unsigned" };
      if (path === "/me/documents/terms/sign" && method === "POST") {
        signed = true;
        return { signature: { id: "sig-1" } };
      }
      if (path === "/me/documents") return { outstanding: 0, documents: [], health_certificate: { required: false, status: "missing", certificate: null } };
      return undefined;
    });

    await page.goto("/box/schedule");
    const sheet = page.getByRole("dialog", { name: "CrossFit" });
    const card = page.getByRole("main").getByRole("button", { name: /CrossFit/ });
    await expect(async () => {
      await card.click();
      await expect(sheet).toBeVisible({ timeout: 2_000 });
    }).toPass({ timeout: 20_000 });

    await sheet.getByRole("button", { name: "Book" }).click();
    const gate = sheet.getByTestId("documents-gate");
    await expect(gate).toContainText("Before you book, these are missing:");
    await expect(sheet.getByRole("button", { name: "Book" })).toBeDisabled();

    await gate.getByTestId("gate-step-terms").click();
    await expect(sheet.getByText("1. I train at my own risk.")).toBeVisible();
    await sheet.getByLabel("Or type your full name").fill("Maria Lambrou");
    await sheet.getByRole("button", { name: "Sign", exact: true }).click();

    await expect(sheet.getByTestId("gate-step-terms")).toContainText("Done");
    await sheet.getByRole("button", { name: "Book" }).click();
    await expect(sheet).toHaveCount(0);
    expect(bookings).toBe(2);
  });
});
