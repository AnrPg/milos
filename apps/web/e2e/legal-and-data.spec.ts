import { expect, test, type Page } from "./support/test";

// ADR-267: the public privacy policy and terms (drafts for the law
// consultant), the minimum-age confirmation at sign-up (checked in the form
// and by the API), and Settings › Your data › Download my data. The API is
// stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const user = {
  id: "member-1",
  nickname: "Maria L",
  display_name: "Maria L",
  handle: "maria",
  role: "member",
  email: "maria@example.com",
  email_verified: true,
  profile_count: 1,
  profile_limit: 3,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

async function signedOut(page: Page, locale = "en") {
  await page.context().addCookies([{ name: "palee_locale", value: locale, url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
  await page.route("**/api/auth/handle-suggestion?**", (route) => route.fulfill(json({ handle: "maria" })));
  await page.route("**/api/auth/handle-available?**", (route) =>
    route.fulfill(json({ available: true, handle: "maria", suggestions: [] })),
  );
}

async function signedIn(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [], unread_count: 0 })));
}

test.describe("privacy policy and terms", () => {
  test("are public drafts that list the real sub-processors and link to each other", async ({ page }) => {
    await signedOut(page);
    await page.goto("/privacy");

    await expect(page.getByRole("heading", { level: 1, name: "Privacy policy" })).toBeVisible();
    await expect(page.getByRole("note")).toContainText("not yet in force");
    await expect(page.getByText("[legal name of the company]", { exact: false }).first()).toBeVisible();
    const processors = page.getByRole("table");
    for (const name of ["Brevo", "Google Gemini API", "Anthropic API", "Cloudflare", "photon.komoot.io", "tiles.openfreemap.org", "Stripe", "fiskaly", "AADE myDATA"]) {
      await expect(processors).toContainText(name);
    }
    await expect(page.getByText("Garmin Connect (Garmin Ltd.)", { exact: false })).toBeVisible();
    await expect(page.getByText("for 5 years after the box is deleted from Palee", { exact: false })).toBeVisible();

    // Health Connect's privacy link opens this section.
    await page.goto("/privacy#health");
    await expect(page.locator("#health")).toBeInViewport();

    await page.getByRole("navigation", { name: "Legal" }).getByRole("link", { name: "Terms of use" }).click();
    await expect(page).toHaveURL(/\/terms$/);
    await expect(page.getByRole("heading", { level: 1, name: "Terms of use" })).toBeVisible();
    await expect(page.getByText("You must be 16 or older.", { exact: false })).toBeVisible();
  });

  test("read in Greek, with the canonical names", async ({ page }) => {
    await signedOut(page, "el");
    await page.goto("/privacy");
    await expect(page.getByRole("heading", { level: 1, name: "Πολιτική απορρήτου" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Τα δικαιώματά σου" })).toBeVisible();
    await expect(page.getByText("«Λήψη των δεδομένων μου»", { exact: false })).toBeVisible();
  });

  test("are in the sitemap and linked from About", async ({ page, request }) => {
    const sitemap = await (await request.get("/sitemap.xml")).text();
    expect(sitemap).toContain("/privacy</loc>");
    expect(sitemap).toContain("/terms</loc>");

    await signedOut(page);
    await page.goto("/about");
    const legal = page.getByRole("navigation", { name: "Legal" });
    await expect(legal.getByRole("link", { name: "Privacy policy" })).toHaveAttribute("href", "/privacy");
    await expect(legal.getByRole("link", { name: "Terms of use" })).toHaveAttribute("href", "/terms");
  });
});

test.describe("minimum age at sign-up", () => {
  test("asks for the confirmation under the box, then sends it", async ({ page }) => {
    const sent: unknown[] = [];
    await signedOut(page);
    await page.route("**/api/auth/register", (route) => {
      sent.push(route.request().postDataJSON());
      return route.fulfill(json({ confirmation: "email_sent", email: "maria@example.com" }, 201));
    });

    await page.goto("/register");
    await page.getByLabel("Your name", { exact: true }).fill("Maria");
    await page.getByLabel("Handle", { exact: true }).fill("maria");
    await page.getByLabel("Email address", { exact: true }).fill("maria@example.com");
    await page.getByLabel("Password", { exact: true }).fill("secret-pass");
    await expect(page.getByRole("link", { name: "Terms of use" })).toHaveAttribute("href", "/terms");
    await expect(page.getByRole("link", { name: "Privacy policy" })).toHaveAttribute("href", "/privacy");
    await page.getByRole("button", { name: "Create account" }).click();

    const box = page.getByLabel("I am 16 or older");
    await expect(box).toHaveAttribute("aria-invalid", "true");
    await expect(page.getByText("Palee is for people aged 16 or older.", { exact: false })).toBeVisible();
    expect(sent).toEqual([]);

    await box.check();
    await page.getByRole("button", { name: "Create account" }).click();
    await expect(page.getByRole("heading", { name: "Check your inbox" })).toBeVisible();
    expect(sent).toEqual([expect.objectContaining({ handle: "maria", age_confirmed: true })]);
  });

  test("shows the API's refusal under the box too", async ({ page }) => {
    await signedOut(page);
    await page.route("**/api/auth/register", (route) =>
      route.fulfill(
        json({ code: "validation_failed", error: "Validation failed", errors: { age_confirmed: ["minimum_age"] } }, 422),
      ),
    );

    await page.goto("/register");
    await page.getByLabel("Your name", { exact: true }).fill("Maria");
    await page.getByLabel("Handle", { exact: true }).fill("maria");
    await page.getByLabel("Email address", { exact: true }).fill("maria@example.com");
    await page.getByLabel("Password", { exact: true }).fill("secret-pass");
    await page.getByLabel("I am 16 or older").check();
    await page.getByRole("button", { name: "Create account" }).click();

    await expect(page.getByText("Palee is for people aged 16 or older.", { exact: false })).toBeVisible();
  });
});

test.describe("download my data", () => {
  test("asks for a copy in Settings, then downloads the ready file", async ({ page }) => {
    let exports: unknown[] = [];
    await signedIn(page);
    await page.route("**/api/me/data-exports", async (route) => {
      if (route.request().method() === "POST") {
        const pending = { id: "e-1", status: "pending", requested_at: "2026-10-29T09:00:00Z", file: null };
        exports = [pending];
        return route.fulfill(json({ export: pending }, 202));
      }
      return route.fulfill(json({ exports }));
    });

    await page.goto("/me/settings#your-data");
    const section = page.locator("#your-data");
    await expect(section.getByRole("heading", { name: "Download my data" })).toBeVisible();
    await expect(section.getByRole("link", { name: "Privacy policy" })).toHaveAttribute("href", "/privacy");

    await section.getByRole("button", { name: "Download my data" }).click();
    await expect(section.getByText("Preparing your file", { exact: false })).toBeVisible();
    await expect(section.getByRole("button", { name: "Prepare a new copy" })).toBeDisabled();

    // The job finishes; the section looks again while the file is pending.
    exports = [
      {
        id: "e-1",
        status: "ready",
        requested_at: "2026-10-29T09:00:00Z",
        completed_at: "2026-10-29T09:01:00Z",
        expires_at: "2026-11-05T09:01:00Z",
        record_count: 120,
        file: { name: "palee-my-data-2026-10-29.zip", bytes: 48_000, sha256: "abc", download_url: "https://media.example/my-data.zip?sig=1" },
      },
    ];
    const link = section.getByRole("link", { name: /Download the file/ });
    await expect(link).toBeVisible({ timeout: 15_000 });
    await expect(link).toHaveAttribute("href", "https://media.example/my-data.zip?sig=1");
    await expect(section.getByText("You can download it until", { exact: false })).toBeVisible();
  });

  test("says when a new copy can be asked for", async ({ page }) => {
    await signedIn(page);
    await page.route("**/api/me/data-exports", (route) =>
      route.request().method() === "POST"
        ? route.fulfill(json({ code: "export_rate_limited", error: "Too many", retry_at: "2026-10-30T09:00:00Z" }, 429))
        : route.fulfill(json({ exports: [] })),
    );

    await page.goto("/me/settings#your-data");
    const section = page.locator("#your-data");
    await section.getByRole("button", { name: "Download my data" }).click();
    await expect(section.getByText("You can ask for a new copy once a day.", { exact: false })).toBeVisible();
  });
});
