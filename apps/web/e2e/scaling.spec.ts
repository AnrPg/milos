import { expect, test, type Page, type Route } from "./support/test";

// P3-M12 AI scaling suggestions (ADR-174): the owner switches the feature on
// with the gym's own key, a coach approves a suggestion with an edit, and a
// member sees only the approved adaptation on today's workout. The API is
// stubbed; every other route answers an empty object.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

function localToday() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}
function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

// ── Owner and coach ──────────────────────────────────────────────────────────

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

const ownerMembership = {
  role: "owner",
  roles: ["owner", "coach"],
  capabilities: { manage_settings: true, grant_staff_roles: true, manage_coaching: true, view_health: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const offSettings = {
  provider: "anthropic",
  scaling_enabled: false,
  key_configured: false,
  key_last4: null,
  key_status: "unknown",
  model: null,
  default_model: "default-model",
  usage: { suggestions: 0, cost_usd: 0 },
};

const suggestion = {
  id: "sug-1",
  athlete_id: "member-1",
  athlete_nickname: "Maria L",
  assigned_workout_id: "assign-1",
  master_workout_id: "wod-1",
  workout_title: "Fran",
  scheduled_for: localToday(),
  status: "pending",
  summary: "Keep the stimulus, spare the knee.",
  scale_level_slug: "scaled",
  scale_level_label: "Scaled",
  injury_regions: ["knee"],
  coach_note: null,
  items: [
    { id: "i1", exercise_id: "m1", section_id: "s1", exercise_name: "Thrusters", change: "substitute", prescribed: "43/30 kg", suggested: "Push press", reason: "Less knee flexion" },
    { id: "i2", exercise_id: "m2", section_id: "s1", exercise_name: "Box jumps", change: "skip", prescribed: "15", suggested: null, reason: "Landing impact" },
  ],
};

async function stubOwner(page: Page, puts: Array<Record<string, unknown>>, approvals: Array<Record<string, unknown>>) {
  let settings: Record<string, unknown> = { ...offSettings };
  let queue = [suggestion];
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [ownerMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/ai-settings") {
      if (method === "PUT") {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        puts.push(body);
        if (typeof body.api_key === "string") {
          settings = { ...settings, key_configured: true, key_last4: body.api_key.slice(-4), key_status: "unknown" };
        }
        if (typeof body.scaling_enabled === "boolean") settings = { ...settings, scaling_enabled: body.scaling_enabled };
      }
      return json(route, { ai_settings: settings });
    }
    // The settings hub's other sections need their own shapes to render.
    if (path === "/api/admin/settings") return json(route, { gamification: {}, finance: {}, scheduling: {} });
    // Settings › Invitations shows the two join links (ADR-216).
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/community/groups") {
      return json(route, { settings: { member_groups: "none", partners_enabled: false }, pending: [], groups: [] });
    }
    if (path === "/api/staff/scaling-suggestions") return json(route, { suggestions: queue });
    if (path === "/api/staff/scaling-suggestions/sug-1/approve") {
      approvals.push(route.request().postDataJSON() as Record<string, unknown>);
      queue = [];
      return json(route, { suggestion: { ...suggestion, status: "approved" } });
    }
    if (path.endsWith("/join-link")) return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    return json(route, {});
  });
}

test("the owner switches suggestions on with the gym's key", async ({ page }) => {
  const puts: Array<Record<string, unknown>> = [];
  await stubOwner(page, puts, []);
  await page.goto("/admin/settings");
  await page.getByRole("button", { name: /AI assistant/ }).click();
  const panel = page.getByTestId("ai-scaling-settings");
  await expect(panel.getByText("No key set.")).toBeVisible();
  const toggle = panel.getByRole("switch", { name: "Scaling suggestions" });
  await expect(toggle).toBeDisabled();

  await panel.getByLabel("API key (Anthropic)").fill("sk-test-key-0123456789-abcd");
  await panel.getByRole("button", { name: "Save key" }).click();
  await expect(panel.getByText("A key ending in abcd is set.")).toBeVisible();
  await expect(panel.getByLabel("API key (Anthropic)")).toHaveValue("");

  await toggle.check();
  await expect(toggle).toBeChecked();
  expect(puts).toEqual([{ api_key: "sk-test-key-0123456789-abcd" }, { scaling_enabled: true }]);
  await expect(panel.getByTestId("ai-usage")).toContainText("suggestions: 0");
});

test("a coach approves a suggestion with an edit and drops one change", async ({ page }) => {
  const approvals: Array<Record<string, unknown>> = [];
  await stubOwner(page, [], approvals);
  await page.goto("/admin");
  const card = page.getByTestId("scaling-suggestion");
  await expect(card).toContainText("Maria L");
  await expect(card).toContainText("knee");
  await expect(card).toContainText("Thrusters → Push press");

  await card.getByRole("textbox", { name: "Suggestion for Thrusters" }).fill("Strict press");
  await card.getByRole("checkbox", { name: "Include: Box jumps" }).uncheck();
  await card.getByRole("textbox", { name: "Message to the athlete (optional)" }).fill("Go easy today");
  await card.getByRole("button", { name: "Approve" }).click();

  await expect(card).toBeHidden();
  expect(approvals).toEqual([
    {
      items: [
        { id: "i1", suggested: "Strict press" },
        { id: "i2", include: false },
      ],
      coach_note: "Go easy today",
    },
  ]);
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

const fran = { id: "wod-1", title: "Fran", type: "crossfit", authoring_mode: "free_text", free_text_body: "21-15-9\nThrusters 43/30 kg\nPull-ups", sections: [] };

async function stubMember(page: Page, scaling: unknown) {
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(member), refresh_token: "refresh" });
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
    if (/\/injury-warnings$/.test(path)) return json(route, { level: "none", warnings: [], warning_count: 0 });
    if (path === "/api/me/workouts/wod-1/scaling") return json(route, { scaling });
    if (path.endsWith("/join-link")) return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    return json(route, {});
  });
}

test.describe("member", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("sees the coach-approved adaptation with the AI disclosure", async ({ page }) => {
    await stubMember(page, {
      id: "sug-1",
      scale_level_slug: "scaled",
      scale_level_label: "Scaled",
      coach_note: "Go easy today",
      reviewed_at: "2026-10-21T08:00:00Z",
      items: [{ exercise_id: "m1", section_id: "s1", exercise_name: "Thrusters", change: "substitute", suggested: "Strict press", reason: "Less knee flexion" }],
    });
    await page.goto("/box");
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    const panel = page.getByTestId("my-workout-scaling");
    await expect(panel.getByRole("heading", { name: "Adjusted by your coach" })).toBeVisible();
    await expect(panel).toContainText("Level: Scaled");
    await expect(panel).toContainText("Thrusters → Strict press");
    await expect(panel).toContainText("«Go easy today»");
    await expect(panel).toContainText("AI-assisted · approved by your coach.");
  });

  test("sees nothing when no adaptation was approved", async ({ page }) => {
    await stubMember(page, null);
    await page.goto("/box");
    await expect(page.getByRole("heading", { name: "Fran" })).toBeVisible();
    await expect(page.getByTestId("my-workout-scaling")).toHaveCount(0);
  });
});
