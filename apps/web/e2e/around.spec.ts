import { expect, test, type Page } from "./support/test";

// Redesign Phase 2 M6 (ADR-154, plan board 9): Γύρω μου. The first-visit area
// picker, the sections with «Δες όλα», the filter sheet with a saved filter and
// its alert, the compact map above the list, thin results and the
// «Φαίνομαι στο Γύρω μου» privacy toggle. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const inDays = (days: number, hour = 10) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
};

const user = {
  id: "member-1",
  nickname: "Maria",
  role: "member",
  email: "member@example.com",
  completed_tours: ["admin", "member", "athlete"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};
const token = `stub.${Buffer.from(
  JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
).toString("base64url")}.signature`;

const kypseli = { id: "11111111-1111-4111-8111-111111111111", slug: "kypseli", kind: "neighbourhood", name: "Κυψέλη", name_en: "Kypseli", city_slug: "athens", latitude: 38.003, longitude: 23.738 };
const patisia = { id: "22222222-2222-4222-8222-222222222222", slug: "patisia", kind: "neighbourhood", name: "Πατήσια", name_en: "Patisia", city_slug: "athens", latitude: 38.02, longitude: 23.73 };

const DEFAULT_FILTER = {
  v: 1,
  radius_km: 3,
  neighbourhood_ids: [],
  kinds: ["events", "boxes", "clubs"],
  disciplines: [],
  when: null,
  date_from: null,
  date_to: null,
  times: [],
  cost: [],
  max_price_cents: null,
  audiences: [],
  languages: [],
  amenities: [],
};

function event(id: string, title: string, days: number, extra: Record<string, unknown> = {}) {
  return {
    id,
    organization_id: "org-1",
    club_id: "club-1",
    club: { id: "club-1", name: "Box Κυψέλη", kind: "gym" },
    box: { name: "Box Κυψέλη", slug: "kypseli", logo_url: null },
    title,
    starts_at: inDays(days, 10),
    ends_at: inDays(days, 11),
    place: { name: "Box Κυψέλη", address: "Φωκίωνος Νέγρη 1", latitude: 38.002, longitude: 23.739, location_id: "loc-1" },
    capacity: 30,
    spots_left: 12,
    going_count: 18,
    waitlist_count: 0,
    price_cents: 0,
    currency: "EUR",
    open_to_non_members: true,
    guest_pass_allowed: false,
    guests_per_member: 0,
    goers: null,
    cancelled: false,
    can_rsvp: true,
    can_manage: false,
    my: null,
    ...extra,
  };
}

const box = {
  organization_id: "org-2",
  slug: "athens-barbell",
  name: "Athens Barbell",
  neighbourhood: "Κολωνάκι",
  city: "Αθήνα",
  disciplines: ["powerlifting"],
  audiences: [],
  amenities: [],
  languages: [],
  latitude: 37.979,
  longitude: 23.744,
  takes_trials: true,
  logo_url: null,
  cover_url: null,
  primary_color: null,
};

const club = {
  id: "club-9",
  name: "Saturday Run Λυκαβηττός",
  organization_id: "org-1",
  join_policy: "open",
  member_count: 88,
  membership: "none",
  role: null,
  box: { name: "Box Κυψέλη", slug: "kypseli", logo_url: null },
};

type Filter = typeof DEFAULT_FILTER;
type Calls = {
  searches: Array<{ filter: Filter; origin?: Record<string, unknown>; remember?: boolean }>;
  kinds: Array<Record<string, unknown>>;
  pins: Array<Record<string, unknown>>;
  areaSaves: unknown[];
  savedFilters: unknown[];
  alerts: unknown[];
  scopes: unknown[];
  visibility: unknown[];
};

function sections(filter: Filter, thin: boolean) {
  const events = thin ? [] : [event("event-1", "Open WOD για όλους", 3), event("event-2", "Run 8 km Λυκαβηττός", 4)];
  return {
    events: { items: events.map((item, index) => ({ distance_km: 0.4 + index, event: item })), next_cursor: null, total: thin ? 0 : 12 },
    boxes: { items: thin ? [] : [{ distance_km: 2.8, box }], next_cursor: null, total: thin ? 0 : 1, placement: "category" },
    clubs: { items: thin ? [] : [{ distance_km: 1.2, club }], next_cursor: null, total: thin ? 0 : 1 },
    posts: filter.kinds.includes("posts") ? { items: [], next_cursor: null, total: 0 } : null,
  };
}

async function stub(page: Page, { area = [kypseli] as unknown[], thin = false, visible = false, hasArea = true } = {}) {
  const calls: Calls = { searches: [], kinds: [], pins: [], areaSaves: [], savedFilters: [], alerts: [], scopes: [], visibility: [] };
  let currentArea = area;
  let saved: Array<Record<string, unknown>> = [];
  let aroundVisibility = { visible, has_area: hasArea };
  const filters = () => ({ surface: "around_me", last_used: null, saved });

  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  // A blank map style: no tiles from the network in tests.
  await page.route("https://tiles.openfreemap.org/**", (route) => route.fulfill(json({ version: 8, sources: {}, layers: [] })));
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Κυψέλη" },
          settings: { brand_name: "Box Κυψέλη", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/api/box-vocabulary", (route) =>
    route.fulfill(
      json({
        discipline_groups: [{ key: "strength", items: ["powerlifting", "crossfit", "hyrox"] }],
        audiences: ["beginners", "women_only", "over_40"],
        amenities: ["wheelchair_accessible"],
        services: [],
      }),
    ),
  );

  await page.route("**/api/me/filters/feed**", (route) => {
    if (route.request().method() === "PUT") {
      const body = route.request().postDataJSON();
      calls.scopes.push(body.params);
      return route.fulfill(json({ surface: "feed", last_used: body.params, saved: [] }));
    }
    return route.fulfill(json({ surface: "feed", last_used: null, saved: [] }));
  });
  await page.route("**/api/me/filters/around_me", (route) => {
    if (route.request().method() === "POST") {
      const body = route.request().postDataJSON();
      calls.savedFilters.push(body);
      saved = [...saved, { id: "saved-1", name: body.name, params: body.params, alert: false, last_used_at: new Date().toISOString() }];
    }
    return route.fulfill(json(filters()));
  });
  await page.route("**/api/me/filters/around_me/*/alert", (route) => {
    const body = route.request().postDataJSON();
    calls.alerts.push(body);
    saved = saved.map((entry) => ({ ...entry, alert: body.enabled }));
    return route.fulfill(json(filters()));
  });

  await page.route("**/api/me/around/area", (route) => {
    if (route.request().method() === "PUT") {
      const ids = route.request().postDataJSON().neighbourhood_ids as string[];
      calls.areaSaves.push(ids);
      currentArea = [kypseli, patisia].filter((place) => ids.includes(place.id));
    }
    return route.fulfill(json({ neighbourhoods: currentArea }));
  });
  await page.route("**/api/places/neighbourhoods?**", (route) => {
    const q = new URL(route.request().url()).searchParams.get("q") ?? "";
    return route.fulfill(json({ neighbourhoods: [kypseli, patisia].filter((place) => place.name.startsWith(q.slice(0, 3))) }));
  });

  await page.route("**/api/around/search", (route) => {
    const body = route.request().postDataJSON();
    calls.searches.push(body);
    if (currentArea.length === 0 && !body.origin) {
      return route.fulfill(json({ code: "origin_required", error: "Choose where to search from" }, 422));
    }
    const filter = { ...DEFAULT_FILTER, ...(body.filter ?? {}) };
    const isThin = thin && filter.radius_km < 10;
    return route.fulfill(
      json({
        active_filters: 0,
        filter,
        origin: { type: body.origin ? body.origin.type : "area", label: body.origin ? null : "Κυψέλη", latitude: 38.003, longitude: 23.738, neighbourhood_ids: [] },
        sections: sections(filter, isThin),
        wider: isThin
          ? [
              { radius_km: 10, total: 4, by_kind: { events: 4 } },
              { radius_km: 25, total: 12, by_kind: { events: 9, boxes: 3 } },
            ]
          : [],
      }),
    );
  });
  await page.route("**/api/around/search/events", (route) => {
    const body = route.request().postDataJSON();
    calls.kinds.push(body);
    const second = body.cursor === "page-2";
    const items = second
      ? [{ distance_km: 6.1, event: event("event-9", "Hyrox simulation", 9) }]
      : [
          { distance_km: 0.4, event: event("event-1", "Open WOD για όλους", 3) },
          { distance_km: 1.4, event: event("event-2", "Run 8 km Λυκαβηττός", 4) },
        ];
    return route.fulfill(
      json({ kind: "events", items, next_cursor: second ? null : "page-2", total: 3, origin: { type: "area", label: "Κυψέλη", latitude: 38.003, longitude: 23.738, neighbourhood_ids: [] } }),
    );
  });
  await page.route("**/api/around/pins", (route) => {
    calls.pins.push(route.request().postDataJSON());
    return route.fulfill(
      json({
        pins: [
          { id: "event-1", kind: "events", latitude: 38.002, longitude: 23.739, slug: null, title: "Open WOD για όλους" },
          { id: "org-2", kind: "boxes", latitude: 37.979, longitude: 23.744, slug: "athens-barbell", title: "Athens Barbell" },
        ],
        truncated: false,
      }),
    );
  });

  await page.route("**/api/me/social", (route) =>
    route.fulfill(
      json({
        posts_count: 0,
        followers_count: 0,
        following_count: 0,
        requests_count: 0,
        booking_sharing: { enabled: false, offered: true },
        member_visibility: { hidden: false },
        around_visibility: aroundVisibility,
      }),
    ),
  );
  await page.route("**/api/me/social/around-visibility", (route) => {
    const body = route.request().postDataJSON();
    calls.visibility.push(body);
    aroundVisibility = { ...aroundVisibility, visible: body.visible };
    return route.fulfill(json(aroundVisibility));
  });
  return calls;
}

const lastSearch = (calls: Calls) => calls.searches[calls.searches.length - 1];

test.describe("Γύρω μου", () => {
  test("first visit asks «Πού να ψάξουμε;», saves the area and shows what is near", async ({ page }) => {
    const calls = await stub(page, { area: [] });
    await page.goto("/around");

    await expect(page.getByRole("heading", { name: "Πού να ψάξουμε;" })).toBeVisible();
    await page.getByLabel("Γειτονιά ή πόλη").fill("Κυψ");
    await page.getByRole("button", { name: /Κυψέλη/ }).click();
    await expect(page.getByRole("list", { name: "Οι περιοχές σου" })).toContainText("Κυψέλη");
    await page.getByLabel("Γειτονιά ή πόλη").fill("Πατ");
    await page.getByRole("button", { name: /Πατήσια/ }).click();
    await page.getByRole("button", { name: "Κάνε κύρια: Πατήσια" }).click();
    await page.getByRole("button", { name: "Συνέχεια" }).click();

    await expect.poll(() => calls.areaSaves).toEqual([[patisia.id, kypseli.id]]);
    await expect(page.getByRole("heading", { name: "Events" })).toBeVisible();
    // The map also labels the event, so check the list entry.
    await expect(page.getByRole("link", { name: /Open WOD για όλους/ })).toBeVisible();
  });

  test("«Χρήση τοποθεσίας τώρα» searches from the rounded position without saving it", async ({ page, context, baseURL }) => {
    await context.setGeolocation({ latitude: 37.98765, longitude: 23.72749 });
    await context.grantPermissions(["geolocation"], { origin: baseURL });
    const calls = await stub(page, { area: [] });
    await page.goto("/around");

    await page.getByRole("button", { name: "Χρήση τοποθεσίας τώρα" }).click();
    await expect.poll(() => lastSearch(calls)?.origin).toEqual({ type: "point", latitude: 37.988, longitude: 23.727 });
    expect(lastSearch(calls).remember).toBe(false);
    expect(calls.areaSaves).toEqual([]);
    await expect(page.getByText("Αναζήτηση από: την τοποθεσία σου τώρα")).toBeVisible();
    await page.getByRole("button", { name: "Πίσω στην περιοχή μου" }).click();
    await expect(page.getByRole("heading", { name: "Πού να ψάξουμε;" })).toBeVisible();
  });

  test("a denied location says so and keeps the picker", async ({ page }) => {
    // What the browser answers when the person says no.
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "geolocation", {
        value: {
          getCurrentPosition: (_ok: unknown, fail: (error: { code: number; PERMISSION_DENIED: number }) => void) =>
            fail({ code: 1, PERMISSION_DENIED: 1 }),
        },
      });
    });
    await stub(page, { area: [] });
    await page.goto("/around");
    await page.getByRole("button", { name: "Χρήση τοποθεσίας τώρα" }).click();
    await expect(page.getByRole("alert").filter({ hasText: /τοποθεσία/ })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Πού να ψάξουμε;" })).toBeVisible();
  });

  test("the scope toggle opens Γύρω μου; sections link to «Δες όλα» with cursor paging", async ({ page }) => {
    const calls = await stub(page);
    await page.goto("/");
    await page.getByRole("navigation", { name: "Τι δείχνει η Αρχική" }).getByRole("link", { name: "Γύρω μου" }).click();
    await expect(page).toHaveURL(/\/around$/);
    await expect.poll(() => calls.scopes).toContainEqual({ scope: "around" });

    await expect(page.getByText("Από: Κυψέλη")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Box κοντά σου" })).toBeVisible();
    await expect(page.getByRole("link", { name: /Athens Barbell/ })).toHaveAttribute("href", "/b/athens-barbell");
    await expect(page.getByRole("link", { name: /Athens Barbell/ })).toContainText("Δοκιμαστικό");
    await expect(page.getByRole("heading", { name: "Ανοιχτά clubs" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Μπες" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Θα έρθω" }).first()).toBeVisible();
    await expect(page.getByRole("heading", { name: "Αναρτήσεις" })).toHaveCount(0);

    await page.getByRole("link", { name: "Δες όλα (12)" }).click();
    await expect(page).toHaveURL(/\/around\/events$/);
    await expect(page.getByRole("heading", { name: "Events", level: 1 })).toBeVisible();
    await expect(page.getByText("Run 8 km Λυκαβηττός")).toBeVisible();
    await page.getByRole("button", { name: "Περισσότερα" }).click();
    await expect(page.getByText("Hyrox simulation")).toBeVisible();
    expect(calls.kinds.map((body) => body.cursor ?? null)).toEqual([null, "page-2"]);
  });

  test("the filter sheet applies as you tap, saves «ΣΚ κοντά» and turns its alert on", async ({ page }) => {
    const calls = await stub(page);
    await page.goto("/around");
    // The map also labels the event, so check the list entry.
    await expect(page.getByRole("link", { name: /Open WOD για όλους/ })).toBeVisible();

    await page.getByRole("button", { name: "Φίλτρα", exact: true }).click();
    const sheet = page.getByRole("dialog", { name: "Φίλτρα" });
    await sheet.getByRole("button", { name: "Δωρεάν" }).click();
    await sheet.getByRole("button", { name: "Σαββατοκύριακο" }).click();
    await sheet.getByRole("button", { name: "Αναρτήσεις" }).click();
    await expect.poll(() => lastSearch(calls).filter).toMatchObject({ cost: ["free"], when: "weekend", kinds: ["events", "boxes", "clubs", "posts"] });

    await sheet.getByRole("button", { name: "Αποθήκευση ως…" }).click();
    const save = page.getByRole("dialog", { name: "Αποθήκευση φίλτρου" });
    await save.getByLabel("Όνομα").fill("ΣΚ κοντά");
    await save.getByRole("button", { name: "Αποθήκευση" }).click();
    await expect.poll(() => calls.savedFilters).toHaveLength(1);
    expect(calls.savedFilters[0]).toMatchObject({ name: "ΣΚ κοντά", params: { cost: ["free"], when: "weekend" } });

    await sheet.getByRole("button", { name: /Δείξε 14/ }).click();
    await expect(sheet).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Φίλτρα (3)" })).toBeVisible();
    await expect(page.getByRole("button", { name: "ΣΚ κοντά", exact: true })).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("heading", { name: "Αναρτήσεις" })).toBeVisible();

    await page.getByRole("button", { name: "Επιλογές για «ΣΚ κοντά»" }).click();
    const manage = page.getByRole("dialog", { name: "ΣΚ κοντά" });
    const alert = manage.getByRole("switch", { name: "Ειδοποίησέ με" });
    await expect(alert).toHaveAttribute("aria-checked", "false");
    await alert.click();
    await expect(alert).toHaveAttribute("aria-checked", "true");
    expect(calls.alerts).toEqual([{ enabled: true }]);
    await page.keyboard.press("Escape");
    await expect(manage).toHaveCount(0);

    // Clearing everything and tapping the saved chip brings the combination back.
    await page.getByRole("button", { name: "Καθαρισμός όλων των φίλτρων" }).click();
    // With the alert on, the chip says so to screen readers too.
    const chip = page.getByRole("button", { name: "ΣΚ κοντά (ειδοποιήσεις ενεργές)" });
    await expect(chip).toHaveAttribute("aria-pressed", "false");
    await chip.click();
    await expect.poll(() => lastSearch(calls).filter).toMatchObject({ cost: ["free"], when: "weekend" });
  });

  test("the map sits above the list: a pin highlights its row, full screen shows a card", async ({ page }) => {
    const calls = await stub(page);
    await page.goto("/around");
    const map = page.getByRole("region", { name: "Χάρτης Γύρω μου" });
    await expect(map).toBeVisible();
    await expect.poll(() => calls.pins.length).toBeGreaterThan(0);
    const bbox = calls.pins[0].bbox as { west: number; east: number; south: number; north: number };
    expect(bbox.east).toBeGreaterThan(bbox.west);
    await expect(map.getByText("2 σημεία")).toBeVisible();

    // Events and boxes look different.
    await expect(map.locator('[data-kind="events"]')).toHaveCount(1);
    await expect(map.locator('[data-kind="boxes"]')).toHaveCount(1);

    await map.getByRole("button", { name: "Event: Open WOD για όλους" }).click({ force: true });
    const row = page.locator('[data-around-id="event-1"]');
    await expect(row.getByRole("button", { name: "Στον χάρτη" })).toHaveAttribute("aria-pressed", "true");

    // A row's «Στον χάρτη» picks its pin.
    const boxRow = page.locator('[data-around-id="org-2"]').getByRole("button", { name: "Στον χάρτη" });
    await boxRow.click();
    await expect(boxRow).toHaveAttribute("aria-pressed", "true");
    await expect(row.getByRole("button", { name: "Στον χάρτη" })).toHaveAttribute("aria-pressed", "false");

    // Panning offers «Ψάξε εδώ» for the new viewport (when the browser can draw the map).
    const canvas = map.locator("canvas.maplibregl-canvas");
    if ((await canvas.count()) > 0) {
      await canvas.scrollIntoViewIfNeeded();
      const box = await canvas.boundingBox();
      if (box) {
        // Start away from the pins and the controls.
        await page.mouse.move(box.x + box.width * 0.75, box.y + box.height * 0.7);
        await page.mouse.down();
        await page.mouse.move(box.x + box.width * 0.75 - 120, box.y + box.height * 0.7 - 30, { steps: 10 });
        await page.mouse.up();
        const searchHere = map.getByRole("button", { name: "Ψάξε εδώ" });
        await expect(searchHere).toBeVisible();
        const before = calls.pins.length;
        await searchHere.click();
        await expect.poll(() => calls.pins.length).toBeGreaterThan(before);
        const moved = calls.pins[calls.pins.length - 1].bbox as typeof bbox;
        expect(moved).not.toEqual(bbox);
        await expect(searchHere).toHaveCount(0);
      }
    }

    await map.getByRole("button", { name: "Μεγάλος χάρτης" }).click();
    await expect(map.getByRole("button", { name: "Πίσω στη λίστα" })).toBeFocused();
    await map.getByRole("button", { name: "Box: Athens Barbell" }).click({ force: true });
    const card = map.getByRole("region", { name: "Box: Athens Barbell" });
    await expect(card.getByRole("link", { name: "Άνοιγμα" })).toHaveAttribute("href", "/b/athens-barbell");
    await page.keyboard.press("Escape");
    await expect(map.getByRole("button", { name: "Μεγάλος χάρτης" })).toBeFocused();
  });

  test("thin results offer wider radii with counts and remember the chosen one", async ({ page }) => {
    const calls = await stub(page, { thin: true });
    await page.goto("/around");
    await expect(page.getByRole("heading", { name: "Τίποτα έως 3 km" })).toBeVisible();
    await expect(page.getByText("Κανένα ανοιχτό event έως 3 km.")).toBeVisible();
    await page.getByRole("button", { name: "Έως 10 km · 4" }).click();
    await expect.poll(() => lastSearch(calls).filter.radius_km).toBe(10);
    expect(lastSearch(calls).remember).toBe(true);
    await expect(page.getByRole("heading", { name: "Τίποτα έως 3 km" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "≤ 10 km" })).toBeVisible();
  });

  test("«Φαίνομαι στο Γύρω μου» in Κοινοποίηση & ορατότητα", async ({ page }) => {
    const calls = await stub(page, { hasArea: false });
    await page.route(/\/api(?:\/org\/[^/]+)?\/pr-sharing$/, (route) => route.fulfill(json({ coach_visibility: true, grants: [] })));
    await page.route(/\/api(?:\/org\/[^/]+)?\/gamification\/preferences$/, (route) => route.fulfill(json({ preferences: { off_days: [0] } })));
    await page.goto("/me/sharing");
    const toggle = page.getByRole("switch", { name: "Φαίνομαι στο Γύρω μου" });
    await expect(toggle).toHaveAttribute("aria-checked", "false");
    await expect(page.getByText("Χρειάζεται να έχεις ορίσει «Η περιοχή μου»", { exact: false })).toBeVisible();
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-checked", "true");
    expect(calls.visibility).toEqual([{ visible: true }]);
    await expect(page.getByText(/σε επίπεδο γειτονιάς/)).toBeVisible();
  });
});
