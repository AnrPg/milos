import { expect, test, type Page } from "./support/test";

// ADR-230: a WOD for a whole day. Staff set it from the strip under a day's
// header; every class of the day follows it unless it has its own WOD, and a
// class's sheet says where its WOD comes from. The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const staff = [{ user_id: "owner-1", nickname: "Olga", role: "owner", roles: ["owner", "coach"] }];

// Tomorrow on the gym's (UTC) clock, so every class is in the future.
const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
const fran = { id: "w-fran", title: "Fran", type: "crossfit", icon: null };
const grace = { id: "w-grace", title: "Grace", type: "crossfit", icon: null };

const rule = {
  id: "rule-1",
  local_date: tomorrow,
  class_type_id: null,
  location_id: null,
  master_workout_id: "w-fran-day",
  workout: { id: "w-fran-day", title: "Fran", type: "crossfit" },
};

type Slot = ReturnType<typeof slot>;

const slot = (id: string, hour: string, attrs: Record<string, unknown> = {}) => ({
  id,
  class_series_id: null,
  master_workout_id: null as string | null,
  day_workout_id: null as string | null,
  workout_source: null as string | null,
  published: false,
  workout_status: "missing",
  name: `CrossFit ${hour}`,
  duration_minutes: 60,
  scheduled_at: `${tomorrow}T${hour}:00:00.000Z`,
  class_type_id: "crossfit",
  class_type: { id: "crossfit", name: "CrossFit", slug: "crossfit", kind: "class" },
  capacity: 12,
  auto_approve: true,
  booking_timeout_minutes: 30,
  approved_booking_count: 0,
  spots_remaining: 12,
  workout: null as { id: string; title: string; sections: unknown[]; content: unknown[] } | null,
  coach_user_id: null,
  location_id: null,
  bookings: [],
  ...attrs,
});

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
    capabilities: { manage_schedule: "all", run_classes: "all", manage_workouts: "all" },
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
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
  await page.route("**/api/org/box1/admin/workouts/choices/suggested?**", (route) =>
    route.fulfill(json({ same_day: [], recent: [fran, grace], newest: [fran, grace] })),
  );
}

/** The schedule answers whatever `state` holds when it is asked. */
async function stubSchedule(page: Page, state: { slots: Slot[]; dayWorkouts: (typeof rule)[] }) {
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(
      json({
        class_types: [{ id: "crossfit", name: "CrossFit", archived_at: null, kind: "class" }],
        locations: [],
        coaches: [],
        day_workouts: state.dayWorkouts,
        slots: state.slots,
      }),
    ),
  );
}

/** The (only) class card of the day. */
const classCard = (page: Page) => page.getByRole("button").filter({ hasText: "0/12" }).first();

async function openTomorrow(page: Page) {
  await page.goto("/admin/schedule");
  await page.getByRole("button", { name: "Day view", exact: true }).click();
  await page.getByRole("button", { name: "Next", exact: true }).click();
  await expect(classCard(page)).toBeVisible();
}

test.describe("Schedule › day WOD", () => {
  test("staff set a WOD for the whole day and see what it changes first", async ({ page }) => {
    await asOwner(page);
    const state = { slots: [slot("s1", "07"), slot("s2", "18")], dayWorkouts: [] as (typeof rule)[] };
    await stubSchedule(page, state);

    const previews: unknown[] = [];
    await page.route("**/api/org/box1/admin/schedule/day-workouts/preview", (route) => {
      previews.push(route.request().postDataJSON());
      return route.fulfill(
        json({
          inherit: [{ id: "s1", name: "CrossFit 07", scheduled_at: `${tomorrow}T07:00:00.000Z`, class_type_name: "CrossFit" }],
          own: [{ id: "s2", name: "CrossFit 18", scheduled_at: `${tomorrow}T18:00:00.000Z`, class_type_name: "CrossFit" }],
          started: [],
        }),
      );
    });

    let saved: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/day-workouts", (route) => {
      if (route.request().method() !== "PUT") return route.fallback();
      saved = route.request().postDataJSON();
      // The day's classes follow it from now on.
      state.dayWorkouts = [rule];
      state.slots = state.slots.map((item) =>
        item.id === "s1"
          ? { ...item, master_workout_id: "w-fran-day", day_workout_id: "rule-1", workout_source: "day", published: true, workout_status: "linked", workout: { id: "w-fran-day", title: "Fran", sections: [], content: [] } }
          : item,
      );
      return route.fulfill(json({ day_workouts: [rule], changed_count: 1 }));
    });

    await openTomorrow(page);
    await page.getByTestId(`day-wod-add-${tomorrow}`).click();

    const dialog = page.getByTestId("day-wod-dialog");
    await expect(dialog.getByRole("heading", { name: "Day WOD" })).toBeVisible();
    await dialog.getByRole("button", { name: "Use Fran" }).click();

    // What saving would change: one class takes it, one keeps its own.
    await expect(dialog.getByTestId("day-wod-preview")).toContainText("1 class takes it.");
    await expect(dialog.getByTestId("day-wod-preview")).toContainText("1 class keeps its own WOD:");
    await dialog.getByLabel("Give them the day WOD too").check();
    expect(previews.at(-1)).toMatchObject({ date: tomorrow, master_workout_id: "w-fran", class_type_ids: [] });

    await dialog.getByTestId("day-wod-save").click();
    await expect(dialog).toHaveCount(0);
    expect(saved).toMatchObject({ date: tomorrow, master_workout_id: "w-fran", class_type_ids: [], replace_own: true });

    await expect(page.getByTestId(`day-wod-${tomorrow}`)).toContainText("Fran");

    // The class's sheet says its WOD comes from the day.
    await classCard(page).click();
    await expect(page.getByTestId("class-day-wod-note")).toContainText("From the day WOD; it changes with it.");
  });

  test("a day WOD for chosen class types needs at least one type", async ({ page }) => {
    await asOwner(page);
    await stubSchedule(page, { slots: [slot("s1", "07")], dayWorkouts: [] });

    await openTomorrow(page);
    await page.getByTestId(`day-wod-add-${tomorrow}`).click();
    const dialog = page.getByTestId("day-wod-dialog");
    await dialog.getByRole("button", { name: "Use Fran" }).click();
    await dialog.getByRole("radio", { name: "Chosen class types" }).click();

    await expect(dialog.getByText("Choose at least one class type.")).toBeVisible();
    await expect(dialog.getByTestId("day-wod-save")).toBeDisabled();

    await dialog.getByTestId("day-wod-types").getByRole("button", { name: "CrossFit" }).click();
    await expect(dialog.getByTestId("day-wod-save")).toBeEnabled();
  });

  test("a class with its own WOD goes back to the day's WOD in one tap", async ({ page }) => {
    await asOwner(page);
    const own = slot("s1", "07", {
      master_workout_id: "w-grace",
      workout_source: "class",
      published: true,
      workout_status: "linked",
      workout: { id: "w-grace", title: "Grace", sections: [], content: [] },
    });
    const state = { slots: [own], dayWorkouts: [rule] };
    await stubSchedule(page, state);

    let followed = false;
    await page.route("**/api/org/box1/admin/schedule/slots/s1/day-workout", (route) => {
      followed = true;
      state.slots = [{ ...own, master_workout_id: "w-fran-day", day_workout_id: "rule-1", workout_source: "day", workout: { id: "w-fran-day", title: "Fran", sections: [], content: [] } }];
      return route.fulfill(json({ slot: state.slots[0] }));
    });

    await openTomorrow(page);
    await classCard(page).click();

    const note = page.getByTestId("class-day-wod-note");
    await expect(note).toContainText("Its own WOD (the day's is «Fran»).");
    await note.getByRole("button", { name: "Back to the day WOD" }).click();

    await expect.poll(() => followed).toBe(true);
    await expect(page.getByTestId("class-day-wod-note")).toContainText("From the day WOD");
  });

  test("removing a day WOD says how many classes followed it", async ({ page }) => {
    await asOwner(page);
    const inherited = slot("s1", "07", {
      master_workout_id: "w-fran-day",
      day_workout_id: "rule-1",
      workout_source: "day",
      published: true,
      workout_status: "linked",
      workout: { id: "w-fran-day", title: "Fran", sections: [], content: [] },
    });
    const state = { slots: [inherited], dayWorkouts: [rule] };
    await stubSchedule(page, state);

    let removed = false;
    await page.route("**/api/org/box1/admin/schedule/day-workouts/rule-1", (route) => {
      removed = route.request().method() === "DELETE";
      state.dayWorkouts = [];
      state.slots = [slot("s1", "07")];
      return route.fulfill(json({ day_workout: rule, changed_count: 1 }));
    });

    await openTomorrow(page);
    await page.getByTestId(`day-wod-${tomorrow}`).click();

    const list = page.getByTestId("day-wod-list");
    await expect(list).toContainText("All classes");
    await expect(list).toContainText("1 class follows it");
    await list.getByRole("button", { name: "Remove" }).click();
    await expect(list).toContainText("Remove it? The 1 class that took it falls back to a broader day WOD, or has none.");
    await list.getByRole("button", { name: "Yes, remove" }).click();

    await expect.poll(() => removed).toBe(true);
    await expect(page.getByTestId("day-wod-dialog")).toHaveCount(0);
    await expect(page.getByTestId(`day-wod-add-${tomorrow}`)).toBeVisible();
  });
});
