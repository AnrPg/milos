import { expect, test, type Page } from "./support/test";

// Redesign Phase 2 M1: an admin edits the gym's public «Σχετικά» step by step
// (text, photos, what it offers, who it's for, amenities), picks tags from the
// canonical lists and publishes the draft. The API is stubbed.

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
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const vocabulary = {
  discipline_groups: [
    { key: "strength", items: ["strength", "powerlifting", "olympic_lifting", "bodybuilding", "strongman", "kettlebell"] },
    { key: "functional", items: ["crossfit", "functional_fitness", "hyrox", "hiit", "bootcamp", "circuit_training", "calisthenics", "gymnastics"] },
    { key: "endurance", items: ["running", "indoor_cycling", "cycling", "rowing", "endurance", "ems_training"] },
    { key: "mind_body", items: ["yoga", "hot_yoga", "pilates", "pilates_reformer", "barre", "mobility", "stretching", "tai_chi_qigong"] },
    { key: "combat", items: ["boxing", "kickboxing", "muay_thai", "mma", "bjj_grappling", "wrestling", "martial_arts", "self_defense"] },
    { key: "dance", items: ["dance", "dance_fitness", "pole_aerial"] },
    { key: "aquatic", items: ["swimming", "aqua_fitness"] },
    { key: "outdoor", items: ["outdoor_training", "climbing_bouldering"] },
    { key: "recovery", items: ["physio_rehab", "sports_massage", "recovery"] },
  ],
  audiences: ["beginners", "women_only", "kids", "teens", "over_40", "seniors", "prenatal_postnatal", "adaptive", "athletes", "students", "lgbtq_friendly", "returning_from_injury"],
  amenities: ["showers", "changing_rooms", "lockers", "towels", "parking", "bike_parking", "public_transport_nearby", "air_conditioning", "sauna", "cold_plunge", "childcare", "wheelchair_accessible", "accessible_restroom", "gender_neutral_restroom", "wifi", "water_refill", "outdoor_area", "drop_in_friendly"],
  services: ["personal_training", "small_group_training", "open_gym", "nutrition_coaching", "online_coaching", "corporate"],
};

const photo = (id: string) => ({ id, purpose: "box_photo", status: "ready", content_type: "image/png", width: 1200, height: 800, url: `http://media.localhost:18080/media_public/${id}.png` });

// A small warm gradient PNG.
const PNG = Buffer.from(
  "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",
  "base64",
);

const STAFF = [
  { id: "coach-1", nickname: "Στέλιος", avatar_url: null },
  { id: "coach-2", nickname: "Κώστας", avatar_url: null },
];

type Calls = { saves: Array<Record<string, unknown>>; published: number; suggestions: Array<Record<string, unknown>> };

async function stubApi(page: Page, calls: Calls, start: Record<string, unknown> = {}) {
  let profile: Record<string, unknown> = {
    about: null,
    disciplines: [],
    audiences: [],
    amenities: [],
    services: [],
    languages: [],
    cover: null,
    photos: [],
    published: false,
    published_at: null,
    unpublished_changes: false,
    missing: ["about", "disciplines"],
    lock_version: 0,
    coaches: [],
    coach_candidates: STAFF,
    ...start,
  };
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("http://media.localhost:18080/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: PNG }));
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
  await page.route("**/api/box-vocabulary", (route) => route.fulfill(json(vocabulary)));
  await page.route("**/api/org/*/admin/public-profile", async (route) => {
    if (route.request().method() === "PUT") {
      const body = route.request().postDataJSON() as Record<string, unknown>;
      calls.saves.push(body);
      const photos = (body.photo_ids as string[]).map(photo);
      const cover = body.cover_photo_id ? photo(body.cover_photo_id as string) : null;
      profile = {
        ...profile,
        ...body,
        photos,
        cover,
        coaches: STAFF.filter((coach) => ((body.coach_ids as string[] | undefined) ?? []).includes(coach.id)),
        lock_version: (profile.lock_version as number) + 1,
        unpublished_changes: Boolean(profile.published),
      };
    }
    await route.fulfill(json({ profile }));
  });
  await page.route("**/api/org/*/admin/public-profile/publish", async (route) => {
    calls.published += 1;
    profile = { ...profile, published: true, published_at: "2026-10-19T10:00:00Z", unpublished_changes: false, missing: [] };
    await route.fulfill(json({ profile }));
  });
  await page.route("**/api/org/*/admin/public-profile/suggestions", async (route) => {
    calls.suggestions.push(route.request().postDataJSON() as Record<string, unknown>);
    await route.fulfill(json({ suggestion: { id: "s-1", status: "pending" } }, 201));
  });
}

async function shot(page: Page, name: string) {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${test.info().project.name}-${name}.png`, fullPage: true });
}

test.describe("admin public page editor", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
  });

  test("walks the steps, picks tags and publishes the draft", async ({ page }) => {
    const calls: Calls = { saves: [], published: 0, suggestions: [] };
    await stubApi(page, calls);
    await page.goto("/admin/public-page");
    await expect(page.getByRole("heading", { name: "Δημόσια σελίδα" })).toBeVisible();
    await expect(page.getByText("Πρόχειρο", { exact: true })).toBeVisible();
    const publish = page.getByRole("button", { name: "Δημοσίευση", exact: true });
    await expect(publish).toBeDisabled();

    await page.getByRole("textbox", { name: "Κείμενο" }).fill("Ένα μικρό box στην Κυψέλη, με προπονητές που σε ξέρουν με το όνομά σου.");
    await page.getByRole("button", { name: "Επόμενο" }).click();
    await expect(page.getByRole("button", { name: "Πρόσθεσε φωτογραφία εξωφύλλου" })).toBeVisible();
    await page.getByRole("button", { name: "Επόμενο" }).click();

    await page.getByRole("button", { name: "Επεξεργασία: Αθλήματα" }).click();
    const picker = page.getByRole("dialog", { name: "Αθλήματα" });
    await picker.getByRole("button", { name: /Λειτουργική & CrossFit/ }).click();
    await picker.getByRole("button", { name: "CrossFit", exact: true }).click();
    await picker.getByRole("button", { name: "HYROX", exact: true }).click();
    await picker.getByRole("searchbox").fill("αρση");
    await picker.getByRole("button", { name: /Άρση βαρών/ }).click();
    await picker.getByRole("searchbox").fill("");
    await expect(picker.getByText("Επιλεγμένα (3)")).toBeVisible();
    await shot(page, "admin-public-page-picker");
    await picker.getByRole("button", { name: "Τέλος" }).click();
    await expect(page.getByRole("region", { name: "Αθλήματα" }).getByText("HYROX")).toBeVisible();

    await page.getByRole("button", { name: "Επόμενο" }).click();
    await page.getByRole("button", { name: "Επεξεργασία: Απευθύνεται σε" }).click();
    const audiences = page.getByRole("dialog", { name: "Απευθύνεται σε" });
    await expect(audiences.getByRole("button", { name: "Επιστροφή μετά από τραυματισμό" })).toHaveCount(0);
    await audiences.getByRole("button", { name: "Τμήματα μόνο για γυναίκες" }).click();
    await audiences.getByRole("button", { name: "Τέλος" }).click();
    await page.getByRole("button", { name: "Επεξεργασία: Γλώσσες" }).click();
    const languages = page.getByRole("dialog", { name: "Γλώσσες" });
    await languages.getByRole("button", { name: "Ελληνικά" }).click();
    await languages.getByRole("searchbox").fill("ukrain");
    await languages.getByRole("button", { name: /Українська/ }).click();
    await languages.getByRole("button", { name: "Τέλος" }).click();
    await shot(page, "admin-public-page");

    await expect(publish).toBeEnabled();
    await publish.click();
    await expect(page.getByText("Δημοσιευμένη", { exact: true })).toBeVisible();
    expect(calls.published).toBe(1);
    expect(calls.saves.at(-1)).toMatchObject({
      disciplines: ["crossfit", "hyrox", "olympic_lifting"],
      audiences: ["women_only"],
      languages: ["el", "uk"],
    });
  });

  test("sets a gallery photo as the cover and suggests a missing tag", async ({ page }) => {
    const calls: Calls = { saves: [], published: 0, suggestions: [] };
    await stubApi(page, calls, {
      about: "Box",
      disciplines: ["crossfit"],
      photos: [photo("p-1"), photo("p-2"), photo("p-3")],
      published: true,
      missing: [],
      lock_version: 4,
    });
    await page.goto("/admin/public-page");
    await expect(page.getByText("Δημοσιευμένη", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Φωτογραφίες" }).click();
    await page.getByRole("button", { name: "Η φωτογραφία 2 ως εξώφυλλο" }).click();
    await expect(page.getByRole("img", { name: "Φωτογραφία εξωφύλλου" })).toBeVisible();
    await page.getByRole("button", { name: "Αποθήκευση πρόχειρου" }).click();
    await expect(page.getByText("Μη δημοσιευμένες αλλαγές", { exact: true })).toBeVisible();
    expect(calls.saves.at(-1)).toMatchObject({ cover_photo_id: "p-2", photo_ids: ["p-1", "p-3"], lock_version: 4 });
    await shot(page, "admin-public-page-photos");

    await page.getByRole("button", { name: "Παροχές" }).click();
    await page.getByRole("button", { name: "Επεξεργασία: Παροχές" }).click();
    const amenities = page.getByRole("dialog", { name: "Παροχές" });
    await amenities.getByRole("searchbox").fill("Ρινγκ πυγμαχίας");
    await amenities.getByRole("button", { name: "Δεν το βρίσκεις; Πρότεινε «Ρινγκ πυγμαχίας»" }).click();
    await amenities.getByRole("button", { name: "Αποστολή" }).click();
    await expect(amenities.getByText("Ευχαριστούμε, θα το δούμε.")).toBeVisible();
    expect(calls.suggestions).toEqual([{ list: "amenities", name: "Ρινγκ πυγμαχίας" }]);
    await amenities.getByRole("button", { name: "Τέλος" }).click();

    // Board 4 Q4: the owner picks which staff the page shows as coaches.
    await page.getByRole("button", { name: "Coaches", exact: true }).click();
    await page.getByRole("switch", { name: "Κώστας" }).check();
    await page.getByRole("button", { name: "Αποθήκευση πρόχειρου" }).click();
    await expect(page.getByRole("switch", { name: "Κώστας" })).toBeChecked();
    expect(calls.saves.at(-1)).toMatchObject({ coach_ids: ["coach-2"] });
  });
});

test.describe("platform tag suggestions", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
  });

  test("platform staff mark a suggestion added", async ({ page }) => {
    const resolved: Array<{ id: string; body: unknown }> = [];
    await stubApi(page, { saves: [], published: 0, suggestions: [] });
    await page.route("**/api/auth/me", (route) => route.fulfill(json({ ...user, vendor: true })));
    await page.route("**/api/platform/tag-suggestions", (route) =>
      route.fulfill(
        json({
          suggestions: [
            { id: "s-1", list: "disciplines", name: "Animal flow", status: "pending", organization_name: "Box Kypseli", inserted_at: "2026-10-19T09:00:00Z" },
            { id: "s-2", list: "amenities", name: "Ρινγκ πυγμαχίας", status: "pending", organization_name: "Fight Club Πατησίων", inserted_at: "2026-10-18T09:00:00Z" },
          ],
        }),
      ),
    );
    await page.route("**/api/platform/tag-suggestions/*", async (route) => {
      resolved.push({ id: route.request().url().split("/").pop()!, body: route.request().postDataJSON() });
      await route.fulfill({ status: 204, body: "" });
    });
    await page.goto("/platform/tag-suggestions");
    await expect(page.getByRole("heading", { name: "Προτάσεις ετικετών" })).toBeVisible();
    await shot(page, "platform-tag-suggestions");
    await page.getByRole("button", { name: "Σημείωση ως προστεθειμένο: Animal flow" }).click();
    await expect(page.getByText("Animal flow")).toHaveCount(0);
    expect(resolved).toEqual([{ id: "s-1", body: { status: "added" } }]);
  });
});
