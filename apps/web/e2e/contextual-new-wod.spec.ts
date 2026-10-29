import { expect, test, type Page, type Request } from "./support/test";

// «+ New WOD» from inside a class: the WOD editor opens over the class (the
// class sheet or form stays as the coach left it) and the published WOD is
// assigned to that class straight away. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const draftId = "11111111-1111-4111-8111-111111111111";

// In two hours: inside today's window in any zone except right before midnight.
const startsAt = new Date(Date.now() + 2 * 3600_000);
startsAt.setUTCMinutes(0, 0, 0);

const draftClass = {
  id: "slot-1",
  class_series_id: null,
  master_workout_id: null,
  name: "Evening WOD",
  duration_minutes: 60,
  scheduled_at: startsAt.toISOString(),
  class_type_id: "ct",
  class_type: { id: "ct", name: "CrossFit", slug: "crossfit" },
  capacity: 12,
  auto_approve: true,
  booking_timeout_minutes: 30,
  approved_booking_count: 0,
  spots_remaining: 12,
  workout: null,
  coach_user_id: null,
  location_id: null,
  bookings: [],
  published: false,
  workout_status: "missing",
};

// A WOD written in text sections (the WOD assistant is off at this gym),
// already complete, so the coach only has to publish it.
const sectionedDraft = {
  id: draftId,
  status: "draft",
  title: "Legs",
  type: "strength",
  authoring_mode: "sectioned_text",
  dsl_source_revision: 1,
  available_scale_levels: [],
  sections: [
    {
      name: "A",
      free_text_body: "Back squat 5x5",
      timer_preset: { format: "emom", interval_seconds: 120, rounds: 5 },
      exercises: [],
    },
  ],
  draft_data: { authoring_mode: "sectioned_text" },
};

async function asOwner(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Olga",
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
    roles: ["owner", "coach"],
    capabilities: { manage_schedule: "all", run_classes: "all", manage_coaching: "all" },
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
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [draftClass] })),
  );
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));

  // The WOD editor.
  await page.route("**/api/org/box1/admin/workouts/authoring-settings", (route) => route.fulfill(json({ wod_assistant_enabled: false })));
  await page.route("**/api/org/box1/admin/workouts", (route) =>
    route.request().method() === "POST"
      ? route.fulfill(json({ draft: { id: draftId, status: "draft", authoring_mode: "structured", dsl_source_revision: 0 } }, 201))
      : route.fulfill(json({ workouts: [] })),
  );
  await page.route(`**/api/org/box1/admin/workouts/${draftId}`, (route) => route.fulfill(json({ workout: sectionedDraft })));
  await page.route(`**/api/org/box1/admin/workouts/${draftId}/draft`, (route) =>
    route.fulfill(json({ draft: { id: draftId, status: "draft", authoring_mode: "sectioned_text", dsl_source_revision: 2 } })),
  );
  await page.route(`**/api/org/box1/admin/workouts/${draftId}/goals`, (route) => route.fulfill(json({ goals: null, suggestion: null })));
}

async function publishFromCreator(page: Page) {
  const creator = page.getByTestId("contextual-wod-creator");
  await expect(creator).toBeVisible();
  await expect(creator).toContainText("New WOD");
  await expect(creator.getByText("Back squat 5x5")).toBeVisible({ timeout: 15_000 });
  await creator.getByRole("button", { name: "Publish workout" }).click();
  await expect(creator).toHaveCount(0);
}

test.describe("Schedule › «+ New WOD» comes back to the class", () => {
  test("a class without a WOD gets the new WOD as soon as it is published, without leaving its sheet", async ({ page }) => {
    await asOwner(page);
    let published = false;
    let linked: Record<string, unknown> | null = null;
    await page.route(`**/api/org/box1/admin/workouts/${draftId}/publish`, (route) => {
      published = true;
      return route.fulfill(json({ workout: { ...sectionedDraft, status: "published" } }));
    });
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/workout", (route) => {
      linked = bodyOf(route.request());
      return route.fulfill(json({ slot: { ...draftClass, master_workout_id: "copy-1", published: true, workout_status: "linked" } }));
    });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("button", { name: "+ New WOD" }).click();
    await expect(page).toHaveURL(/\/admin\/schedule/);

    await publishFromCreator(page);

    expect(published).toBe(true);
    await expect.poll(() => linked).toEqual({ master_workout_id: draftId });
    // Still on the schedule: the editor never replaced the page.
    await expect(page).toHaveURL(/\/admin\/schedule$/);
  });

  test("a WOD that cannot be assigned is explained inside the class, never as «check the highlighted values»", async ({ page }) => {
    await asOwner(page);
    await page.route(`**/api/org/box1/admin/workouts/${draftId}/publish`, (route) =>
      route.fulfill(json({ workout: { ...sectionedDraft, status: "published" } })),
    );
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/workout", (route) =>
      route.fulfill(
        json(
          {
            code: "workout_not_assignable",
            error: "The workout cannot be assigned until it is complete (no_content)",
            params: { workout_id: draftId, title: "Legs", problem: "no_content" },
          },
          422,
        ),
      ),
    );

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("button", { name: "+ New WOD" }).click();
    await publishFromCreator(page);

    const notice = page.getByRole("alert").filter({ hasText: "WOD to link" });
    await expect(notice).toContainText("The WOD “Legs” has no content yet");
    await expect(page.getByText(/check the highlighted values/i)).toHaveCount(0);
  });

  test("the new-class form keeps what the coach typed and gets the new WOD", async ({ page }) => {
    await asOwner(page);
    await page.route("**/api/org/box1/schedule?**", (route) =>
      route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [] })),
    );
    await page.route(`**/api/org/box1/admin/workouts/${draftId}/publish`, (route) =>
      route.fulfill(json({ workout: { ...sectionedDraft, status: "published" } })),
    );

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: "+ Class" }).first().click();
    const form = page.getByRole("dialog");
    await form.getByLabel("Class name").fill("Friday Barbell");
    await form.getByRole("button", { name: "+ New WOD" }).click();
    await publishFromCreator(page);

    await expect(form.getByLabel("Class name")).toHaveValue("Friday Barbell");
    await expect(form.getByText("Legs")).toBeVisible();
  });
});
