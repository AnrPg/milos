import { expect, type Locator, type Page, type Route } from "@playwright/test";

// Shared stubs and helpers for the structured WOD editor specs (ADR-270,
// `docs/plans/structured-wod-plan.md`). Every screen is reached through the
// test ids listed at the end of that plan; the API is stubbed and every route
// not listed answers an empty object. The coach and the member write Greek
// (ANR), so the specs run in Greek and read the canonical Greek terms.

export const draftId = "11111111-1111-4111-8111-111111111111";

export const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const admin = {
  id: "22222222-2222-4222-8222-222222222222",
  nickname: "Coach",
  role: "admin",
  avatar_url: null,
  preferred_locale: "el",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
};
const adminMembership = {
  id: "33333333-3333-4333-8333-333333333333",
  role: "admin",
  organization: { id: "44444444-4444-4444-8444-444444444444", name: "Demo Gym", slug: "demo-gym", settings: {} },
};

/** The exercise library the name suggestions read (the WOD manual's vocabulary). */
const exerciseCatalog = [
  "Back Squat",
  "Front Squat",
  "Bench Press",
  "Pull-up",
  "Wall Ball",
  "Burpee",
  "Thruster",
  "Row",
  "Walking Lunge",
  "Romanian Deadlift",
  "Deadlift",
].map((label) => ({ id: label.toLowerCase().replace(/[^a-z]+/g, "-"), label, aliases: [] }));

// ── Plans used by the view and execution specs ──────────────────────────────

/**
 * One Σετ section: a Bench Press + Pull-up superset (tempo 31X1 on the
 * press), Walking Lunge per side, 2 sets, and an interruption every 2:00 for
 * 5 Burpees.
 */
export const supersetPlan = {
  v: 1,
  flow: "sets",
  preset: null,
  params: { sets: "2", rest: "90″", intEvery: "2:00" },
  mods: { interrupt: true },
  blocks: [
    [
      { id: "row-bench", kind: "ex", name: "Bench Press", dose: "", load: "", extra: ["tempo"], cells: [{ d: "8", l: "60kg", tempo: "31X1" }], group: "g-1" },
      { id: "row-pull", kind: "ex", name: "Pull-up", dose: "", load: "", cells: [{ d: "6" }], group: "g-1" },
      { id: "row-lunge", kind: "ex", name: "Walking Lunge", dose: "", load: "", extra: ["side"], cells: [{ d: "10", l: "16kg" }], group: null },
    ],
  ],
  interrupt: [{ id: "row-burpee", kind: "ex", name: "Burpee", dose: "5", load: "", cells: [] }],
  structs: { "g-1": { kind: "superset" } },
  score: "none",
};

export function planWorkout(overrides: Record<string, unknown> = {}) {
  return {
    id: draftId,
    status: "draft",
    title: "Upper",
    type: "strength",
    authoring_mode: "structured_plan",
    free_text_body: null,
    dsl_source_revision: 3,
    available_scale_levels: [],
    sections: [{ id: "sec-1", name: "A", plan: supersetPlan, exercises: [] }],
    draft_data: { authoring_mode: "structured_plan" },
    ...overrides,
  };
}

function freeTextWorkout() {
  return {
    id: draftId,
    status: "draft",
    title: "",
    type: "crossfit",
    authoring_mode: "free_text",
    free_text_body: "",
    dsl_source_revision: 1,
    available_scale_levels: [],
    sections: [],
    draft_data: { authoring_mode: "free_text", free_text_body: "" },
  };
}

// ── Coach: the WOD editor ───────────────────────────────────────────────────

export type EditorServer = {
  workout: Record<string, unknown>;
  revision: number;
  /** Every draft save (PATCH …/draft) and publish body, in order. */
  saves: Array<Record<string, unknown>>;
};

export async function stubCoach(page: Page, workout: Record<string, unknown> = freeTextWorkout()): Promise<EditorServer> {
  const server: EditorServer = { workout, revision: Number(workout.dsl_source_revision ?? 1), saves: [] };
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (path === "/api/auth/refresh") return json(route, { access_token: "test-token" });
    if (path === "/api/auth/me") return json(route, admin);
    if (path === "/api/memberships") return json(route, [adminMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/workouts" && method === "POST") {
      return json(route, { draft: { id: draftId, status: "draft", authoring_mode: "free_text", dsl_source_revision: server.revision } }, 201);
    }
    if (path === `/api/admin/workouts/${draftId}` && method === "GET") return json(route, { workout: server.workout });
    if (path === `/api/admin/workouts/${draftId}/draft` && method === "PATCH") {
      const update = route.request().postDataJSON() as Record<string, unknown>;
      server.saves.push(update);
      server.revision += 1;
      return json(route, { draft: { id: draftId, status: "draft", authoring_mode: update.authoring_mode, dsl_source_revision: server.revision } });
    }
    if (path === `/api/admin/workouts/${draftId}/publish` && method === "POST") {
      const body = (route.request().postDataJSON() ?? {}) as Record<string, unknown>;
      server.saves.push(body);
      return json(route, { workout: { ...server.workout, ...body, status: "published" } });
    }
    if (path === "/api/admin/workouts/dsl/manual") {
      return json(route, { version: 1, markdown: "", templates: { workout: "", sections: {} }, vocabulary: { version: 1, exercise_catalog: exerciseCatalog } });
    }
    if (path === "/api/admin/workouts/authoring-settings") return json(route, { wod_assistant_enabled: true });
    if (path === `/api/admin/workouts/${draftId}/goals`) return json(route, { goals: null, suggestion: null });
    if (path === "/api/admin/scale-levels") return json(route, { scale_levels: [] });
    if (path === "/api/admin/workout-folders") return json(route, { folders: [] });
    if (path === "/api/admin/workouts" && method === "GET") return json(route, { workouts: [] });
    return json(route, {});
  });
  return server;
}

/** Opens the coach's draft in the WOD editor and switches it to Structured. */
export async function openStructuredEditor(page: Page) {
  await page.goto(`/admin/workouts/new?draft=${draftId}`);
  await switchAuthoring(page, "structured");
  await expect(page.getByTestId("plan-editor")).toBeVisible();
}

/**
 * Flips the free text / structured toggle. The toggle is either one switch
 * (`authoring-toggle` itself is the control) or a small group of choices.
 */
export async function switchAuthoring(page: Page, to: "structured" | "free") {
  const toggle = page.getByTestId("authoring-toggle");
  await expect(toggle).toBeVisible({ timeout: 15_000 });
  const name = to === "structured" ? /structured|δομημένο/i : /free text|ελεύθερο κείμενο|κείμενο/i;
  const choice = toggle.getByRole("tab", { name }).or(toggle.getByRole("radio", { name })).or(toggle.getByRole("button", { name }));
  if ((await choice.count()) > 0) await choice.first().click();
  else await toggle.click();
}

/** The open section's flow step: an empty section opens on it; otherwise «+ Ενότητα» (Shift+Enter) starts one. */
export async function flowInput(page: Page) {
  const input = page.getByTestId("plan-flow-input");
  if (!(await input.isVisible())) {
    const add = page.getByTestId("plan-editor").getByRole("button", { name: /ενότητα|section/i });
    if (await add.count()) await add.last().click();
    else await page.keyboard.press("Shift+Enter");
  }
  await expect(input).toBeVisible();
  await expect(input).toBeFocused();
  return input;
}

/** Picks a flow or preset with the keyboard (type, Enter) and lands on the next step. */
export async function pickFlow(page: Page, query: string) {
  const input = await flowInput(page);
  await input.pressSequentially(query);
  await input.press("Enter");
}

/** The input of a flow parameter, whether the test id sits on the input or on its label. */
export function paramInput(page: Page, key: string) {
  const id = `plan-param-${key}`;
  return page.locator(`input[data-testid="${id}"], [data-testid="${id}"] input`).first();
}

/** Replaces a wizard parameter with the keyboard. */
export async function typeParam(page: Page, key: string, value: string) {
  const input = paramInput(page, key);
  await input.focus();
  await input.press("ControlOrMeta+a");
  await input.pressSequentially(value);
  return input;
}

export async function expectStep(page: Page, step: "flow" | "time" | "exercises" | "score") {
  await expect
    .poll(() =>
      page.getByTestId(`plan-step-${step}`).evaluate((el) =>
        el.getAttribute("aria-current") === "step" ||
        el.getAttribute("aria-selected") === "true" ||
        el.getAttribute("data-active") === "true" ||
        el.getAttribute("aria-pressed") === "true",
      ),
    )
    .toBe(true);
}

// ── Rows and cells ──────────────────────────────────────────────────────────

/** Exercise rows of the open section, in order (not the ⋯ menu, which shares the prefix). */
export function rows(page: Page) {
  return page.locator('[data-testid^="plan-row-"]:not([data-testid="plan-row-menu"])');
}

export async function rowIds(page: Page): Promise<string[]> {
  const ids = await rows(page).evaluateAll((els) => els.map((el) => el.getAttribute("data-testid") ?? ""));
  return ids.map((id) => id.replace(/^plan-row-/, ""));
}

/** The exercise-name input of a row. */
export function nameInput(page: Page, rowId: string) {
  return page.getByTestId(`plan-row-${rowId}`).locator("input").first();
}

/** The element carrying `plan-cell-<row>-<col>-<key>` (the field's box). */
export function cell(page: Page, rowId: string, col: number, key: string) {
  return page.getByTestId(`plan-cell-${rowId}-${col}-${key}`);
}

/** The text input of a cell, whether the test id sits on the input or on its box. */
export function cellInput(page: Page, rowId: string, col: number, key: string) {
  const id = `plan-cell-${rowId}-${col}-${key}`;
  return page.locator(`input[data-testid="${id}"], [data-testid="${id}"] input`).first();
}

/** All columns of one value key in a row (sets or rounds). */
export function columns(page: Page, rowId: string, key: string) {
  return page.locator(`[data-testid^="plan-cell-${rowId}-"][data-testid$="-${key}"]`);
}

/**
 * Types an exercise name and presses Enter until a new row exists: the first
 * Enter may only take a fuzzy suggestion, the next one adds the row.
 */
export async function nameAndEnter(page: Page, name: string) {
  const before = await rows(page).count();
  await page.keyboard.type(name);
  await page.keyboard.press("Enter");
  if ((await rows(page).count()) === before) await page.keyboard.press("Enter");
  await expect(rows(page)).toHaveCount(before + 1);
}

/** Types a name and leaves a suggestion list closed, without adding a row. */
export async function typeName(page: Page, name: string) {
  await page.keyboard.type(name);
  const list = page.getByRole("listbox");
  if (await list.first().isVisible().catch(() => false)) await page.keyboard.press("Escape");
}

/** Whether an element (or the field box around it) is drawn in the theme's red. */
export async function isRed(target: Locator) {
  return target.evaluate((el) => {
    const probe = document.createElement("span");
    probe.style.color = "var(--red)";
    document.body.append(probe);
    const red = getComputedStyle(probe).color;
    probe.remove();
    const boxes = [el, el.parentElement, el.closest("[data-testid^='plan-cell-']")].filter(Boolean) as Element[];
    return boxes.some((box) => {
      const s = getComputedStyle(box);
      return [s.color, s.borderTopColor, s.borderBottomColor, s.outlineColor, s.boxShadow, s.backgroundColor].some((value) => value.includes(red));
    });
  });
}

/** No text field in the editor cuts its text off. */
export async function expectNoCroppedFields(page: Page) {
  const cropped = await page
    .getByTestId("plan-editor")
    .locator("input, textarea")
    .evaluateAll((els) =>
      els
        .filter((el) => (el as HTMLInputElement).offsetParent !== null && (el as HTMLInputElement).value)
        .filter((el) => el.scrollWidth > el.clientWidth + 1)
        .map((el) => `${el.getAttribute("aria-label") ?? el.getAttribute("data-testid") ?? el.tagName}: ${(el as HTMLInputElement).value}`),
    );
  expect(cropped).toEqual([]);
}

export async function expectNoHorizontalScroll(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
}

/** Visible pop-ups: suggestions, measure picker, row menu. */
export function openPopups(page: Page) {
  return page.locator('[role="listbox"]:visible, [role="menu"]:visible, [data-testid="plan-row-menu"]:visible');
}

/** A click on an empty spot of the page, away from every field and pop-up. */
export async function clickOutside(page: Page) {
  const box = await page.getByTestId("plan-editor").boundingBox();
  const viewport = page.viewportSize() ?? { width: 1280, height: 720 };
  await page.mouse.click(viewport.width - 4, Math.max(4, Math.min(viewport.height - 4, (box?.y ?? 0) - 8)));
}

// ── Member: the WOD view and execution ──────────────────────────────────────

const member = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
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

export const memberPlanWorkout = { ...planWorkout(), id: "wod-1", status: "published", title: "Upper" };

export async function stubMember(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  const workout = memberPlanWorkout;
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
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
    if (path === "/api/schedule") {
      return json(route, {
        start_date: localToday(),
        end_date: localToday(),
        days: 7,
        class_types: [],
        slots: [
          {
            id: "slot-1",
            master_workout_id: workout.id,
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
            workout,
            current_user_booking: { id: "booking-1", user_id: member.id, status: "approved", inserted_at: todayAt(8) },
            bookings: [],
          },
        ],
      });
    }
    if (path === "/api/my-workouts") return json(route, { start_date: localToday(), end_date: localToday(), assignments: [] });
    if (path === "/api/executions") return json(route, { executions: [] });
    if (path === "/api/executions/exec-1") {
      return json(route, {
        execution: {
          id: "exec-1",
          master_workout_id: workout.id,
          status: "in_progress",
          source: "class_booking",
          source_reference_id: "slot-1",
          scale_level_slug: null,
          lock_version: 1,
          workout,
        },
      });
    }
    if (path === `/api/workouts/${workout.id}`) return json(route, { workout });
    if (path === `/api/workouts/${workout.id}/timer-sequence`) return json(route, { segments: [] });
    if (path === "/api/me/training-log/sources") return json(route, { classes: [], assignments: [], library_workouts: [] });
    if (/\/injury-warnings$/.test(path)) return json(route, { level: "none", warnings: [], warning_count: 0 });
    return json(route, {});
  });
}
