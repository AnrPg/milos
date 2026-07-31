import { expect, test, type BrowserContext, type Route } from "@playwright/test";

const draftId = "11111111-1111-4111-8111-111111111111";
const admin = {
  id: "22222222-2222-4222-8222-222222222222",
  nickname: "Coach",
  role: "admin",
  avatar_url: null,
  preferred_locale: "en",
};

const source = `[workout]
dsl-version: 1
title: Quick Strength
type: strength

[section: untimed]
title: Main

[exercise: Deadlift]
sets: 3
reps: 5
load: 100 kg
[/exercise]
[/section]
[/workout]`;

const preview = {
  version: 1,
  workout: {
    title: "Quick Strength",
    type: "strength",
    is_team_workout: false,
    sections: [
      {
        name: "Main",
        scoreable: false,
        timer_config: { type: "untimed" },
        exercises: [
          {
            item_type: "exercise",
            name: "Deadlift",
            sets: 3,
            prescription_value: 5,
            prescription_unit: "reps",
            load_value: 100,
            load_mode: "kg",
          },
        ],
      },
    ],
  },
  formatted_source: `${source}\n`,
  vocabulary: {
    version: 1,
    section_formats: ["untimed", "for_time", "amrap"],
    workout_parameters: ["dsl-version", "title", "type", "team"],
    exercise_parameters: ["sets", "reps", "load"],
    header_parameters: ["title", "subtitle"],
    note_markers: ["!note", "!coach-note", "!athlete-note"],
    section_parameters: { untimed: [] },
  },
};

test("coach can author Quick Text, preview it, and convert it to structured mode", async ({
  context,
  page,
}) => {
  const draftUpdates: Array<Record<string, unknown>> = [];
  await mockWorkoutApi(context, draftUpdates);

  await page.goto(`/admin/workouts/new?mode=quick-text&draft=${draftId}`);

  const editor = page.getByRole("textbox", { name: "Quick Text workout editor" });
  await expect(editor).toBeVisible();
  await editor.fill(source);

  await expect(page.getByText("Canonical preview ready")).toBeVisible();
  const canonicalPreview = page.getByRole("complementary");
  await expect(canonicalPreview.getByText("Quick Strength", { exact: true })).toBeVisible();
  await expect(canonicalPreview.getByText("Deadlift", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Beautify" }).click();
  await expect(editor).toContainText("load: 100 kg");

  await page.getByRole("button", { name: "Use in Structured mode" }).click();
  await expect
    .poll(() =>
      draftUpdates.some(
        (update) =>
          update.authoring_mode === "structured" &&
          Array.isArray(update.sections) &&
          update.dsl_source === source,
      ),
    )
    .toBe(true);
  await expect(page).toHaveURL(/mode=structured/);
});

async function mockWorkoutApi(
  context: BrowserContext,
  draftUpdates: Array<Record<string, unknown>>,
) {
  await context.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const method = route.request().method();

    if (path === "/api/auth/refresh") return json(route, { access_token: "test-token" });
    if (path === "/api/auth/me") return json(route, admin);
    if (path === "/api/theme") return json(route, {});
    if (path === "/api/threads/unread-count") return json(route, { unread_count: 0 });
    if (path.startsWith("/api/notifications")) {
      return json(route, { notifications: [], unread_count: 0 });
    }

    if (path === `/api/admin/workouts/${draftId}` && method === "GET") {
      return json(route, {
        workout: {
          id: draftId,
          status: "draft",
          title: "Quick Strength",
          type: "strength",
          available_scale_levels: [],
          sections: [],
          draft_data: { authoring_mode: "quick_text", dsl_source: source },
        },
      });
    }

    if (path === `/api/admin/workouts/${draftId}/draft` && method === "PATCH") {
      const update = route.request().postDataJSON() as Record<string, unknown>;
      draftUpdates.push(update);
      return json(route, { draft: { id: draftId, status: "draft" } });
    }

    if (path === "/api/admin/workouts/dsl/parse" && method === "POST") {
      return json(route, preview);
    }

    if (path === "/api/admin/scale-levels") return json(route, { scale_levels: [] });
    return json(route, {});
  });
}

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
}
