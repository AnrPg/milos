import { expect, test, type Page, type Request } from "./support/test";
import { chooseOption } from "./support/select";

// ADR-225: on a member's profile, staff book the member into a class or move
// one of their bookings. The API lists the choices and says why a class
// cannot take the member; a member out of visits can still be moved, since
// the move returns the old booking's visit. The API is stubbed; every route
// not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");
const inDays = (days: number, hour: number) => {
  const at = new Date();
  at.setUTCDate(at.getUTCDate() + days);
  at.setUTCHours(hour, 0, 0, 0);
  return at.toISOString();
};

async function common(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Kostas",
    role: "admin",
    email: "owner@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { book_for_clients: true, view_client_training: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/admin/users/u-1", (route) =>
    route.fulfill(
      json({
        user: {
          identity: { id: "u-1", nickname: "Eleni", avatar_url: null, role: "member", joined_at: "2026-01-10T10:00:00Z" },
          account_status: "active",
          membership: { roles: ["member"], coach_scope: "all" },
          available_sections: [],
          attention: [],
          operational_links: {},
        },
      }),
    ),
  );
}

const option = (slot_id: string, name: string, scheduled_at: string, blocked_reason: string | null, spots_remaining = 5) => ({
  slot_id,
  name,
  scheduled_at,
  duration_minutes: 60,
  capacity: 12,
  spots_remaining,
  blocked_reason,
});

test.describe("Member profile › Book or move (ADR-225)", () => {
  test("staff move a member out of visits, and full classes stay closed", async ({ page }) => {
    await common(page);
    const placements: unknown[] = [];
    await page.route("**/api/org/*/admin/users/u-1/class-placement", (route) => {
      if (route.request().method() === "POST") {
        placements.push(bodyOf(route.request()));
        return route.fulfill(json({ booking: { id: "bk-new", status: "approved" }, previous_booking_id: "bk-1" }, 201));
      }
      return route.fulfill(
        json({
          timezone: "Europe/Athens",
          lookahead_days: 30,
          bookings: [{ booking_id: "bk-1", slot_id: "s-1", name: "WOD 07:00", scheduled_at: inDays(1, 5), status: "approved" }],
          classes: [
            option("s-2", "WOD 18:00", inDays(1, 16), "finance_allowance_exhausted"),
            option("s-3", "WOD 19:00", inDays(1, 17), "slot_full", 0),
            option("s-4", "Open Gym", inDays(2, 16), "class_not_published"),
          ],
        }),
      );
    });

    await page.goto("/admin/users/u-1");
    await page.getByRole("button", { name: "Book or move" }).click({ timeout: 60_000 });
    const dialog = page.getByRole("dialog");
    const target = dialog.getByTestId("placement-target");

    // A new booking: every class says why it cannot take her.
    await target.click();
    await expect(page.locator('[role="option"][data-value="s-2"]')).toHaveAttribute("aria-disabled", "true");
    await expect(page.locator('[role="option"][data-value="s-2"]')).toContainText("no visits left in the package");
    await expect(page.locator('[role="option"][data-value="s-3"]')).toContainText("full");
    await expect(page.locator('[role="option"][data-value="s-4"]')).toContainText("draft, no WOD yet");
    await page.keyboard.press("Escape");
    await expect(dialog.getByRole("button", { name: "Book", exact: true })).toBeDisabled();

    // A move returns the old visit: the class she had no visit for opens.
    await chooseOption(page, dialog.getByTestId("placement-from"), "bk-1");
    await expect(dialog).toContainText("with no cancellation charge");
    await chooseOption(page, target, "s-2");
    await target.click();
    await expect(page.locator('[role="option"][data-value="s-3"]')).toHaveAttribute("aria-disabled", "true");
    await page.keyboard.press("Escape");

    await dialog.getByRole("button", { name: "Move", exact: true }).click();
    await expect.poll(() => placements).toEqual([{ slot_id: "s-2", from_booking_id: "bk-1" }]);
    await expect(dialog).toBeHidden();
  });

  test("a refused placement says why inside the dialog", async ({ page }) => {
    await common(page);
    await page.route("**/api/org/*/admin/users/u-1/class-placement", (route) =>
      route.request().method() === "POST"
        ? route.fulfill(json({ code: "slot_full", message: "Slot is full" }, 422))
        : route.fulfill(json({ timezone: "Europe/Athens", lookahead_days: 30, bookings: [], classes: [option("s-2", "WOD 18:00", inDays(1, 16), null)] })),
    );

    await page.goto("/admin/users/u-1");
    await page.getByRole("button", { name: "Book or move" }).click({ timeout: 60_000 });
    const dialog = page.getByRole("dialog");
    await chooseOption(page, dialog.getByTestId("placement-target"), "s-2");
    await dialog.getByRole("button", { name: "Book", exact: true }).click();
    await expect(dialog).toContainText("Not done: full.");
  });
});
