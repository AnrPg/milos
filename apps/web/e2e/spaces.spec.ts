import { expect, test, type Page, type Request } from "./support/test";
import { chooseDate, chooseOption } from "./support/select";

// ADR-202: the spaces of each branch (Ρυθμίσεις › Χώροι), the space of a
// class, the cleaning staff's «Σήμερα» list and where each machine stands.
// The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const dayKey = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);

const rectangle = [
  [0.1, 0.1],
  [0.5, 0.1],
  [0.5, 0.5],
  [0.1, 0.5],
];

const mats = {
  id: "space-mats",
  name: "Mats area",
  description: "The big room with the rig",
  directions: "Ground floor, left",
  location_id: "loc-1",
  tasks: ["Mop"],
  floor_plan_id: "plan-1",
  area: { points: rectangle },
  archived_at: null,
  unavailability: [],
};
const mainFloor = { ...mats, id: "space-gym", name: "Main floor", location_id: null, floor_plan_id: null, area: null, description: null };
const kifisiaRoom = { ...mats, id: "space-k", name: "Kifisia room", floor_plan_id: null, area: null };
const plan = { id: "plan-1", location_id: "loc-1", name: "Ground floor", media_id: "media-1", sort_order: 0, image_url: null, width: 800, height: 600 };

async function signIn(page: Page, role: string, capabilities: Record<string, string>) {
  const user = {
    id: "user-1",
    nickname: "Olga",
    role: "member",
    email: "staff@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role,
    roles: [role],
    capabilities,
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
  await page.route("**/api/org/box1/admin/locations", (route) =>
    route.fulfill(json({ locations: [{ id: "loc-1", name: "Kifisia", address: null, archived_at: null }] })),
  );
}

const MANAGER = {
  manage_spaces: "all",
  edit_space_details: "all",
  set_space_unavailable: "all",
  view_spaces: "all",
  manage_schedule: "all",
  run_classes: "all",
};

test.describe("Settings › Spaces", () => {
  test("lists the spaces of each branch on its floor plan and adds one", async ({ page }) => {
    await signIn(page, "owner", MANAGER);
    let created: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/staff/spaces", (route) => {
      if (route.request().method() === "POST") {
        created = bodyOf(route.request());
        return route.fulfill(json({ space: { ...mats, id: "space-rig", name: "Rig", floor_plan_id: null, area: null } }, 201));
      }
      return route.fulfill(json({ spaces: [mats, mainFloor], floor_plans: [plan] }));
    });

    await page.goto("/admin/spaces");
    await expect(page.getByRole("heading", { name: "Kifisia" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Whole box" })).toBeVisible();
    await expect(page.getByTestId("plan-area-space-mats")).toHaveText("Mats area");
    await expect(page.getByTestId("space-space-gym")).toContainText("Main floor");

    await page.getByTestId("space-add").click();
    const dialog = page.getByRole("dialog", { name: "Add space" });
    await dialog.getByTestId("space-name").fill("Rig");
    await chooseOption(page, dialog.getByTestId("space-branch"), "loc-1");
    await dialog.getByTestId("space-save").click();

    await expect.poll(() => created?.name).toBe("Rig");
    expect(created).toMatchObject({ location_id: "loc-1", floor_plan_id: null });
  });

  test("makes a space unavailable from–to with a reason and lists the classes there", async ({ page }) => {
    await signIn(page, "owner", MANAGER);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/staff/spaces", (route) => route.fulfill(json({ spaces: [mats], floor_plans: [plan] })));
    await page.route("**/api/org/box1/staff/spaces/space-mats/unavailability", (route) => {
      const body = bodyOf(route.request());
      sent = body;
      return route.fulfill(
        json(
          {
            unavailability: { id: "w1", space_id: "space-mats", starts_at: body.starts_at, ends_at: body.ends_at, reason: body.reason },
            affected_classes: [{ id: "c1", name: "Morning WOD", scheduled_at: `${dayKey(1)}T10:00:00Z`, duration_minutes: 60 }],
          },
          201,
        ),
      );
    });

    await page.goto("/admin/spaces");
    await page.getByTestId("space-space-mats").getByRole("button", { name: "Make unavailable" }).click();
    const dialog = page.getByTestId("space-unavailable-form");
    await chooseDate(page, dialog.getByTestId("unavailable-from"), dayKey(1));
    await chooseDate(page, dialog.getByTestId("unavailable-to"), dayKey(2));
    await dialog.getByTestId("unavailable-reason").fill("Floor repairs");
    await dialog.getByTestId("space-unavailable-save").click();

    await expect.poll(() => sent?.reason).toBe("Floor repairs");
    expect(sent).toMatchObject({ starts_at: `${dayKey(1)}T09:00:00.000Z`, ends_at: `${dayKey(2)}T09:00:00.000Z` });
    await expect(page.getByTestId("space-unavailable-result")).toContainText("1 class is already scheduled there then:");
    await expect(page.getByTestId("space-unavailable-result")).toContainText("Morning WOD");
  });

  test("tapping a space shows its upcoming classes and equipment", async ({ page }) => {
    await signIn(page, "front_desk", { view_spaces: "all", edit_space_details: "all", set_space_unavailable: "all" });
    await page.route("**/api/org/box1/staff/spaces", (route) => route.fulfill(json({ spaces: [mats], floor_plans: [plan] })));
    await page.route("**/api/org/box1/staff/spaces/space-mats", (route) =>
      route.fulfill(
        json({
          space: {
            ...mats,
            classes: [{ id: "c1", name: "Morning WOD", scheduled_at: `${dayKey(1)}T07:00:00Z`, duration_minutes: 60 }],
            equipment: [{ machine_id: "m1", name: "Rower", status: "working", quantity: 4 }],
          },
        }),
      ),
    );

    await page.goto("/admin/spaces");
    // Front desk edits the details and closures, but does not add, archive or draw.
    await expect(page.getByTestId("space-add")).toHaveCount(0);
    await expect(page.getByTestId("space-draw-space-mats")).toHaveCount(0);

    await page.getByTestId("plan-area-space-mats").click();
    const detail = page.getByTestId("space-detail");
    await expect(detail.getByTestId("space-detail-classes")).toContainText("Morning WOD");
    await expect(detail.getByTestId("space-detail-equipment")).toContainText("Rower");
    await expect(detail.getByTestId("space-detail-equipment")).toContainText("× 4");
    await expect(detail).toContainText("Ground floor, left");
  });
});

// In two hours: inside today's window in any zone except right before midnight.
const startsAt = new Date(Date.now() + 2 * 3600_000);
startsAt.setUTCMinutes(0, 0, 0);

const morningClass = {
  id: "slot-1",
  class_series_id: null,
  master_workout_id: null,
  name: "Morning WOD",
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
  space_id: null,
  space: null,
  bookings: [],
};

async function withSchedule(page: Page, slot: Record<string, unknown>) {
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [slot] })),
  );
  await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff: [] })));
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
  await page.route("**/api/org/box1/staff/spaces", (route) => route.fulfill(json({ spaces: [mainFloor, kifisiaRoom], floor_plans: [] })));
}

test.describe("Schedule › the space of a class", () => {
  test("the class popup shows the space and a clash with another class", async ({ page }) => {
    await signIn(page, "owner", MANAGER);
    await withSchedule(page, { ...morningClass, space_id: "space-gym", space: { id: "space-gym", name: "Main floor" }, space_overlap: true });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await expect(page.getByTestId("slot-space")).toHaveText("Space: Main floor");
    await expect(page.getByTestId("slot-space-overlap")).toBeVisible();
    await expect(page.getByTestId("slot-space-unavailable")).toHaveCount(0);
  });

  test("the class editor offers the spaces that fit its branch and saves the choice", async ({ page }) => {
    await signIn(page, "owner", MANAGER);
    await withSchedule(page, morningClass);
    let sent: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1", (route) => {
      sent = bodyOf(route.request());
      return route.fulfill(json({ slot: { ...morningClass, space_id: "space-gym" }, updated_count: 1 }));
    });

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("button", { name: "Edit slot" }).click();
    const dialog = page.getByRole("dialog", { name: "Edit scheduled class" });
    const select = dialog.getByTestId("class-space-select");
    await select.click();
    // A class with no branch takes only the gym-wide spaces.
    await expect(page.locator('[role="option"][data-value="space-gym"]')).toBeVisible();
    await expect(page.locator('[role="option"][data-value="space-k"]')).toHaveCount(0);
    await page.locator('[role="option"][data-value="space-gym"]').click();
    await expect(select).toHaveAttribute("data-value", "space-gym");
    await dialog.getByRole("button", { name: "Save changes" }).click();

    await expect.poll(() => sent?.space_id).toBe("space-gym");
  });
});

const janitor = { record_cleaning: "all", report_inventory: "all" };
const area = (id: string, name: string) => ({ id, name, location_id: null, tasks: [], archived_at: null, last_cleaned_at: null, floor_plan_id: null, area: null });
const due = (spaceId: string, name: string, extra: Record<string, unknown> = {}) => ({
  space_id: spaceId,
  name,
  location_id: null,
  tasks: [],
  floor_plan_id: null,
  area: null,
  times: ["07:00:00", "21:00:00"],
  comment: null,
  cleanings_due: 2,
  cleanings_done: 0,
  done: false,
  ...extra,
});

async function withCleaning(page: Page, today: Record<string, unknown>) {
  let started: Record<string, unknown> | null = null;
  await page.route("**/api/org/box1/staff/cleaning/areas", (route) => route.fulfill(json({ areas: [area("mats", "Mats area"), area("showers", "Showers")] })));
  await page.route("**/api/org/box1/staff/cleaning/entries", (route) => {
    if (route.request().method() === "POST") {
      const body = bodyOf(route.request());
      started = body;
      return route.fulfill(
        json({ entry: { id: "e1", area_id: body.area_id, user_id: "user-1", nickname: "Olga", started_at: new Date().toISOString(), finished_at: null, tasks_done: [], note: null } }, 201),
      );
    }
    return route.fulfill(json({ entries: [] }));
  });
  await page.route("**/api/org/box1/staff/cleaning/today", (route) => route.fulfill(json(today)));
  return () => started;
}

test.describe("Cleaning › Today", () => {
  test("the cleaning staff see what is due today in a list and start a space", async ({ page }) => {
    await signIn(page, "janitor", janitor);
    const started = await withCleaning(page, {
      date: dayKey(0),
      due: [due("mats", "Mats area", { comment: "Mop under the rig" }), due("showers", "Showers", { cleanings_done: 2, done: true })],
      open_entries: [],
      floor_plans: [],
    });

    await page.goto("/admin/cleaning");
    const list = page.getByTestId("cleaning-today-list");
    await expect(page.getByText("1 of 2 done")).toBeVisible();
    await expect(list.getByTestId("due-mats")).toHaveAttribute("data-status", "due");
    await expect(list.getByTestId("due-mats")).toContainText("07:00 · 21:00");
    await expect(list.getByTestId("due-mats")).toContainText("Mop under the rig");
    await expect(list.getByTestId("due-showers")).toHaveAttribute("data-status", "done");

    await list.getByTestId("due-mats").getByRole("button", { name: "Start cleaning" }).click();
    await expect.poll(() => started()?.area_id).toBe("mats");
  });

  test("on a floor plan the cleaning staff tap a space to start it", async ({ page }) => {
    await signIn(page, "janitor", janitor);
    const started = await withCleaning(page, {
      date: dayKey(0),
      due: [due("mats", "Mats area", { floor_plan_id: "plan-1", area: { points: rectangle } }), due("showers", "Showers")],
      open_entries: [],
      floor_plans: [plan],
    });

    await page.goto("/admin/cleaning");
    await expect(page.getByTestId("today-plan-plan-1")).toBeVisible();
    // A space that is not drawn on a plan stays in the plain list.
    await expect(page.getByTestId("cleaning-today-list").getByTestId("due-showers")).toBeVisible();

    await page.getByTestId("plan-area-mats").click();
    await expect.poll(() => started()?.area_id).toBe("mats");
  });
});

test.describe("Equipment › where it stands", () => {
  test("a machine shows its placement and the unassigned rest, and is placed in another space", async ({ page }) => {
    await signIn(page, "front_desk", { manage_inventory: "all", view_spaces: "all" });
    let sent: Record<string, unknown> | null = null;
    const treadmill = {
      id: "m1",
      name: "Treadmill",
      category: "training",
      status: "working",
      quantity: 6,
      archived_at: null,
      service_due: false,
      next_service_on: null,
      placements: [{ space_id: "space-cardio", quantity: 4 }],
      unassigned: 2,
    };
    await page.route("**/api/org/box1/staff/inventory/machines", (route) => route.fulfill(json({ machines: [treadmill] })));
    await page.route("**/api/org/box1/staff/inventory/machines/m1/events", (route) => route.fulfill(json({ events: [] })));
    await page.route("**/api/org/box1/staff/spaces", (route) =>
      route.fulfill(json({ spaces: [{ ...mainFloor, id: "space-cardio", name: "Cardio" }, { ...mainFloor, id: "space-up", name: "Upstairs" }], floor_plans: [] })),
    );
    await page.route("**/api/org/box1/staff/inventory/machines/m1/placements", (route) => {
      const body = bodyOf(route.request());
      sent = body;
      return route.fulfill(json({ machine_id: "m1", placements: body.placements, unassigned: 0 }));
    });

    await page.goto("/admin/inventory");
    await page.getByRole("button", { name: /Treadmill/ }).click();
    const placement = page.getByTestId("placement-m1");
    await expect(placement).toContainText("Cardio");
    await expect(placement.getByTestId("placement-unassigned-m1")).toHaveText("2 unassigned");

    await placement.getByTestId("placement-edit-m1").click();
    await placement.getByRole("button", { name: "Add a space" }).click();
    await chooseOption(page, placement.getByTestId("placement-space-1"), "space-up");
    await expect(placement.getByTestId("placement-quantity-1")).toHaveValue("2");
    await placement.getByTestId("placement-save-m1").click();

    await expect.poll(() => sent?.placements).toEqual([
      { space_id: "space-cardio", quantity: 4 },
      { space_id: "space-up", quantity: 2 },
    ]);
  });
});
