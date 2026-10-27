import { expect, test, type BrowserContext, type Route } from "./support/test";

// Draft autosave in the WOD editors. The stub API checks revisions the way
// the server does (a save based on an old revision gets 409
// stale_dsl_revision), so these specs catch overlapping saves, saves sent
// before the draft loaded, and the plain-language notice for a real conflict.

const draftId = "11111111-1111-4111-8111-111111111111";
const admin = { id: "22222222-2222-4222-8222-222222222222", nickname: "Coach", role: "admin", avatar_url: null, preferred_locale: "en" };
const adminMembership = {
  id: "33333333-3333-4333-8333-333333333333",
  role: "admin",
  organization: { id: "44444444-4444-4444-8444-444444444444", name: "Demo Gym", slug: "demo-gym", settings: {} },
};

type DraftServer = {
  revision: number;
  title: string;
  body: string;
  authoringMode: "free_text" | "sectioned_text";
  /** How long each draft save takes. */
  saveDelayMs: number;
  /** How long loading the draft takes. */
  loadDelayMs: number;
  inFlight: number;
  maxInFlight: number;
  saves: Array<Record<string, unknown>>;
  conflicts: number;
};

function draftServer(overrides: Partial<DraftServer> = {}): DraftServer {
  return {
    revision: 3,
    title: "Fran",
    body: "21-15-9 Thrusters and Pull-ups",
    authoringMode: "free_text",
    saveDelayMs: 0,
    loadDelayMs: 0,
    inFlight: 0,
    maxInFlight: 0,
    saves: [],
    conflicts: 0,
    ...overrides,
  };
}

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function workoutRecord(server: DraftServer) {
  const sectioned = server.authoringMode === "sectioned_text";
  return {
    id: draftId,
    status: "draft",
    title: server.title,
    type: "crossfit",
    authoring_mode: server.authoringMode,
    free_text_body: sectioned ? null : server.body,
    dsl_source_revision: server.revision,
    available_scale_levels: [],
    sections: sectioned ? [{ name: "Main", free_text_body: server.body, timer_preset: null, exercises: [] }] : [],
    draft_data: sectioned
      ? { authoring_mode: "sectioned_text" }
      : { authoring_mode: "free_text", free_text_body: server.body },
  };
}

async function mockApi(context: BrowserContext, server: DraftServer) {
  await context.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (path === "/api/auth/refresh") return json(route, { access_token: "test-token" });
    if (path === "/api/auth/me") return json(route, admin);
    if (path === "/api/memberships") return json(route, [adminMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === `/api/admin/workouts/${draftId}` && method === "GET") {
      if (server.loadDelayMs) await sleep(server.loadDelayMs);
      return json(route, { workout: workoutRecord(server) });
    }
    if (path === `/api/admin/workouts/${draftId}/draft` && method === "PATCH") {
      const update = route.request().postDataJSON() as Record<string, unknown>;
      server.inFlight += 1;
      server.maxInFlight = Math.max(server.maxInFlight, server.inFlight);
      try {
        if (server.saveDelayMs) await sleep(server.saveDelayMs);
        if (update.expected_source_revision !== server.revision) {
          server.conflicts += 1;
          return json(route, { error: "This workout was saved somewhere else after you opened it.", code: "stale_dsl_revision" }, 409);
        }
        server.revision += 1;
        server.saves.push(update);
        if (typeof update.title === "string") server.title = update.title;
        return json(route, { draft: { id: draftId, status: "draft", authoring_mode: update.authoring_mode, dsl_source_revision: server.revision } });
      } finally {
        server.inFlight -= 1;
      }
    }
    if (path === `/api/admin/workouts/${draftId}/goals`) return json(route, { goals: null, suggestion: null });
    if (path === "/api/admin/scale-levels") return json(route, { scale_levels: [] });
    if (path === "/api/admin/workout-folders") return json(route, { folders: [] });
    return json(route, {});
  });
}

test("slow saves while the coach keeps typing never collide", async ({ context, page }) => {
  // The case behind "changed in another editor" with only one editor open:
  // each save took longer than the autosave delay, so saves overlapped.
  const server = draftServer({ saveDelayMs: 1_500 });
  await mockApi(context, server);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const title = page.getByPlaceholder("Leave empty to let the assistant propose one");
  await expect(title).toHaveValue("Fran");
  for (const word of [" sdfds", " efes", " again"]) {
    await title.press("End");
    await title.pressSequentially(word);
    await page.waitForTimeout(1_200);
  }

  await expect.poll(() => server.title, { timeout: 15_000 }).toBe("Fran sdfds efes again");
  await expect.poll(() => server.inFlight, { timeout: 15_000 }).toBe(0);
  // The save status is hidden on phones, so it is checked in the DOM.
  await expect(page.locator("[role=status]", { hasText: "Draft saved" })).toHaveCount(1);
  expect(server.conflicts).toBe(0);
  expect(server.maxInFlight).toBe(1);
  await expect(page.getByTestId("draft-conflict-notice")).toHaveCount(0);
});

test("nothing is saved before a slow draft finishes loading", async ({ context, page }) => {
  // An early autosave used to send the empty editor and then use the
  // revision from the late load, which the server had already moved past.
  const server = draftServer({ loadDelayMs: 2_500 });
  await mockApi(context, server);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const title = page.getByPlaceholder("Leave empty to let the assistant propose one");
  await expect(title).toHaveValue("Fran", { timeout: 15_000 });
  await title.press("End");
  await title.pressSequentially(" Friday");
  await expect.poll(() => server.title, { timeout: 10_000 }).toBe("Fran Friday");
  expect(server.saves.every((save) => typeof save.free_text_body === "string" && save.free_text_body.length > 0)).toBe(true);
  expect(server.conflicts).toBe(0);
});

test("a real change elsewhere explains itself and keeps the coach's version on request", async ({ context, page }) => {
  const server = draftServer();
  await mockApi(context, server);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const title = page.getByPlaceholder("Leave empty to let the assistant propose one");
  await expect(title).toHaveValue("Fran");
  await expect.poll(() => server.saves.length).toBeGreaterThan(0);
  // Saved in another tab.
  server.revision += 5;
  server.title = "Fran (other tab)";

  await title.fill("Fran (mine)");
  const notice = page.getByTestId("draft-conflict-notice");
  await expect(notice).toBeVisible();
  await expect(notice).toContainText("This WOD was changed somewhere else");
  await expect(notice).toContainText("Which version do you want to keep?");
  await expect(page.locator("[role=status]", { hasText: "Not saved: changed elsewhere" })).toHaveCount(1);
  const conflictsSeen = server.conflicts;
  // Autosave waits for the coach's choice instead of retrying.
  await page.waitForTimeout(1_500);
  expect(server.conflicts).toBe(conflictsSeen);

  await notice.getByRole("button", { name: /Keep my version/ }).click();
  await expect(notice).toHaveCount(0);
  await expect.poll(() => server.title).toBe("Fran (mine)");
});

test("loading the other version replaces the coach's unsaved text", async ({ context, page }) => {
  const server = draftServer();
  await mockApi(context, server);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const title = page.getByPlaceholder("Leave empty to let the assistant propose one");
  await expect(title).toHaveValue("Fran");
  await expect.poll(() => server.saves.length).toBeGreaterThan(0);
  server.revision += 2;
  server.title = "Fran (other tab)";

  await title.fill("Fran (mine)");
  const notice = page.getByTestId("draft-conflict-notice");
  await expect(notice).toBeVisible();
  await notice.getByRole("button", { name: /Load the other version/ }).click();
  await expect(notice).toHaveCount(0);
  await expect(title).toHaveValue("Fran (other tab)");
  expect(server.saves.some((save) => save.title === "Fran (mine)")).toBe(false);
});

test("the sections editor shows the same notice for a real change elsewhere", async ({ context, page }) => {
  const server = draftServer({ authoringMode: "sectioned_text" });
  await mockApi(context, server);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const title = page.getByPlaceholder("Leave empty to let the assistant propose one");
  await expect(title).toHaveValue("Fran");
  await expect.poll(() => server.saves.length).toBeGreaterThan(0);
  server.revision += 1;

  await title.fill("Fran (mine)");
  const notice = page.getByTestId("draft-conflict-notice");
  await expect(notice).toBeVisible();
  await notice.getByRole("button", { name: /Keep my version/ }).click();
  await expect(notice).toHaveCount(0);
  await expect.poll(() => server.title).toBe("Fran (mine)");
  expect(server.saves.at(-1)?.authoring_mode).toBe("sectioned_text");
});
