import { expect, test, type Page } from "./support/test";

// Redesign Phase 2 M1: an admin edits one location on its own page: address
// search, a Google Maps link, a draggable pin and weekly opening hours. The
// API is stubbed; every route not listed here answers an empty object.

const SHOTS = process.env.SCHEDULE_SCREENSHOTS_DIR;

const user = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  completed_tours: ["admin", "member", "athlete"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(
    JSON.stringify({
      sub: user.id,
      role: user.role,
      memberships: [{ organization_slug: "kypseli" }],
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const kypseli = {
  label: "Φωκίωνος Νέγρη 12, Κυψέλη, Αθήνα",
  address: "Φωκίωνος Νέγρη 12",
  neighbourhood: "Κυψέλη",
  city: "Αθήνα",
  country_code: "GR",
  latitude: 38.000563,
  longitude: 23.7345526,
};

async function stubApi(page: Page, saved: Array<Record<string, unknown>>) {
  let location: Record<string, unknown> = {
    id: "loc-1",
    organization_id: "org-1",
    name: "Box Κυψέλη",
    address: null,
    latitude: null,
    longitude: null,
    neighbourhood: null,
    city: null,
    country_code: null,
    opening_hours: [],
    accessibility: [],
    archived_at: null,
  };
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { manage_settings: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/locations", (route) => route.fulfill(json({ locations: [location] })));
  await page.route("**/api/org/*/admin/locations/loc-1", async (route) => {
    const body = route.request().postDataJSON() as Record<string, unknown>;
    saved.push(body);
    location = { ...location, ...body };
    await route.fulfill(json({ location }));
  });
  await page.route("**/api/org/*/admin/geocode?**", (route) =>
    route.fulfill(json({ places: [kypseli, { ...kypseli, label: "Φωκίωνος Νέγρη 12, Γαλάτσι", neighbourhood: "Γαλάτσι", latitude: 38.02 }] })),
  );
  await page.route("**/api/org/*/admin/geocode/reverse?**", (route) => route.fulfill(json({ place: kypseli })));
  await page.route("**/api/org/*/admin/geocode/link?**", (route) =>
    route.fulfill(json({ place: { ...kypseli, latitude: 38.0012, longitude: 23.7351 } })),
  );
}

async function shot(page: Page, name: string) {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${test.info().project.name}-${name}.png`, fullPage: true });
}

test.describe("admin location editor", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
  });

  test("pins a location from the address search and saves its hours", async ({ page }) => {
    const saved: Array<Record<string, unknown>> = [];
    await stubApi(page, saved);
    await page.goto("/admin/settings/locations/loc-1");
    await expect(page.getByRole("heading", { name: "Box Κυψέλη" })).toBeVisible();
    await expect(page.getByText(/Δεν υπάρχει πινέζα/)).toBeVisible();

    await page.getByRole("combobox", { name: "Διεύθυνση" }).fill("Φωκίωνος Νέγρη 12");
    await page.getByRole("button", { name: "Φωκίωνος Νέγρη 12, Κυψέλη, Αθήνα" }).click();
    await expect(page.getByLabel("Γειτονιά")).toHaveValue("Κυψέλη");
    await expect(page.getByText(/Σύρε την πινέζα στην είσοδο/)).toBeVisible();

    await page.getByRole("button", { name: "Προσθήκη ωραρίου για Δευτέρα" }).click();
    await page.getByRole("button", { name: "Προσθήκη ωραρίου για Δευτέρα" }).click();
    await page.getByRole("button", { name: /Αντιγραφή της Δευτέρας/ }).click();
    await expect(page.getByLabel("Παρασκευή ανοίγει")).toHaveCount(2);
    await expect(page.getByText("Μη αποθηκευμένες αλλαγές")).toBeVisible();
    await shot(page, "admin-location");

    await page.getByRole("button", { name: "Αποθήκευση" }).click();
    await expect(page.getByText("Αποθηκεύτηκε")).toBeVisible();
    expect(saved).toHaveLength(1);
    expect(saved[0]).toMatchObject({ address: "Φωκίωνος Νέγρη 12", neighbourhood: "Κυψέλη", latitude: 38.000563 });
    expect((saved[0].opening_hours as unknown[]).length).toBe(10);
  });

  test("a pasted Google Maps link places the pin", async ({ page }) => {
    const saved: Array<Record<string, unknown>> = [];
    await stubApi(page, saved);
    await page.goto("/admin/settings/locations/loc-1");
    await page.getByRole("combobox", { name: "Διεύθυνση" }).fill("https://maps.app.goo.gl/kypseli");
    await expect(page.getByRole("combobox", { name: "Διεύθυνση" })).toHaveValue("Φωκίωνος Νέγρη 12");
    await expect(page.getByLabel("Γειτονιά")).toHaveValue("Κυψέλη");
    await page.getByRole("button", { name: "Αποθήκευση" }).click();
    await expect(page.getByText("Αποθηκεύτηκε")).toBeVisible();
    expect(saved[0]).toMatchObject({ latitude: 38.0012, longitude: 23.7351 });
  });
});
