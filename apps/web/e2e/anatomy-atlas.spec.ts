import { expect, test, type Page, type Route } from "./support/test";

import { chromeArgs } from "../playwright.config";
import { requireWebgl, waitForFigure } from "./support/webgl";

// P3-M2 anatomy atlas (ADR-164): a member opens the atlas from the WOD goals
// sheet on a muscle, reads what it does, their own sets and the gym's
// exercises with videos, drills with the breadcrumb and the figure (3D
// through SwiftShader), and switches to the heat map. The API is stubbed;
// every other route answers an empty object. Set ATLAS_SHOTS_DIR to keep
// screenshots.

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
test.use({
  launchOptions: {
    ...(executablePath ? { executablePath } : {}),
    // The shared flags keep /dev/shm out of the GPU process, which crashes it on a CI runner.
    args: [...chromeArgs, "--use-gl=angle"],
  },
  // SwiftShader renders on the CPU, and at the phone's 2.6x density the figure
  // alone outlasted the 5-minute budget on the CI runner. The checks are about
  // the panel, framing, heat map and picking, not pixel density, so 1x.
  deviceScaleFactor: 1,
});
test.describe.configure({ timeout: 300_000 });

const SHOTS = process.env.ATLAS_SHOTS_DIR;
const shot = async (page: Page, name: string) => {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${test.info().project.name}-${name}.png` });
};

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const member = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function memberToken() {
  const payload = Buffer.from(
    JSON.stringify({ sub: member.id, role: member.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

function localToday() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}
function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

const fran = { id: "wod-1", title: "Fran", type: "crossfit", authoring_mode: "free_text", free_text_body: "21-15-9\nThrusters\nPull-ups", sections: [] };
const memberGoals = {
  workout_id: "wod-1",
  muscles: [
    { id: "quadriceps", role: "primary" },
    { id: "latissimus-dorsi", role: "primary" },
    { id: "glutes", role: "secondary" },
  ],
  qualities: ["stamina"],
  stimulus: null,
  taxonomy_version: 1,
  updated_at: "2026-10-21T08:00:00Z",
};

const atlas = (range: string, sessions = 6) => ({
  range,
  weeks: range === "1w" ? 1 : range === "12w" ? 12 : 4,
  from: "2026-09-24",
  to: "2026-10-21",
  taxonomy_version: 1,
  thresholds: { medium: 3, high: 8 },
  sessions,
  felt_entries: 2,
  exercises: { recognized: 9, unrecognized: 0 },
  nodes:
    sessions === 0
      ? []
      : [
          { id: "thighs", kind: "region", sets: 40, per_week: 10, level: "high", felt: 2, top_exercises: [] },
          {
            id: "quadriceps",
            kind: "group",
            sets: 34.5,
            per_week: 8.6,
            level: "high",
            felt: 2,
            top_exercises: [
              { exercise_ref: "back-squat", label: "Back Squat", sets: 20 },
              { exercise_ref: "thruster", label: "Thruster", sets: 12 },
            ],
          },
          { id: "rectus-femoris", kind: "head", sets: 34.5, per_week: 8.6, level: "high", felt: 0, top_exercises: [] },
          { id: "hamstrings", kind: "group", sets: 9, per_week: 2.3, level: "low", felt: 0, top_exercises: [] },
          { id: "upper-back", kind: "region", sets: 14, per_week: 3.5, level: "medium", felt: 0, top_exercises: [] },
          { id: "latissimus-dorsi", kind: "group", sets: 14, per_week: 3.5, level: "medium", felt: 1, top_exercises: [] },
        ],
});

const exercises = (nodeId: string) => ({
  node_id: nodeId,
  videos_included: true,
  exercises: [
    {
      exercise_ref: "back-squat",
      label: "Back Squat",
      role: "primary",
      videos: [{ id: "v-1", title: "Squat basics", video_url: "https://videos.example/squat", duration_minutes: 6 }],
    },
    { exercise_ref: "front-squat", label: "Front Squat", role: "primary", videos: [] },
    { exercise_ref: "romanian-deadlift", label: "Romanian Deadlift", role: "secondary", videos: [] },
  ],
});

async function stubMember(page: Page, options: { sessions?: number } = {}) {
  const atlasRequests: string[] = [];
  await page.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = tenantless(url.pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: memberToken(), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, member);
    if (path === "/api/memberships") {
      return json(route, [
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]);
    }
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [] });
    if (path === "/api/me/atlas") {
      const range = url.searchParams.get("range") ?? "4w";
      atlasRequests.push(range);
      return json(route, atlas(range, options.sessions));
    }
    const nodeMatch = /^\/api\/anatomy\/nodes\/([^/]+)\/exercises$/.exec(path);
    if (nodeMatch) return json(route, exercises(decodeURIComponent(nodeMatch[1])));
    if (path === "/api/schedule") {
      return json(route, {
        start_date: localToday(),
        end_date: localToday(),
        days: 7,
        class_types: [],
        slots: [
          {
            id: "slot-1",
            master_workout_id: "wod-1",
            name: "CrossFit",
            duration_minutes: 60,
            scheduled_at: todayAt(23),
            class_type_id: "ct-1",
            class_type: { id: "ct-1", name: "CrossFit" },
            capacity: 12,
            auto_approve: true,
            booking_timeout_minutes: 30,
            approved_booking_count: 4,
            spots_remaining: 8,
            workout: fran,
            current_user_booking: { id: "booking-1", user_id: member.id, status: "approved", inserted_at: todayAt(8) },
            bookings: [],
          },
        ],
      });
    }
    if (path === "/api/my-workouts") return json(route, { start_date: localToday(), end_date: localToday(), assignments: [] });
    if (path === "/api/executions") return json(route, { executions: [] });
    if (path === "/api/me/training-log/sources") return json(route, { classes: [], assignments: [], library_workouts: [] });
    if (/\/injury-warnings$/.test(path)) return json(route, { level: "none", warnings: [], warning_count: 0 });
    if (path === "/api/workouts/wod-1/goals") return json(route, { workout_id: "wod-1", goals: memberGoals });
    return json(route, {});
  });
  return atlasRequests;
}

test("the goals sheet opens the atlas on a muscle; the panel, breadcrumb, figure and heat map work", async ({ page }) => {
  await requireWebgl(page);
  const atlasRequests = await stubMember(page);
  await page.goto("/box");
  await page.getByTestId("wod-goals-strip").click();
  const sheet = page.getByRole("dialog", { name: "Workout goals" });
  await sheet.getByTestId("wod-goals-atlas-link").click();
  // The first visit compiles the route in the dev server.
  await expect(page).toHaveURL(/\/journal\/atlas\?node=quadriceps$/, { timeout: 60_000 });

  const panel = page.getByTestId("atlas-panel");
  await expect(panel.getByRole("heading", { name: "Quadriceps" })).toBeVisible();
  await expect(panel).toContainText("Straighten the knee");
  const sets = panel.getByTestId("atlas-your-sets");
  await expect(sets).toContainText("34.5 sets");
  await expect(sets).toContainText("High coverage");
  await expect(sets).toContainText("Mostly from: Back Squat and Thruster");
  await expect(sets).toContainText("You felt it in 2 workouts");
  const list = panel.getByTestId("atlas-exercises");
  await expect(list.getByRole("link", { name: "Video: Squat basics" })).toHaveAttribute("href", "https://videos.example/squat");
  await expect(list).toContainText("Romanian Deadlift");

  // The 3D figure loads and frames the muscle.
  const figure = page.getByTestId("atlas-figure").locator("[data-anatomy-status]");
  await waitForFigure(figure);
  await expect(figure).toHaveAttribute("data-anatomy-status", "ready");
  await expect(figure).toHaveAttribute("data-anatomy-framed", "quadriceps");
  await expect(figure).toHaveAttribute("aria-label", /Primary: Quadriceps/);
  await shot(page, "atlas-group");

  // A head, then up the breadcrumb.
  await panel.getByRole("button", { name: "Rectus femoris" }).click();
  await expect(panel.getByRole("heading", { name: "Rectus femoris" })).toBeVisible();
  await expect(page).toHaveURL(/node=rectus-femoris$/);
  const crumbs = panel.getByRole("navigation", { name: "Level" });
  await crumbs.getByRole("button", { name: "Thighs" }).click();
  await expect(panel.getByRole("heading", { name: "Thighs" })).toBeVisible();
  await expect(panel.getByRole("button", { name: /Hamstrings/ })).toContainText("9 sets");
  await crumbs.getByRole("button", { name: "Body" }).click();
  await expect(panel.getByRole("heading", { name: "Whole body" })).toBeVisible();
  // The figure animates only while on screen (below the panel on a phone).
  await figure.scrollIntoViewIfNeeded();
  await expect(figure).toHaveAttribute("data-anatomy-framed", "body", { timeout: 30_000 });

  // Heat map: the figure is painted by coverage level, with the legend and its caveat.
  await page.getByRole("radio", { name: "My coverage" }).click();
  await expect(figure).toHaveAttribute("aria-label", /High coverage: Quadriceps/);
  await expect(figure).toHaveAttribute("aria-label", /Medium coverage: Latissimus dorsi/);
  await expect(page.getByText("An indication of your training volume, not a target.")).toBeVisible();
  await page.getByRole("button", { name: "12 wks" }).click();
  await expect.poll(() => atlasRequests).toContain("12w");
  await shot(page, "atlas-heat");

  // A tap on the figure picks a muscle group.
  const canvas = figure.locator("canvas");
  await figure.scrollIntoViewIfNeeded();
  const box = (await canvas.boundingBox())!;
  await page.mouse.click(box.x + box.width * 0.21, box.y + box.height * 0.6);
  await expect(panel.getByRole("heading", { name: "Whole body" })).toBeHidden();
  await expect(panel.getByRole("navigation", { name: "Level" }).getByRole("button", { name: "Body" })).toBeVisible();
});

test("an empty period explains itself", async ({ page }) => {
  await stubMember(page, { sessions: 0 });
  await page.goto("/journal/atlas?node=hamstrings");
  const panel = page.getByTestId("atlas-panel");
  await expect(panel.getByRole("heading", { name: "Hamstrings" })).toBeVisible();
  await expect(panel.getByTestId("atlas-your-sets")).toContainText("No workouts in this period yet.");
  await panel.getByRole("navigation", { name: "Level" }).getByRole("button", { name: "Body" }).click();
  await expect(panel).toContainText("No workouts in this period yet.");
});
