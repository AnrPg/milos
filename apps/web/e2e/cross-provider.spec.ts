import { expect, test, type Page, type Request } from "@playwright/test";

// Redesign Phase 2 M14 (ADR-162, plan board 17): one journal across a gym and
// an independent coach. Box ▾ switches provider and remembers it on the
// account, «Σήμερα» merges both providers' day with source labels, Ροή filters
// by source and remembers the filter, a coach rung asks whose coaches it
// means, and Ρυθμίσεις exports the whole journal. The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    completed_tours: ["admin", "member", "athlete"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const membership = (id: string, slug: string, name: string) => ({
  role: "member",
  roles: ["member"],
  capabilities: {},
  organization: { id, slug, name },
  settings: { brand_name: name, brand_logo_url: null, brand_primary_color: null },
});

const provider = (id: string, slug: string, name: string, kind: "gym" | "coach", selected: boolean) => ({
  organization_id: id,
  slug,
  name,
  kind,
  logo_url: null,
  primary_color: null,
  roles: ["member"],
  selected,
  next: null,
  unread_messages: kind === "coach" ? 1 : 0,
  partial: false,
});

function providers(selected: "org-box" | "org-coach") {
  return {
    selected_organization_id: selected,
    providers: [
      provider("org-box", "kypseli", "Box Kypseli", "gym", selected === "org-box"),
      provider("org-coach", "nikos", "Nikos P.", "coach", selected === "org-coach"),
    ],
    former: [{ organization_id: "org-old", slug: "old-box", name: "Old Box", kind: "gym", logo_url: null, primary_color: null, ended_at: "2026-03-01T00:00:00Z" }],
  };
}

const source = (id: string | null, name: string | null, kind: "organization" | "freeform" | "device" = "organization") => ({
  kind,
  organization_id: id,
  name,
  former: false,
});

async function common(page: Page) {
  const { user, token } = persona();
  await page.context().addCookies([{ name: "milos_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([membership("org-box", "kypseli", "Box Kypseli"), membership("org-coach", "nikos", "Nikos P.")])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/providers", (route) => route.fulfill(json(providers("org-box"))));
  await page.route("**/api/me/journal/coach-audience", (route) =>
    route.fulfill(
      json({
        organization_ids: ["org-box", "org-coach"],
        coaches: [
          { organization_id: "org-box", user_id: "u-eleni" },
          { organization_id: "org-box", user_id: "u-petros" },
          { organization_id: "org-coach", user_id: "u-nikos" },
        ],
        providers: [
          {
            organization_id: "org-box",
            name: "Box Kypseli",
            kind: "gym",
            included: true,
            coaches: [
              { user_id: "u-eleni", name: "Eleni", included: true },
              { user_id: "u-petros", name: "Petros", included: true },
            ],
          },
          {
            organization_id: "org-coach",
            name: "Nikos P.",
            kind: "coach",
            included: true,
            coaches: [{ user_id: "u-nikos", name: "Nikos", included: true }],
          },
        ],
      }),
    ),
  );
}

test.describe("One journal across providers", () => {
  test("Box ▾ lists everyone who trains you and remembers the switch", async ({ page }) => {
    await common(page);
    const at = new Date();
    at.setHours(18, 0, 0, 0);
    await page.route("**/api/me/today?**", (route) =>
      route.fulfill(
        json({
          date: "2026-10-21",
          timezone: "UTC",
          partial: false,
          failed_organization_ids: [],
          items: [
            { kind: "program", id: "as-1", at: null, title: "Lower body A", status: null, source: source("org-coach", "Nikos P."), target: { organization_id: "org-coach", slug: "nikos" } },
            { kind: "class", id: "slot-1", at: at.toISOString(), title: "CrossFit", status: "approved", source: source("org-box", "Box Kypseli"), target: { organization_id: "org-box", slug: "kypseli" } },
          ],
        }),
      ),
    );
    let selected: string | null = null;
    await page.route("**/api/me/providers/selected", (route) => {
      selected = bodyOf(route.request()).organization_id;
      return route.fulfill(json(providers("org-coach")));
    });

    await page.goto("/box");
    const today = page.getByRole("list", { name: "Today" });
    await expect(today.getByText("Lower body A")).toBeVisible();
    await expect(today.getByText("Nikos P.")).toBeVisible();
    await expect(today.getByText("CrossFit")).toBeVisible();

    await page.getByRole("button", { name: "Box Kypseli, switch provider" }).click();
    const sheet = page.getByRole("dialog", { name: "Who trains you" });
    await expect(sheet.getByText("Personal coach · 1 message")).toBeVisible();
    await sheet.getByRole("button", { name: "Past providers (1)" }).click();
    await expect(sheet.getByText("Old Box")).toBeVisible();
    await expect(sheet.getByRole("link", { name: "Add a box or coach" })).toHaveAttribute("href", "/me/clubs#join");

    await sheet.getByRole("button", { name: /Nikos P\./ }).click();
    await expect(sheet).toBeHidden();
    expect(selected).toBe("org-coach");
    expect(await page.evaluate(() => window.localStorage.getItem("milos:selected-organization-slug"))).toBe("nikos");
  });

  test("Ροή labels each entry's source, filters by it and remembers the filter", async ({ page }) => {
    await common(page);
    const requests: URL[] = [];
    await page.route("**/api/me/journal?**", (route) => {
      const url = new URL(route.request().url());
      requests.push(url);
      const filtered = url.searchParams.get("sources") === "org-coach";
      const note = (id: string, body: string, from: ReturnType<typeof source>) => ({
        kind: "note",
        id,
        occurred_at: new Date().toISOString(),
        occurred_tz: "UTC",
        organization_id: from.organization_id,
        journal_visibility: "private",
        choosable_visibilities: ["private", "coach_can_view", "coach_reply_requested"],
        source: from,
        audience: null,
        entry: { id, topic: "thought", body, journal_visibility: "private", organization_id: from.organization_id },
      });
      const items = [note("n-coach", "Squats felt strong", source("org-coach", "Nikos P."))];
      if (!filtered) items.push(note("n-free", "Easy walk", source(null, null, "freeform")));
      return route.fulfill(json({ items, next_cursor: null, filter: {}, active_filter_count: filtered ? 1 : 0 }));
    });

    await page.goto("/journal");
    await expect(page.getByText("Easy walk")).toBeVisible();
    await expect(page.locator("[data-source=freeform]").first()).toHaveText("Freeform");
    await expect(page.locator("[data-source=organization]").first()).toHaveText("Nikos P.");

    await page.getByRole("button", { name: "Source" }).click();
    await page.getByRole("menuitemcheckbox", { name: "Nikos P." }).click();
    await expect(page.getByText("Easy walk")).toBeHidden();
    const last = requests[requests.length - 1];
    expect(last.searchParams.get("sources")).toBe("org-coach");
    expect(last.searchParams.get("remember")).toBe("true");
  });

  test("a coach rung asks once whose coaches «My coaches» means", async ({ page }) => {
    await common(page);
    await page.route("**/api/me/journal?**", (route) =>
      route.fulfill(
        json({
          items: [
            {
              kind: "note",
              id: "n-1",
              occurred_at: new Date().toISOString(),
              occurred_tz: "UTC",
              organization_id: null,
              journal_visibility: "private",
              choosable_visibilities: ["private", "coach_can_view"],
              source: { kind: "freeform", organization_id: null, name: null, former: false },
              audience: {
                custom: false,
                organization_ids: ["org-box", "org-coach"],
                coaches: [
                  { organization_id: "org-box", user_id: "u-eleni" },
                  { organization_id: "org-box", user_id: "u-petros" },
                  { organization_id: "org-coach", user_id: "u-nikos" },
                ],
              },
              entry: { id: "n-1", topic: "thought", body: "Shoulder is tight", journal_visibility: "private", organization_id: null },
            },
          ],
          next_cursor: null,
        }),
      ),
    );
    await page.route("**/api/me/journal/entries/note/n-1/visibility", (route) =>
      route.fulfill(json({ kind: "note", id: "n-1", journal_visibility: "coach_can_view", choosable_visibilities: ["private", "coach_can_view", "coach_reply_requested"] })),
    );
    const audience = page.waitForRequest((request) => request.url().endsWith("/me/journal/entries/note/n-1/audience") && request.method() === "PUT");
    await page.route("**/api/me/journal/entries/note/n-1/audience", (route) =>
      route.fulfill(
        json({
          kind: "note",
          id: "n-1",
          audience: {
            custom: true,
            organization_ids: ["org-box", "org-coach"],
            coaches: [
              { organization_id: "org-box", user_id: "u-petros" },
              { organization_id: "org-coach", user_id: "u-nikos" },
            ],
          },
        }),
      ),
    );

    await page.goto("/journal");
    await page.getByRole("button", { name: /Who sees it/ }).click();
    const picker = page.getByRole("dialog", { name: "Who sees it" });
    await picker.getByRole("radio", { name: /Coach can view/ }).check();
    const chooser = picker.getByRole("group", { name: "Who do you mean by «My coaches»?" });
    await expect(chooser).toBeVisible();
    // Per coach: leave Eleni at the box out, Petros there still sees it.
    await chooser.getByRole("button", { name: /Eleni/ }).click();
    await chooser.getByRole("checkbox", { name: "Use this for my coaches from now on" }).uncheck();
    await picker.getByRole("button", { name: "Save" }).click();
    expect(bodyOf(await audience)).toEqual({
      coaches: [
        { organization_id: "org-box", user_id: "u-petros" },
        { organization_id: "org-coach", user_id: "u-nikos" },
      ],
    });
  });

  test("Ρυθμίσεις exports the whole journal", async ({ page }) => {
    await common(page);
    let exports: unknown[] = [];
    await page.route("**/api/me/journal/exports", (route) => route.fulfill(json({ exports })));
    const requested = page.waitForRequest((request) => request.url().endsWith("/me/journal/export") && request.method() === "POST");
    await page.route("**/api/me/journal/export", (route) => {
      exports = [
        {
          id: "x-1",
          status: "ready",
          requested_at: new Date().toISOString(),
          completed_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(),
          entry_count: 42,
          files: [{ name: "journal.json", content_type: "application/json", download_url: "http://media.localhost/journal.json", bytes: 1024 }],
        },
      ];
      return route.fulfill(json({ export: { ...(exports[0] as object), status: "pending" } }, 202));
    });

    await page.goto("/me/settings");
    await page.getByRole("button", { name: /Export my journal/ }).click();
    await page.getByRole("button", { name: "Export", exact: true }).click();
    await requested;
    await expect(page.getByRole("link", { name: "Download journal.json" })).toBeVisible();
    await expect(page.getByText("42 entries", { exact: false })).toBeVisible();
  });
});
