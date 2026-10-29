import { expect, test, type Page } from "./support/test";
import { json } from "./support/structured-wod";

// The WOD vault draws folders as folders and WODs as pages, with the chosen
// emoji in the middle; «Παραλλαγές για μέλος» carries the member-to-member
// glyph and class-date folders their date. The API is stubbed; every route not
// listed answers an empty object.

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

const folders = [
  { id: "f-athletes", name: "Athletes", parent_id: null, system_key: "athletes" },
  { id: "f-classes", name: "Classes", parent_id: null, system_key: "classes" },
  { id: "f-variations", name: "Variations for member", parent_id: null, system_key: "member_variations" },
  { id: "f-year", name: "2026", parent_id: "f-classes", system_key: "classes:2026" },
  { id: "f-misc", name: "Misc", parent_id: null, system_key: null },
];

const workout = (id: string, title: string, extra: Record<string, unknown> = {}) => ({
  id,
  title,
  type: "strength",
  status: "published",
  folder_id: null,
  icon: null,
  available_scale_levels: [],
  sections: [],
  ...extra,
});

async function stubVault(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: "test-token" });
    if (path === "/api/auth/me") return json(route, admin);
    if (path === "/api/memberships") return json(route, [adminMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/workout-folders") return json(route, { folders });
    if (path === "/api/admin/workouts") {
      return json(route, { workouts: [workout("w-legs", "Legs"), workout("w-fran", "Fran", { icon: "🔥", status: "draft" })] });
    }
    return json(route, {});
  });
}

test.describe("WOD vault › folder and file icons", () => {
  test("folders look like folders and WODs like pages, with their mark in the middle", async ({ page }) => {
    await stubVault(page);
    await page.goto("/admin/workouts");

    const tile = (name: string) => page.getByRole("listitem").filter({ hasText: name });

    const athletes = tile("Αθλητές").locator('[data-icon="folder"]');
    await expect(athletes).toBeVisible({ timeout: 15_000 });
    await expect(athletes).toContainText("👥");

    // Variations for member: the member-to-member glyph, not an emoji.
    const variations = tile("Παραλλαγές για μέλος").locator('[data-icon="folder"]');
    await expect(variations.locator("svg")).toHaveCount(2);
    await expect(variations).not.toContainText("🎯");

    // A coach folder with no fitting emoji stays a plain folder.
    await expect(tile("Misc").locator('[data-icon="folder"]')).not.toContainText("📁");

    await expect(tile("Legs").locator('[data-icon="file"]')).toContainText("🦵");
    await expect(tile("Fran").locator('[data-icon="file"]')).toContainText("🔥");
  });

  test("a year folder shows its year inside the folder", async ({ page }) => {
    await stubVault(page);
    await page.goto("/admin/workouts");
    await page.getByRole("listitem").filter({ hasText: "Τμήματα" }).getByRole("button").first().click();
    await expect(page.getByRole("listitem").filter({ hasText: "2026" }).locator('[data-icon="folder"]')).toContainText("2026");
  });
});
