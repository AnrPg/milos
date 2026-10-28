import { expect, test, type Page } from "./support/test";
import { chooseOption } from "./support/select";

// The staff programming dialog on a member's profile (Training tab): one
// question at a time, only the fields the chosen path needs, extras folded
// under «More options», and one primary action that says what happens.
// The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

function isoDay(offset: number) {
  const date = new Date();
  date.setDate(date.getDate() + offset);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

const TODAY = isoDay(0);
const TOMORROW = isoDay(1);

async function stub(page: Page) {
  const user = {
    id: "coach-1",
    nickname: "Kostas",
    role: "admin",
    email: "coach@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "coach", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const posts: Record<string, unknown>[] = [];

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "coach",
          roles: ["coach"],
          capabilities: { view_client_training: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
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
          membership: { roles: ["member"], coach_scope: "assigned" },
          available_sections: [],
          attention: [],
          operational_links: {},
        },
      }),
    ),
  );
  await page.route("**/api/org/*/admin/users/u-1/prs", (route) => route.fulfill(json({ user_id: "u-1", visibility: "coach", member: null, prs: [] })));
  await page.route("**/api/org/*/admin/users/u-1/schedule?**", (route) =>
    route.fulfill(
      json({
        user_id: "u-1",
        role: "member",
        start_date: TODAY,
        end_date: isoDay(6),
        items: [{ id: "slot-1", kind: "class", name: "CrossFit", scheduled_at: `${TODAY}T15:00:00Z`, master_workout_id: "w-class" }],
      }),
    ),
  );
  await page.route("**/api/org/*/admin/workouts", (route) =>
    route.fulfill(json({ workouts: [{ id: "w-fran", title: "Fran", status: "published" }] })),
  );
  await page.route("**/api/org/*/admin/workout-folders", (route) => route.fulfill(json({ folders: [] })));
  await page.route("**/api/org/*/admin/users/u-1/programming", (route) => {
    posts.push(route.request().postDataJSON() as Record<string, unknown>);
    return route.fulfill(json({ workout: { id: "w-new" }, association: {}, mode: "class_variant" }));
  });
  return posts;
}

test.describe("member programming dialog", () => {
  test("asks one thing at a time and has one primary action", async ({ page }) => {
    const posts = await stub(page);
    await page.goto("/admin/users/u-1?tab=training");
    await page.getByTestId(`programming-day-${TODAY}`).click({ timeout: 60_000 });

    const dialog = page.getByTestId("programming-dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText("Programming for Eleni");
    // A readable date, never the raw ISO day.
    await expect(dialog.getByRole("heading")).not.toContainText(TODAY);

    // Recommended path: this member's own version of their only booked class, picked for them.
    await expect(dialog.getByRole("radio", { name: /Change it for this member only/ })).toBeChecked();
    await expect(dialog.getByText(/\d{1,2}:\d{2}.* · CrossFit/)).toBeVisible();
    await expect(dialog.getByRole("radio", { name: "Adapt the class WOD" })).toBeChecked();
    const submit = dialog.getByTestId("programming-submit");
    await expect(submit).toHaveText("Continue to the editor");
    await expect(submit).toBeEnabled();

    // Extras stay folded away, with a summary of what they hold.
    const more = dialog.getByRole("button", { name: /More options/ });
    await expect(more).toHaveAttribute("aria-expanded", "false");
    await expect(more).toContainText("Folder: Automatic · just this person");
    await expect(dialog.getByText("Library folder")).toHaveCount(0);

    await dialog.getByRole("radio", { name: "The class WOD as it is" }).click({ force: true });
    await expect(submit).toHaveText("Assign");
    await submit.click();
    await expect(dialog).toBeHidden();
    expect(posts.at(-1)).toMatchObject({ mode: "class_variant", slot_id: "slot-1", copy_source: true, scheduled_for: TODAY, folder_id: null });
    expect(posts.at(-1)).not.toHaveProperty("master_workout_id");
  });

  test("a separate workout needs no class and waits for a WOD", async ({ page }) => {
    const posts = await stub(page);
    await page.goto("/admin/users/u-1?tab=training");
    await page.getByTestId(`programming-day-${TODAY}`).click({ timeout: 60_000 });
    const dialog = page.getByTestId("programming-dialog");

    await dialog.getByRole("radio", { name: /Separate workout/ }).click();
    await expect(dialog.getByText("Choose a class…")).toHaveCount(0);
    await expect(dialog.getByRole("radio", { name: "Adapt the class WOD" })).toHaveCount(0);
    await expect(dialog.getByRole("radio", { name: "From the library" })).toBeChecked();

    const submit = dialog.getByTestId("programming-submit");
    await expect(submit).toBeDisabled();
    await expect(dialog.getByTestId("programming-blocker")).toHaveText("Choose a WOD from the library.");
    await chooseOption(page, dialog.locator('[aria-label="Existing WOD"]'), "w-fran");
    await expect(submit).toBeEnabled();

    await dialog.getByRole("button", { name: /More options/ }).click();
    await expect(dialog.getByText("Library folder")).toBeVisible();
    await expect(dialog.getByRole("searchbox", { name: "Search people" })).toBeVisible();
    await expect(dialog.getByText("No one matches.")).toHaveCount(0);

    await submit.click();
    await expect(dialog).toBeHidden();
    expect(posts.at(-1)).toMatchObject({ mode: "personal", master_workout_id: "w-fran", copy_source: true });
    expect(posts.at(-1)?.slot_id).toBeUndefined();
  });

  test("a day without a booked class says so instead of showing empty fields", async ({ page }) => {
    await stub(page);
    await page.goto("/admin/users/u-1?tab=training");
    await page.getByTestId(`programming-day-${TOMORROW}`).click({ timeout: 60_000 });
    const dialog = page.getByTestId("programming-dialog");
    // The title is the clicked day itself, never shifted by a time zone.
    await expect(dialog.getByRole("heading")).toContainText(new RegExp(`\\b${Number(TOMORROW.slice(8))}\\b`));

    await expect(dialog.getByTestId("programming-no-class")).toContainText("No class booked this day");
    await expect(dialog.getByRole("radio", { name: "Adapt the class WOD" })).toHaveCount(0);
    await expect(dialog.getByTestId("programming-submit")).toBeDisabled();

    await dialog.getByRole("radio", { name: /Separate workout/ }).click();
    await expect(dialog.getByTestId("programming-no-class")).toHaveCount(0);
    await dialog.getByRole("radio", { name: "New WOD" }).click({ force: true });
    await expect(dialog.getByTestId("programming-submit")).toHaveText("Continue to the editor");
    await expect(dialog.getByTestId("programming-submit")).toBeEnabled();
  });
});
