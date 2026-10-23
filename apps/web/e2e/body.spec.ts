import { expect, test, type Page, type Route } from "./support/test";

// P2-M10 (ADR-158, board 13): Ημερολόγιο › Σώμα. The empty state, a new
// measurement with the first-weight question, «Μόνο τάση» showing no
// numbers, comparing two snapshots, the body-photo consent before the first
// photo (gallery path; the presigned PUT is stubbed), and the two-step
// before/after share. The API is stubbed; unlisted routes answer {}.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

// A 4×3 PNG, small enough to inline.
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGM4EaABRww4OQAsNg8BoqhHXQAAAABJRU5ErkJggg==", "base64");

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({
      sub: user.id,
      role: "member",
      memberships: [{ organization_slug: "kypseli", organization_id: "org-1" }],
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const catalog = [
  { key: "weight", min: 20, max: 400, unit: "kg", sensitive: true },
  { key: "body_fat", min: 2, max: 75, unit: "%", sensitive: true },
  ...["waist", "hips", "chest", "arm", "thigh", "neck", "calf", "arm_left", "arm_right", "thigh_left", "thigh_right"].map((key) => ({
    key,
    min: 5,
    max: 250,
    unit: "cm",
    sensitive: false,
  })),
];

type Settings = {
  units: "metric" | "imperial";
  weight_display: "number" | "trend" | "hidden";
  journal_sections: { body?: boolean; wellness?: boolean; cravings?: boolean };
  measure_reminder_weeks: number | null;
  default_visibility: "private" | "coach_numbers" | "coach_full";
  blur_photos: boolean;
  compare_mode: "slider" | "side_by_side";
};

const defaults = (): Settings => ({
  units: "metric",
  weight_display: "number",
  journal_sections: { body: true, wellness: true, cravings: true },
  measure_reminder_weeks: null,
  default_visibility: "private",
  blur_photos: false,
  compare_mode: "slider",
});

const photo = (id: string, pose: "front" | "side" | "back", snapshotId: string) => ({
  id,
  pose,
  status: "ready",
  snapshot_id: snapshotId,
  width: 1200,
  height: 1600,
  thumb_url: `/__media/${id}-thumb.png`,
  feed_url: `/__media/${id}-feed.png`,
  full_url: `/__media/${id}-full.png`,
  placeholder: null,
});

function snapshot(id: string, takenAt: string, extra: Record<string, unknown> = {}) {
  return {
    id,
    taken_at: takenAt,
    taken_tz: "Europe/Athens",
    units: "metric",
    metrics: {},
    withheld_metrics: [],
    weight_display: "number",
    visibility: "private",
    photo_count: 0,
    photos: [],
    notes: null,
    source: "manual",
    ...extra,
  };
}

type Calls = {
  settings: unknown[];
  created: Record<string, unknown>[];
  consents: string[];
  uploads: unknown[];
  puts: string[];
  shares: Record<string, unknown>[];
};

type World = {
  settings: Settings;
  snapshots: ReturnType<typeof snapshot>[];
  consents: { scope: string; active: boolean; granted_at?: string | null; withdrawn_at?: string | null }[];
  series?: (metric: string, range: string) => unknown;
  compare?: (from: string, to: string) => unknown;
};

async function stub(page: Page, world: World) {
  const { user, token } = persona();
  const calls: Calls = { settings: [], created: [], consents: [], uploads: [], puts: [], shares: [] };
  const settingsResponse = () => ({
    settings: world.settings,
    catalog,
    photos: { content_types: ["image/heic", "image/heif", "image/jpeg", "image/png", "image/webp"], max_bytes: 26214400, max_photos: 4, poses: ["front", "side", "back", "other"] },
    ranges: ["1m", "3m", "1y", "all"],
    max_reminder_weeks: 12,
  });

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" } }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/__media/**", (route) => route.fulfill({ status: 200, contentType: "image/png", body: PNG }));
  await page.route("**/__upload/**", (route) => {
    calls.puts.push(route.request().url().split("/").pop()!);
    return route.fulfill({ status: 200, body: "" });
  });

  await page.route(/\/api\/me\/body\//, async (route: Route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api\/me\/body/, "");
    const method = request.method();

    if (path === "/settings") {
      if (method === "PUT") {
        const change = request.postDataJSON();
        calls.settings.push(change);
        world.settings = {
          ...world.settings,
          ...change,
          journal_sections: { ...world.settings.journal_sections, ...(change.journal_sections ?? {}) },
        };
      }
      return route.fulfill(json(settingsResponse()));
    }
    if (path === "/snapshots" && method === "GET") return route.fulfill(json({ snapshots: world.snapshots, next_cursor: null }));
    if (path === "/snapshots" && method === "POST") {
      const body = request.postDataJSON();
      calls.created.push(body);
      const created = snapshot("new-1", body.taken_at ?? new Date().toISOString(), { metrics: body.metrics ?? {}, visibility: body.visibility });
      world.snapshots = [created, ...world.snapshots];
      return route.fulfill(json({ snapshot: created }, 201));
    }
    const one = path.match(/^\/snapshots\/([^/]+)$/);
    if (one && method === "GET") {
      const found = world.snapshots.find((item) => item.id === one[1]);
      return route.fulfill(found ? json({ snapshot: found }) : json({ code: "not_found" }, 404));
    }
    if (path === "/series") {
      const metric = url.searchParams.get("metric")!;
      const range = url.searchParams.get("range")!;
      return route.fulfill(json(world.series?.(metric, range) ?? { metric, range, display: "number", points: [], trend: null, unit: "kg", units: "metric" }));
    }
    if (path === "/compare") return route.fulfill(json(world.compare!(url.searchParams.get("from")!, url.searchParams.get("to")!)));
    if (path === "/consents") return route.fulfill(json({ consents: world.consents }));
    const consent = path.match(/^\/consents\/(\w+)$/);
    if (consent && method === "PUT") {
      calls.consents.push(consent[1]);
      world.consents = [{ scope: consent[1], active: true, granted_at: "2026-10-20T08:00:00Z", withdrawn_at: null }];
      return route.fulfill(json({ consents: world.consents }));
    }
    if (path === "/photos/latest") return route.fulfill(json({ photos: [] }));
    if (path === "/photos/uploads") {
      calls.uploads.push(request.postDataJSON());
      return route.fulfill(
        json({ media_id: "media-1", upload_url: "/__upload/media-1", required_headers: { "content-type": "image/png" }, max_bytes: 26214400, expires_in: 900 }),
      );
    }
    if (path === "/access-log") return route.fulfill(json({ entries: [] }));
    if (path === "/share") {
      calls.shares.push(request.postDataJSON());
      return route.fulfill(json({ post: { id: "post-1" } }, 201));
    }
    return route.fulfill(json({}));
  });
  return calls;
}

const withPhotos = () => [
  snapshot("s2", "2026-10-14T08:00:00Z", {
    metrics: { weight: 72.4, waist: 81 },
    photo_count: 1,
    photos: [photo("p2", "front", "s2")],
  }),
  snapshot("s1", "2026-07-01T08:00:00Z", {
    metrics: { weight: 74.5, waist: 85 },
    photo_count: 1,
    photos: [photo("p1", "front", "s1")],
  }),
];

test.describe("Ημερολόγιο › Σώμα", () => {
  test("an empty Σώμα explains what it is for and that it is private", async ({ page }) => {
    await stub(page, { settings: defaults(), snapshots: [], consents: [] });
    await page.goto("/journal/body");
    await expect(page.getByRole("heading", { name: "Track your body, privately" })).toBeVisible();
    await expect(page.getByText(/Private by default/)).toBeVisible();
    await expect(page.getByRole("link", { name: "New measurement" })).toHaveAttribute("href", "/journal/body/new");
  });

  test("lists snapshots newest first with the change since the previous one", async ({ page }) => {
    await stub(page, {
      settings: defaults(),
      snapshots: withPhotos(),
      consents: [],
      series: (metric, range) => ({
        metric,
        range,
        display: "number",
        unit: "kg",
        units: "metric",
        trend: "down",
        points: [
          { at: "2026-07-01T08:00:00Z", value: 74.5, smoothed: 74.5 },
          { at: "2026-10-14T08:00:00Z", value: 72.4, smoothed: 73.9 },
        ],
      }),
    });
    await page.goto("/journal/body");
    const rows = page.getByTestId("body-snapshot");
    await expect(rows).toHaveCount(2);
    await expect(rows.first()).toContainText("Oct 14, 2026");
    await expect(rows.first()).toContainText("−2.1 kg");
    await expect(page.getByTestId("body-chart")).toHaveAttribute("data-display", "number");
    await expect(page.getByTestId("body-chart")).toContainText("72.4 kg");
  });

  test("a new measurement needs one value, asks how to show the first weight, and saves", async ({ page }) => {
    const calls = await stub(page, { settings: defaults(), snapshots: [], consents: [] });
    await page.goto("/journal/body/new");
    await page.getByRole("button", { name: "Save snapshot" }).click();
    await expect(page.getByText("Add at least one measurement or one photo.")).toBeVisible();
    expect(calls.created).toHaveLength(0);

    await page.getByLabel("Weight").fill("72,4");
    await page.getByLabel("Waist").fill("81");
    await page.getByRole("button", { name: "Save snapshot" }).click();
    const question = page.getByRole("dialog", { name: "How do you want to see your weight?" });
    await expect(question).toBeVisible();
    await question.getByRole("radio", { name: /Trend only/ }).click();
    await question.getByRole("button", { name: "Save" }).click();

    await expect(page).toHaveURL(/\/journal\/body$/);
    expect(calls.settings).toContainEqual({ weight_display: "trend" });
    expect(calls.created[0]).toMatchObject({ metrics: { weight: 72.4, waist: 81 }, visibility: "private", units: "metric" });
  });

  test("trend only shows a line and words, never a weight number", async ({ page }) => {
    await stub(page, {
      settings: { ...defaults(), weight_display: "trend" },
      snapshots: [
        snapshot("s2", "2026-10-14T08:00:00Z", { metrics: { waist: 81 }, withheld_metrics: ["weight"], weight_display: "trend" }),
        snapshot("s1", "2026-07-01T08:00:00Z", { metrics: { waist: 85 }, withheld_metrics: ["weight"], weight_display: "trend" }),
      ],
      consents: [],
      series: (metric, range) => ({ metric, range, display: "trend", unit: "kg", units: "metric", trend: "slightly_down",
        points: [],
        shape: [
          { at: "2026-08-01T08:00:00Z", y: 1 },
          { at: "2026-08-15T08:00:00Z", y: 0.4 },
          { at: "2026-08-29T08:00:00Z", y: 0 },
        ],
      }),
    });
    await page.goto("/journal/body");
    const chart = page.getByTestId("body-chart");
    await expect(chart).toHaveAttribute("data-display", "trend");
    await expect(page.getByTestId("body-trend-word")).toHaveText("Slightly down");
    // The line is the server's real 0..1 shape, not a drawing from the word.
    await expect(page.getByTestId("body-trend-line")).toHaveAttribute("d", "M0.0,6.0L150.0,42.0L300.0,66.0");
    await expect(chart).not.toContainText(/kg/);
    await expect(page.locator("main")).not.toContainText(/\d+(?:[.,]\d+)? kg/);
    // Circumferences still show as numbers.
    await expect(page.getByTestId("body-snapshot").first()).toContainText("81 cm");
  });

  test("compare shows the slider by default, deltas in numbers and words, and remembers side by side", async ({ page }) => {
    const snapshots = withPhotos();
    const calls = await stub(page, {
      settings: defaults(),
      snapshots,
      consents: [],
      compare: () => ({
        from: snapshots[1],
        to: snapshots[0],
        units: "metric",
        deltas: [
          { metric: "weight", delta: null, direction: "slightly_down" },
          { metric: "waist", delta: -4, direction: "down" },
        ],
      }),
    });
    await page.goto("/journal/body/compare");
    await expect(page.getByTestId("compare-slider")).toBeVisible();
    const deltas = page.getByTestId("compare-deltas");
    await expect(deltas).toContainText("Slightly down");
    await expect(deltas).toContainText("−4 cm");
    await expect(page.getByRole("button", { name: "Share a before and after" })).toHaveCount(0);

    await page.getByRole("button", { name: "Side by side" }).click();
    await expect(page.getByTestId("compare-side-by-side")).toBeVisible();
    await expect.poll(() => calls.settings).toContainEqual({ compare_mode: "side_by_side" });
  });

  test("the first photo asks for consent in plain words, then uploads from the gallery", async ({ page }) => {
    const calls = await stub(page, { settings: defaults(), snapshots: [], consents: [] });
    await page.goto("/journal/body/new");
    await page.getByRole("button", { name: "Add photo: Front" }).click();
    const consent = page.getByRole("dialog", { name: "Body photos" });
    await expect(consent).toContainText("Only you see them.");
    await expect(consent.getByRole("button", { name: "Without photos" })).toBeVisible();
    await consent.getByRole("button", { name: "I agree" }).click();
    expect(calls.consents).toEqual(["body_photos"]);

    const camera = page.getByTestId("body-camera");
    await expect(camera).toBeVisible();
    await camera.getByTestId("body-gallery-input").setInputFiles({ name: "front.png", mimeType: "image/png", buffer: PNG });
    await expect(camera).toBeHidden();
    await expect(page.getByTestId("pose-slot-front")).toHaveAttribute("data-phase", "ready");
    expect(calls.uploads).toEqual([{ content_type: "image/png", byte_size: PNG.length }]);
    expect(calls.puts).toEqual(["media-1"]);

    await page.getByRole("button", { name: "Save snapshot" }).click();
    await expect(page).toHaveURL(/\/journal\/body$/);
    expect(calls.created[0]).toMatchObject({ photos: [{ media_id: "media-1", pose: "front" }] });
    expect(calls.created[0].metrics).toEqual({});
  });

  test("sharing a before/after explains it, then needs a second, separate confirmation", async ({ page }) => {
    const calls = await stub(page, { settings: { ...defaults(), blur_photos: true }, snapshots: withPhotos(), consents: [] });
    await page.goto("/journal/body/s2");
    await expect(page.getByTestId("body-photo").first()).toHaveAttribute("data-blurred", "true");

    const share = page.getByRole("button", { name: "Share a before and after" });
    await expect(share).toHaveText("");
    await share.click();
    const dialog = page.getByRole("dialog", { name: "Share a before and after" });
    await expect(dialog).toContainText("No measurement is added");
    await dialog.getByLabel("Text (optional)").fill("Three months of Tuesdays");
    await dialog.getByRole("button", { name: "Next" }).click();

    const confirm = page.getByRole("dialog", { name: "Post these photos?" });
    await expect(confirm).toContainText("My followers");
    expect(calls.shares).toHaveLength(0);
    await confirm.getByRole("button", { name: "Yes, post them" }).click();
    await expect(page.getByRole("dialog", { name: "Posted" })).toBeVisible();
    expect(calls.shares).toEqual([
      {
        from_snapshot_id: "s1",
        to_snapshot_id: "s2",
        pose: "front",
        text: "Three months of Tuesdays",
        audience: "followers",
        confirm: true,
      },
    ]);
  });
});
