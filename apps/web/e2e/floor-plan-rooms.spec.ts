import { expect, test, type Page, type Request, type Route } from "./support/test";

// ADR-290: what the floor plans grow into. The room of a class on the plan
// from the class details, the gym's switch and per-floor switches, room
// photos with the floating 🌐, cleaning points, the janitor's carousel and
// photos plus pins on the machine log. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGM4EaABRww4OQAsNg8BoqhHXQAAAABJRU5ErkJggg==", "base64");
const png = (name: string) => ({ name, mimeType: "image/png", buffer: PNG });

const rectangle = [
  [0.1, 0.1],
  [0.5, 0.1],
  [0.5, 0.5],
  [0.1, 0.5],
];
const studio = {
  id: "space-studio",
  name: "Studio",
  description: null,
  directions: "First floor, left",
  location_id: "loc-1",
  tasks: [],
  floor_plan_id: "plan-1",
  area: { points: rectangle },
  archived_at: null,
  unavailability: [],
};
const plan = (id: string, name: string, extra: Record<string, unknown> = {}) => ({
  id,
  location_id: "loc-1",
  name,
  media_id: `media-${id}`,
  sort_order: 0,
  image_url: null,
  width: 800,
  height: 600,
  shown_in_classes: true,
  ...extra,
});

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

/** Presigned uploads: reserve, PUT, complete. Returns the media ids handed out. */
async function stubUploads(page: Page, path: string) {
  const ids: string[] = [];
  await page.route(`**/api/org/box1/staff/${path}/uploads`, (route) => {
    const id = `${path.replace(/\W/g, "-")}-${ids.length + 1}`;
    ids.push(id);
    return route.fulfill(json({ media_id: id, upload_url: `/__upload/${id}`, required_headers: { "content-type": "image/png" }, max_bytes: 8_000_000, expires_in: 900 }));
  });
  await page.route("**/__upload/**", (route: Route) => route.fulfill({ status: 200, body: "" }));
  await page.route(`**/api/org/box1/staff/${path}/uploads/*/complete`, (route) => route.fulfill(json({ media: { status: "ready" } })));
  return ids;
}

const MANAGER = { manage_spaces: "all", edit_space_details: "all", set_space_unavailable: "all", view_spaces: "all", manage_schedule: "all", run_classes: "all" };

test.describe("The room of a class", () => {
  test("the class details open the room coloured on the floor plan with its photos", async ({ page }) => {
    await signIn(page, "owner", MANAGER);
    const startsAt = new Date(Date.now() + 2 * 3600_000);
    startsAt.setUTCMinutes(0, 0, 0);
    const slot = {
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
      space_id: "space-studio",
      space: { id: "space-studio", name: "Studio", viewable: true },
      bookings: [],
    };
    await page.route("**/api/org/box1/schedule?**", (route) =>
      route.fulfill(json({ class_types: [{ id: "ct", name: "CrossFit", archived_at: null }], locations: [], coaches: [], slots: [slot] })),
    );
    await page.route("**/api/org/box1/staff/members", (route) => route.fulfill(json({ staff: [] })));
    await page.route("**/api/org/box1/staff/spaces", (route) => route.fulfill(json({ spaces: [studio], floor_plans: [plan("plan-1", "First floor")], settings: { floor_plans_in_classes: true } })));
    await page.route("**/api/org/box1/schedule/slots/slot-1/space", (route) =>
      route.fulfill(
        json({
          space: { id: "space-studio", name: "Studio", description: null, directions: "First floor, left" },
          floor_plan: plan("plan-1", "First floor"),
          area: { points: rectangle },
          photos: [{ id: "ph1", space_id: "space-studio", media_id: "m1", caption: "Mirrors", public: false, sort_order: 0, url: "/__media/room.png", width: 4, height: 3 }],
        }),
      ),
    );
    await page.route("**/__media/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: PNG }));

    await page.goto("/admin/schedule");
    await page.getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByTestId("slot-space").click();

    const room = page.getByTestId("class-room");
    await expect(room.getByTestId("class-room-plan")).toBeVisible();
    await expect(room.getByTestId("plan-area-space-studio")).toHaveText("Studio");
    await expect(room.getByTestId("class-room-directions")).toHaveText("First floor, left");
    await expect(room.getByTestId("class-room-photos")).toBeVisible();
  });
});

test.describe("Settings › Spaces › floor plans in classes and room photos", () => {
  test("the gym switch, per-floor switches with two floors, a photo added and made public", async ({ page }) => {
    await signIn(page, "owner", MANAGER);
    let settings = { floor_plans_in_classes: false };
    const puts: unknown[] = [];
    const floorPatches: unknown[] = [];
    const photoPatches: unknown[] = [];
    let added: Record<string, unknown> | null = null;
    let photos: Record<string, unknown>[] = [];

    await page.route("**/api/org/box1/staff/spaces", (route) =>
      route.fulfill(json({ spaces: [studio], floor_plans: [plan("plan-1", "First floor"), plan("plan-2", "Basement")], settings })),
    );
    await page.route("**/api/org/box1/staff/space-settings", (route) => {
      settings = bodyOf(route.request());
      puts.push(settings);
      return route.fulfill(json({ settings }));
    });
    await page.route("**/api/org/box1/staff/floor-plans/plan-2", (route) => {
      floorPatches.push(bodyOf(route.request()));
      return route.fulfill(json({ floor_plan: plan("plan-2", "Basement", { shown_in_classes: false }) }));
    });
    await page.route("**/api/org/box1/staff/spaces/space-studio", (route) =>
      route.fulfill(json({ space: { ...studio, classes: [], equipment: [], photos, points: [] } })),
    );
    const ids = await stubUploads(page, "space-photos");
    await page.route("**/api/org/box1/staff/spaces/space-studio/photos", (route) => {
      added = bodyOf(route.request());
      photos = [{ id: "ph1", space_id: "space-studio", media_id: added!.media_id, caption: null, public: false, sort_order: 0, url: "/__media/room.png", width: 4, height: 3 }];
      return route.fulfill(json({ photo: photos[0] }, 201));
    });
    await page.route("**/api/org/box1/staff/space-photos/ph1", (route) => {
      const body = bodyOf(route.request());
      photoPatches.push(body);
      photos = [{ ...photos[0], ...body }];
      return route.fulfill(json({ photo: photos[0] }));
    });
    await page.route("**/__media/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: PNG }));

    await page.goto("/admin/spaces");
    // Off: no per-floor switches yet.
    await expect(page.getByTestId("spaces-loc-1-floors-in-classes")).toHaveCount(0);
    await page.getByTestId("plans-in-classes").click();
    await expect.poll(() => puts).toEqual([{ floor_plans_in_classes: true }]);

    const floors = page.getByTestId("spaces-loc-1-floors-in-classes");
    await expect(floors).toBeVisible();
    await expect(page.getByTestId("floor-in-classes-plan-1")).toBeChecked();
    await page.getByTestId("floor-in-classes-plan-2").click();
    await expect.poll(() => floorPatches).toEqual([{ shown_in_classes: false }]);

    // Room photos: start off the public page; the floating 🌐 turns one on.
    await page.getByTestId("plan-area-space-studio").click();
    const detail = page.getByTestId("space-detail");
    await detail.getByTestId("room-photo-file").setInputFiles(png("room.png"));
    await expect.poll(() => added?.media_id).toBe(ids[0]);
    const tile = detail.getByTestId("room-photo-ph1");
    await expect(tile).toHaveAttribute("data-public", "false");
    await tile.locator("img").hover();
    await detail.getByTestId("room-photo-public-ph1").click();
    await expect.poll(() => photoPatches).toEqual([{ public: true }]);
    await expect(tile).toHaveAttribute("data-public", "true");
  });

  test("front desk adds a cleaning point with a photo and what to clean", async ({ page }) => {
    await signIn(page, "front_desk", { view_spaces: "all", edit_space_details: "all" });
    let added: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/staff/spaces", (route) => route.fulfill(json({ spaces: [studio], floor_plans: [plan("plan-1", "First floor")], settings: { floor_plans_in_classes: false } })));
    await page.route("**/api/org/box1/staff/spaces/space-studio", (route) =>
      route.fulfill(json({ space: { ...studio, classes: [], equipment: [], photos: [], points: [] } })),
    );
    const ids = await stubUploads(page, "cleaning-photos");
    await page.route("**/api/org/box1/staff/spaces/space-studio/cleaning-points", (route) => {
      added = bodyOf(route.request());
      return route.fulfill(json({ point: { id: "pt1", space_id: "space-studio", media_id: added!.media_id, instruction: added!.instruction, sort_order: 0, url: null } }, 201));
    });

    await page.goto("/admin/spaces");
    // Front desk does not switch the floor plans on for classes.
    await expect(page.getByTestId("plans-in-classes")).toHaveCount(0);
    await page.getByTestId("plan-area-space-studio").click();
    await page.getByTestId("cleaning-point-add").click();
    await page.getByTestId("cleaning-point-file").setInputFiles(png("drains.png"));
    await page.getByTestId("cleaning-point-instruction").fill("Drains and the grate");
    await page.getByTestId("cleaning-point-save").click();

    await expect.poll(() => added?.instruction).toBe("Drains and the grate");
    expect(added).toEqual({ media_id: ids[0], instruction: "Drains and the grate" });
  });
});

test.describe("Cleaning › the visual checklist", () => {
  test("the janitor answers each point; not cleaned needs a note; finishing sends the answers", async ({ page }) => {
    await signIn(page, "janitor", { record_cleaning: "all" });
    let finished: Record<string, unknown> | null = null;
    const points = [
      { id: "p1", space_id: "showers", media_id: "m1", instruction: "Drains", sort_order: 0, url: "/__media/p1.png" },
      { id: "p2", space_id: "showers", media_id: "m2", instruction: "Mirrors", sort_order: 1, url: "/__media/p2.png" },
    ];
    await page.route("**/__media/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: PNG }));
    await page.route("**/api/org/box1/staff/cleaning/areas", (route) =>
      route.fulfill(json({ areas: [{ id: "showers", name: "Showers", location_id: null, tasks: [], archived_at: null, last_cleaned_at: null, floor_plan_id: null, area: null, points }] })),
    );
    await page.route("**/api/org/box1/staff/cleaning/entries", (route) =>
      route.fulfill(
        json({ entries: [{ id: "e1", area_id: "showers", user_id: "user-1", nickname: "Olga", started_at: new Date().toISOString(), finished_at: null, tasks_done: [], note: null }] }),
      ),
    );
    await page.route("**/api/org/box1/staff/cleaning/today", (route) => route.fulfill(json({ date: "", due: [], open_entries: [], floor_plans: [] })));
    await page.route("**/api/org/box1/staff/cleaning/entries/e1/finish", (route) => {
      finished = bodyOf(route.request());
      return route.fulfill(json({ entry: { id: "e1", area_id: "showers", started_at: new Date().toISOString(), finished_at: new Date().toISOString(), tasks_done: [], point_results: [] } }));
    });

    await page.goto("/admin/cleaning");
    const carousel = page.getByTestId("cleaning-carousel");
    await expect(carousel.getByTestId("cleaning-carousel-instruction")).toHaveText("Drains");
    await expect(page.getByTestId("cleaning-finish")).toBeDisabled();

    await carousel.getByTestId("cleaning-point-cleaned").click();
    await expect(carousel.getByTestId("cleaning-carousel-instruction")).toHaveText("Mirrors");
    await carousel.getByTestId("cleaning-point-not-cleaned").click();
    await expect(page.getByTestId("cleaning-finish")).toBeDisabled();
    await carousel.getByTestId("cleaning-point-note").fill("Out of spray");
    await page.getByTestId("cleaning-finish").click();

    await expect.poll(() => finished?.point_results).toEqual([
      { point_id: "p1", status: "cleaned", note: null, after_media_id: null },
      { point_id: "p2", status: "not_cleaned", note: "Out of spray", after_media_id: null },
    ]);
  });
});

test.describe("Equipment › photos and the pin on the plan", () => {
  test("a log line takes photos; under the log the plan shows where the machine stands", async ({ page }) => {
    await signIn(page, "front_desk", { manage_inventory: "all", view_spaces: "all" });
    let logged: Record<string, unknown> | null = null;
    const rower = {
      id: "m1",
      name: "Rower",
      category: "training",
      status: "out_of_order",
      quantity: 1,
      archived_at: null,
      service_due: false,
      next_service_on: null,
      placements: [{ space_id: "space-studio", quantity: 1, positions: [[0.3, 0.3]] }],
      unassigned: 0,
    };
    await page.route("**/__media/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: PNG }));
    await page.route("**/api/org/box1/staff/inventory/machines", (route) => route.fulfill(json({ machines: [rower] })));
    await page.route("**/api/org/box1/staff/spaces", (route) => route.fulfill(json({ spaces: [studio], floor_plans: [plan("plan-1", "First floor")], settings: { floor_plans_in_classes: false } })));
    await page.route("**/api/org/box1/staff/inventory/machines/m1/events", (route) => {
      if (route.request().method() === "POST") {
        logged = bodyOf(route.request());
        return route.fulfill(json({ machine: rower, event: { id: "ev1", kind: logged!.kind, occurred_at: new Date().toISOString(), photos: [] } }, 201));
      }
      return route.fulfill(
        json({
          events: [{ id: "ev0", kind: "out_of_order", occurred_at: new Date().toISOString(), body: "Chain snapped", photos: [{ id: "ph0", url: "/__media/chain.png" }] }],
          places: [{ space_id: "space-studio", space_name: "Studio", quantity: 1, positions: [[0.3, 0.3]], area: { points: rectangle }, floor_plan: plan("plan-1", "First floor") }],
        }),
      );
    });
    const ids = await stubUploads(page, "inventory/machine-photos");

    await page.goto("/admin/inventory");
    await page.getByRole("button", { name: /Rower/ }).click();
    await expect(page.getByTestId("event-photos-ev0")).toBeVisible();
    const places = page.getByTestId("machine-places");
    await expect(places.getByTestId("machine-place-space-studio")).toBeVisible();
    await expect(places.getByTestId("plan-pin-space-studio-0")).toBeVisible();

    await page.getByRole("button", { name: /Add note/ }).click();
    await page.getByTestId("machine-photo-file").setInputFiles([png("a.png"), png("b.png")]);
    await expect.poll(() => ids.length).toBe(2);
    await page.getByRole("button", { name: "Save" }).click();
    await expect.poll(() => logged?.media_ids).toEqual(ids);
  });
});
