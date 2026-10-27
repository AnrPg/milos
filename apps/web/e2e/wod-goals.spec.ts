import { expect, test, type Page, type Route } from "./support/test";

import { chooseOption } from "./support/select";

// P3-M1 WOD goals (ADR-163): the coach sets goals in the free-text editor,
// a member sees the goals strip on Box and opens its sheet, and the finish
// wizard's «Τι ένιωσες;» step saves what was felt. The API is stubbed; every
// other route answers an empty object. Set WOD_GOALS_SHOTS_DIR to keep
// screenshots of the new screens.

const SHOTS = process.env.WOD_GOALS_SHOTS_DIR;
const shot = async (page: Page, name: string) => {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${test.info().project.name}-${name}.png` });
};

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const muscles = [
  { id: "quadriceps", role: "primary" },
  { id: "latissimus-dorsi", role: "primary" },
  { id: "glutes", role: "secondary" },
  { id: "erector-spinae", role: "stabilizer" },
];
const memberGoals = {
  workout_id: "wod-1",
  muscles,
  qualities: ["stamina", "power"],
  stimulus: "fast, 3–7′, unbroken thrusters",
  taxonomy_version: 1,
  updated_at: "2026-10-21T08:00:00Z",
};

function localToday() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}
function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

// ── Coach ────────────────────────────────────────────────────────────────────

const draftId = "11111111-1111-4111-8111-111111111111";
const admin = { id: "22222222-2222-4222-8222-222222222222", nickname: "Coach", role: "admin", avatar_url: null, preferred_locale: "en" };
const adminMembership = {
  id: "33333333-3333-4333-8333-333333333333",
  role: "admin",
  organization: { id: "44444444-4444-4444-8444-444444444444", name: "Demo Gym", slug: "demo-gym", settings: {} },
};

function staffGoals(saved: boolean, goals: Record<string, unknown> = {}) {
  const suggestion = muscles.slice(0, 3);
  return {
    goals: {
      workout_id: draftId,
      saved,
      muscles: suggestion,
      qualities: ["stamina"],
      stimulus: null,
      visible_to_members: false,
      source: saved ? "edited" : "suggested",
      taxonomy_version: 1,
      updated_by_id: null,
      updated_at: null,
      ...goals,
    },
    suggestion: { muscles: suggestion, qualities: ["stamina"], matched_exercises: 2, unmatched_exercises: 0, taxonomy_version: 1 },
  };
}

test("coach shows goals to members and edits them on the chips and in the picker list", async ({ context, page }) => {
  const puts: Array<Record<string, unknown>> = [];
  await context.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (path === "/api/auth/refresh") return json(route, { access_token: "test-token" });
    if (path === "/api/auth/me") return json(route, admin);
    if (path === "/api/memberships") return json(route, [adminMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === `/api/admin/workouts/${draftId}` && method === "GET") {
      const body = "21-15-9\nThrusters 43/30 kg\nPull-ups";
      return json(route, {
        workout: {
          id: draftId,
          status: "draft",
          title: "Fran",
          type: "crossfit",
          authoring_mode: "free_text",
          free_text_body: body,
          available_scale_levels: [],
          sections: [],
          draft_data: { authoring_mode: "free_text", free_text_body: body },
        },
      });
    }
    if (path === `/api/admin/workouts/${draftId}/draft`) return json(route, { draft: { id: draftId, status: "draft", dsl_source_revision: 1 } });
    if (path === `/api/admin/workouts/${draftId}/goals`) {
      if (method === "PUT") {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        puts.push(body);
        return json(route, staffGoals(true, { ...body, visible_to_members: body.visible_to_members }));
      }
      return json(route, puts.length ? staffGoals(true, puts.at(-1)) : staffGoals(false));
    }
    if (path === `/api/admin/workouts/${draftId}/goal-feedback-summary`) {
      return json(route, {
        workout_id: draftId,
        entries: 12,
        shown: true,
        felt_muscles: [{ id: "latissimus-dorsi", count: 9 }, { id: "quadriceps", count: 7 }],
        felt_qualities: [{ id: "stamina", count: 5 }],
        goals_not_felt: ["glutes"],
      });
    }
    if (path === "/api/admin/scale-levels") return json(route, { scale_levels: [] });
    if (path === "/api/admin/workout-folders") return json(route, { folders: [] });
    return json(route, {});
  });

  await page.goto(`/admin/workouts/new?mode=free-text&draft=${draftId}`);
  await page.getByRole("tab", { name: "Goals", exact: true }).click();
  const panel = page.getByTestId("wod-goals-panel");
  await expect(panel.getByText("Suggested from 2 exercises")).toBeVisible();
  await expect(panel.getByText("Suggestion · not saved yet")).toBeVisible();
  const totals = panel.getByRole("region", { name: "What they felt" });
  await expect(totals).toContainText("12 entries");
  await expect(totals).toContainText("Latissimus dorsi9");
  await expect(totals).toContainText("Goals nobody felt: Glutes");

  await panel.getByRole("checkbox", { name: "Show goals to members" }).check();
  await panel.getByRole("button", { name: "Quadriceps, Primary. Tap to change the role." }).click();
  await expect(panel.getByRole("button", { name: "Quadriceps, Secondary. Tap to change the role." })).toBeVisible();
  await panel.getByRole("button", { name: "heavy", exact: true }).click();
  await expect.poll(() => puts.at(-1)?.visible_to_members).toBe(true);
  await expect(panel.getByText("Saved")).toBeVisible();
  await shot(page, "coach-panel");

  await panel.getByRole("button", { name: "Edit on the body" }).click();
  const picker = page.getByRole("dialog", { name: "Target muscles" });
  await expect(picker).toBeVisible();
  await shot(page, "picker-body");
  await picker.getByRole("radio", { name: "List" }).click();
  await picker.getByRole("searchbox", { name: "Search muscles" }).fill("hamstr");
  await chooseOption(page, picker.getByRole("combobox", { name: "Role: Hamstrings" }), "primary");
  await shot(page, "picker-list");
  await picker.getByRole("button", { name: "Done" }).click();
  await expect(picker).toBeHidden();

  await expect
    .poll(() => puts.at(-1))
    .toEqual({
      muscles: [
        { id: "quadriceps", role: "secondary" },
        { id: "latissimus-dorsi", role: "primary" },
        { id: "glutes", role: "secondary" },
        { id: "hamstrings", role: "primary" },
      ],
      qualities: ["stamina"],
      stimulus: "heavy",
      visible_to_members: true,
    });
  await expect(panel.getByRole("button", { name: "Reset to suggestion" })).toBeEnabled();
});

// ── Member ───────────────────────────────────────────────────────────────────

const member = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
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

const fran = { id: "wod-1", title: "Fran", type: "crossfit", authoring_mode: "free_text", free_text_body: "21-15-9\nThrusters 43/30 kg\nPull-ups", sections: [] };

async function stubMember(page: Page, extra: (route: Route, path: string, method: string) => Promise<void> | null = () => null) {
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const handled = extra(route, path, method);
    if (handled) return handled;
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
}

test.describe("member", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("sees the goals strip in today's workout card and opens the goals sheet", async ({ page }) => {
    await stubMember(page);
    await page.goto("/box");
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();

    const strip = page.getByTestId("wod-goals-strip");
    await expect(strip).toContainText("Goals: Quadriceps and Latissimus dorsi");
    await expect(strip).toContainText("Stamina");
    await expect(strip).toContainText("fast, 3–7′, unbroken thrusters");
    await shot(page, "box-strip");

    await strip.click();
    const sheet = page.getByRole("dialog", { name: "Workout goals" });
    await expect(sheet).toContainText("Erector spinae");
    await expect(sheet).toContainText("Stabilizing");
    await shot(page, "goals-sheet");
    // The header × and the footer button both close it.
    await sheet.getByRole("button", { name: "Close" }).first().click();
    await expect(sheet).toBeHidden();
  });

  test("the finish wizard's felt step saves what was felt", async ({ page }) => {
    const saved: unknown[] = [];
    await stubMember(page, (route, path, method) => {
      if (path === "/api/executions/exec-1") {
        return json(route, {
          execution: {
            id: "exec-1",
            master_workout_id: "wod-1",
            status: "in_progress",
            source: "class_booking",
            source_reference_id: "slot-1",
            workout: fran,
          },
        });
      }
      if (path === "/api/me/goal-feedback/execution/exec-1") {
        if (method === "PUT") {
          const body = route.request().postDataJSON() as { felt_muscles: string[]; felt_qualities: string[] };
          saved.push(body);
          return json(route, { entry_kind: "execution", entry_id: "exec-1", voided: false, goals: memberGoals, feedback: { ...body, updated_at: "2026-10-21T09:00:00Z" } });
        }
        return json(route, { entry_kind: "execution", entry_id: "exec-1", voided: false, goals: memberGoals, feedback: null });
      }
      return null;
    });

    await page.goto("/workouts/exec-1/execute");
    await expect(page).toHaveURL(/\/workouts\/free-text\/execute/);
    await page.getByRole("button", { name: "Done", exact: true }).click();
    // No scored sections → Next; then the comments step → Skip.
    await page.getByRole("button", { name: "Next →" }).click();
    await page.getByRole("button", { name: "Skip →" }).click();

    const step = page.getByTestId("felt-step");
    await expect(step.getByRole("heading", { name: "How did it feel?" })).toBeVisible();
    await step.getByRole("button", { name: "Glutes", exact: true }).click();
    await step.getByRole("button", { name: "Power", exact: true }).click();
    await expect(step.getByRole("button", { name: "Glutes", exact: true })).toHaveAttribute("aria-pressed", "true");
    await shot(page, "felt-step");
    await step.getByRole("button", { name: "Save", exact: true }).click();

    await expect(page.getByText("Ready to save?")).toBeVisible();
    expect(saved).toEqual([{ felt_muscles: ["glutes"], felt_qualities: ["power"] }]);
  });
});
