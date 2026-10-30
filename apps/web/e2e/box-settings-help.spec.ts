import { expect, test, type Page, type Route } from "./support/test";

// The box settings explain themselves (2026-10-28): difficulty levels ask
// only for a name and say what the fixed code is for, the installation's push
// keys are gone from the box (ADR-218), and the platform console shows only
// status and the contact, because the server makes the keys itself (ADR-277).
// The API is stubbed.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

function person(id: string, vendor: boolean) {
  return {
    id,
    nickname: vendor ? "Vendor" : "Apostolos",
    role: "admin",
    email: `${id}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor,
    memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
  };
}

const ownerMembership = {
  role: "owner",
  roles: ["owner", "coach"],
  capabilities: { manage_settings: true, grant_staff_roles: true, manage_coaching: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const savedLevels = [
  { id: "l1", slug: "scaled", label: "Scaled", sort_order: 1, is_active: true },
  { id: "l2", slug: "rx", label: "Rx", sort_order: 2, is_active: true },
];

async function stub(page: Page, user: ReturnType<typeof person>, writes: Array<{ path: string; body: unknown }>) {
  let push = {
    enabled: true,
    source: "palee",
    vapid_subject: "mailto:alerts@palee.app",
    subject_source: "default",
    keys_created_at: "2026-10-29T21:00:00Z",
    device_count: 3,
    last_sent_at: "2026-10-29T21:14:00Z",
  };
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" ? null : route.request().postDataJSON();
    if (body !== null) writes.push({ path, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(user), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, user);
    if (path === "/api/memberships") return json(route, [ownerMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/settings") return json(route, { gamification: {}, finance: {}, scheduling: {} });
    // Settings › Invitations shows the two join links (ADR-216).
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/community/groups") {
      return json(route, { settings: { member_groups: "none", partners_enabled: false }, pending: [], groups: [] });
    }
    if (path === "/api/admin/scale-levels") {
      if (method === "PUT") {
        const levels = (body as { scale_levels: Array<{ slug: string; label: string; sort_order: number }> }).scale_levels;
        return json(route, { scale_levels: levels.map((l, i) => ({ ...l, id: `l${i + 1}`, is_active: true })) });
      }
      return json(route, { scale_levels: savedLevels });
    }
    if (path.startsWith("/api/platform/push-settings")) {
      if (!user.vendor) return json(route, { code: "vendor_required" }, 403);
      if (method === "PATCH") {
        const contact = (body as { vapid_subject: string }).vapid_subject.trim();
        push = { ...push, vapid_subject: contact.includes(":") ? contact : `mailto:${contact}`, subject_source: "palee" };
      }
      if (method === "POST") push = { ...push, device_count: 0, keys_created_at: "2026-10-29T22:00:00Z" };
      return json(route, push);
    }
    return json(route, {});
  });
}

test("difficulty levels ask only for a name and explain the fixed code", async ({ page }) => {
  const writes: Array<{ path: string; body: unknown }> = [];
  await stub(page, person("owner-1", false), writes);
  await page.goto("/admin/settings");

  // ADR-218: no push keys on a box's settings page any more.
  await expect(page.getByRole("button", { name: /Difficulty levels/ })).toBeVisible();
  await expect(page.getByText("Public key")).toHaveCount(0);
  await expect(page.locator("#notifications")).toHaveCount(0);

  const section = page.locator("#level-taxonomy");
  await expect(section.getByText(/Each level has two parts/)).toBeVisible();
  await expect(section.getByLabel("Level name")).toHaveCount(2);
  await expect(section.getByTestId("level-code")).toHaveText(["scaled", "rx"]);
  await expect(section.getByText("fixed, used in WOD text and in history")).toHaveCount(2);

  await section.getByRole("button", { name: "+ Add level" }).click();
  await expect(section.getByText("Every level needs a name.")).toBeVisible();
  await section.getByLabel("Level name").nth(2).fill("Αρχάριοι");
  await expect(section.getByTestId("level-code").nth(2)).toHaveText("archarioi");
  await expect(section.getByText("made from the name when you save")).toBeVisible();

  await section.getByRole("button", { name: /^Save/ }).click();
  await expect.poll(() => writes.find((w) => w.path === "/api/admin/scale-levels")?.body).toEqual({
    scale_levels: [
      { slug: "scaled", label: "Scaled", sort_order: 1 },
      { slug: "rx", label: "Rx", sort_order: 2 },
      { slug: "archarioi", label: "Αρχάριοι", sort_order: 3 },
    ],
  });
});

test("the platform team sees status and the contact, never a key, and can replace the keys", async ({ page }) => {
  const writes: Array<{ path: string; body: unknown }> = [];
  await stub(page, person("vendor-1", true), writes);
  await page.goto("/platform/push");

  await expect(page.getByRole("heading", { name: "Browser alerts" })).toBeVisible();
  await expect(page.getByTestId("push-status")).toHaveText("On");
  await expect(page.getByText(/You don't send anything to anyone/)).toBeVisible();
  await expect(page.getByTestId("push-stats")).toContainText("3 devices allow alerts");
  await expect(page.getByText(/Public key|Private key/)).toHaveCount(0);
  await expect(page.locator("textarea")).toHaveCount(0);

  const contact = page.getByLabel("Contact for Google, Apple and Mozilla");
  await expect(contact).toHaveValue("mailto:alerts@palee.app");
  await contact.fill("ops@palee.app");
  await page.getByRole("button", { name: "Save contact" }).click();
  await expect(page.getByText("Saved", { exact: true })).toBeVisible();
  await expect(contact).toHaveValue("mailto:ops@palee.app");
  expect(writes.find((w) => w.path === "/api/platform/push-settings")?.body).toEqual({ vapid_subject: "ops@palee.app" });

  // The one rare action sits behind «Advanced» and asks first.
  await expect(page.getByRole("button", { name: "New keys…" })).toBeHidden();
  await page.getByText("Advanced").click();
  await page.getByRole("button", { name: "New keys…" }).click();
  await expect(page.getByTestId("push-rotate-confirm")).toContainText("3 devices stop getting alerts");
  await page.getByRole("button", { name: "Replace the keys" }).click();
  await expect(page.getByText("New keys in use")).toBeVisible();
  await expect(page.getByTestId("push-stats")).toContainText("0 devices allow alerts");
});

test("a box owner opening the push page is told it is not theirs", async ({ page }) => {
  await stub(page, person("owner-1", false), []);
  await page.goto("/platform/push");
  await expect(page.getByText("Only the platform team manages browser alerts.")).toBeVisible();
});
