import { expect, test, type Page, type Request } from "./support/test";

// Redesign Phase 2 M13 (ADR-161, plan board 16 A): Garmin on Εγώ ›
// Συνδεδεμένες συσκευές («Σύντομα» without credentials, the connect sheet,
// the connected row with «Συγχρονισμός τώρα», reconnect and disconnect) and
// in the journal (the device card, «Ήταν αυτό το …;», watch workouts in Ροή
// and the watch's numbers on a matched class). The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

function persona() {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    completed_tours: ["admin", "member", "athlete"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return { user, token: `stub.${payload}.signature` };
}

const ALL_ON = { activities: true, sleep: true, weight: true, resting_hr: true };
const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();

type Connection = {
  status: "active" | "error";
  last_synced_at: string | null;
  backfill_status: "none" | "running" | "done" | "failed";
  backfill_progress: number | null;
  needs_reconnect: boolean;
  sync_prefs?: Record<string, boolean>;
};

function garminRow(status: "unavailable" | "disconnected" | "connected" | "error", connection: Connection | null = null) {
  const configured = status !== "unavailable";
  return {
    provider: "garmin",
    status,
    configured,
    capability: configured ? "available" : "not_configured",
    sync_prefs: connection?.sync_prefs ?? ALL_ON,
    backfill_day_options: [0, 30, 90],
    connection: connection
      ? { connected_at: minutesAgo(600), backfill_days: 30, last_error: null, sync_prefs: ALL_ON, ...connection }
      : null,
  };
}

function devices(row: ReturnType<typeof garminRow>) {
  return {
    wallet: { passes: [], platforms: { apple: false, google: false } },
    calendar: { https_url: "https://example.com/cal.ics", webcal_url: "webcal://example.com/cal.ics", download_url: null },
    integrations: [row, { provider: "apple_health", status: "native_only" }, { provider: "health_connect", status: "native_only" }],
  };
}

async function common(page: Page) {
  const { user, token } = persona();
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
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
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/api/me/body/consents", (route) => route.fulfill(json({ consents: [{ scope: "health_data", active: false }] })));
}

async function devicesPage(page: Page, row: () => ReturnType<typeof garminRow>) {
  await common(page);
  await page.route("**/api/me/devices", (route) => route.fulfill(json(devices(row()))));
}

test.describe("Garmin on Συνδεδεμένες συσκευές", () => {
  test("without Garmin credentials the row says Coming soon", async ({ page }) => {
    await devicesPage(page, () => garminRow("unavailable"));
    await page.goto("/me/devices");
    const row = page.getByTestId("garmin-row");
    await expect(row).toContainText("Garmin Connect");
    await expect(row).toContainText("Coming soon");
    await expect(row.getByRole("button", { name: "Connect" })).toHaveCount(0);
  });

  test("the connect sheet sends the choices and the consent, then opens Garmin", async ({ page }) => {
    await devicesPage(page, () => garminRow("disconnected"));
    await page.route("https://connect.garmin.com/**", (route) =>
      route.fulfill({ status: 200, contentType: "text/html", body: "<html><body><h1>Garmin sign-in</h1></body></html>" }),
    );
    await page.route("**/api/me/devices/garmin/connect", (route) =>
      route.fulfill(json({ authorize_url: "https://connect.garmin.com/oauth2Confirm?state=abc", expires_at: new Date(Date.now() + 900_000).toISOString() })),
    );

    await page.goto("/me/devices");
    await page.getByTestId("garmin-row").getByRole("button", { name: "Connect" }).click();
    const sheet = page.getByRole("dialog", { name: "Connect Garmin" });
    await expect(sheet).toBeVisible();
    for (const name of ["Workouts", "Sleep", "Weight", "Resting heart rate"]) {
      await expect(sheet.getByRole("switch", { name })).toHaveAttribute("aria-checked", "true");
    }
    await expect(sheet.getByText("To Wellness")).toBeVisible();
    await expect(sheet.getByRole("radio", { name: "Last 30 days" })).toHaveAttribute("aria-checked", "true");

    await sheet.getByRole("switch", { name: "Weight" }).click();
    await sheet.getByRole("radio", { name: "90 days" }).click();
    const proceed = sheet.getByRole("button", { name: "Continue to Garmin" });
    await expect(proceed).toBeDisabled();
    await sheet.getByRole("checkbox").check();
    await page.screenshot({ path: "test-results/garmin/connect-sheet.png" });

    const posted = page.waitForRequest((request) => request.url().endsWith("/me/devices/garmin/connect") && request.method() === "POST");
    await proceed.click();
    expect(bodyOf(await posted)).toEqual({
      sync_prefs: { activities: true, sleep: true, weight: false, resting_hr: true },
      backfill_days: 90,
      health_data_consent: true,
    });
    await page.waitForURL(/connect\.garmin\.com/);
    await expect(page.getByRole("heading", { name: "Garmin sign-in" })).toBeVisible();
  });

  test("workouts only needs no health-data line", async ({ page }) => {
    await devicesPage(page, () => garminRow("disconnected"));
    await page.goto("/me/devices");
    await page.getByTestId("garmin-row").getByRole("button", { name: "Connect" }).click();
    const sheet = page.getByRole("dialog", { name: "Connect Garmin" });
    await expect(sheet.getByRole("checkbox")).toBeVisible();
    for (const name of ["Sleep", "Weight", "Resting heart rate"]) await sheet.getByRole("switch", { name }).click();
    await expect(sheet.getByRole("checkbox")).toHaveCount(0);
    await expect(sheet.getByRole("button", { name: "Continue to Garmin" })).toBeEnabled();
  });

  test("Garmin's return shows a toast and leaves the address clean", async ({ page }) => {
    await devicesPage(page, () => garminRow("connected", { status: "active", last_synced_at: null, backfill_status: "running", backfill_progress: 0, needs_reconnect: false }));
    await page.goto("/me/devices?garmin=connected");
    await expect(page.getByTestId("garmin-return")).toHaveText(/Garmin is connected\. Your data is on its way\./);
    await expect(page).toHaveURL(/\/me\/devices$/);

    await page.goto("/me/devices?garmin=error&reason=garmin_access_denied");
    await expect(page.getByTestId("garmin-return")).toContainText("You didn't allow access at Garmin");
    await page.getByTestId("garmin-return").getByRole("button", { name: "Dismiss" }).click();
    await expect(page.getByTestId("garmin-return")).toHaveCount(0);
  });

  test("connected: last sync, history progress, sync now (and too soon), what syncs", async ({ page }) => {
    let syncs = 0;
    await devicesPage(page, () => garminRow("connected", { status: "active", last_synced_at: minutesAgo(12), backfill_status: "running", backfill_progress: 40, needs_reconnect: false }));
    await page.route("**/api/me/devices/garmin/sync", (route) => {
      syncs += 1;
      if (syncs > 1) return route.fulfill(json({ code: "sync_too_soon", error: "Garmin was synced a moment ago" }, 429));
      return route.fulfill(json({ garmin: garminRow("connected", { status: "active", last_synced_at: minutesAgo(0), backfill_status: "running", backfill_progress: 40, needs_reconnect: false }) }));
    });
    await page.route("**/api/me/devices/garmin", (route) =>
      route.request().method() === "PATCH"
        ? route.fulfill(json({ garmin: garminRow("connected", { status: "active", last_synced_at: minutesAgo(0), backfill_status: "done", backfill_progress: 100, needs_reconnect: false, sync_prefs: { ...ALL_ON, sleep: false } }) }))
        : route.fallback(),
    );

    await page.goto("/me/devices");
    const row = page.getByTestId("garmin-row");
    await expect(row).toContainText("Active");
    await expect(row.getByTestId("garmin-last-sync")).toHaveText("Last synced 12′ ago");
    await expect(row).toContainText("Workouts, Sleep, Weight, Resting heart rate");
    await expect(row.getByRole("progressbar", { name: "Importing… 40%" })).toHaveAttribute("aria-valuenow", "40");
    await row.screenshot({ path: "test-results/garmin/connected-row.png" });

    await row.getByRole("button", { name: "Sync now" }).click();
    await expect(row.getByRole("status")).toHaveText("Asked Garmin to resend the last two days.");
    await expect(row.getByTestId("garmin-last-sync")).toHaveText("Last synced just now");
    await row.getByRole("button", { name: "Sync now" }).click();
    await expect(row.getByRole("status")).toHaveText("Garmin synced a moment ago. Try again in a few minutes.");

    const patched = page.waitForRequest((request) => request.url().endsWith("/me/devices/garmin") && request.method() === "PATCH");
    await row.getByRole("button", { name: "What syncs" }).click();
    await row.getByRole("switch", { name: "Sleep" }).click();
    await row.getByRole("button", { name: "Save" }).click();
    expect(bodyOf(await patched)).toEqual({ sync_prefs: { activities: true, sleep: false, weight: true, resting_hr: true } });
    await expect(row).toContainText("Workouts, Weight, Resting heart rate");
    await expect(row.getByRole("progressbar")).toHaveCount(0);
  });

  test("a broken link warns and reconnects through the same sheet", async ({ page }) => {
    await devicesPage(page, () => garminRow("error", { status: "error", last_synced_at: minutesAgo(3 * 24 * 60), backfill_status: "done", backfill_progress: 100, needs_reconnect: true }));
    await page.goto("/me/devices");
    const row = page.getByTestId("garmin-row");
    await expect(row).toContainText("Needs reconnecting");
    await expect(row.getByRole("alert")).toContainText("Garmin stopped answering");
    await expect(row.getByRole("button", { name: "Sync now" })).toHaveCount(0);
    await row.getByRole("button", { name: "Reconnect" }).click();
    await expect(page.getByRole("dialog", { name: "Reconnect Garmin" })).toBeVisible();
  });

  for (const choice of ["keep", "delete"] as const) {
    test(`disconnect asks once more and ${choice === "keep" ? "keeps" : "deletes"} the data`, async ({ page }) => {
      let connected = true;
      await devicesPage(page, () =>
        connected
          ? garminRow("connected", { status: "active", last_synced_at: minutesAgo(5), backfill_status: "done", backfill_progress: 100, needs_reconnect: false })
          : garminRow("disconnected"),
      );
      const deletes: string[] = [];
      await page.route(/\/api\/me\/devices\/garmin\?delete_data=/, (route) => {
        deletes.push(route.request().url());
        connected = false;
        return route.fulfill(json({ status: "revoked", deleted: choice === "delete" ? { activities: 3, sleep: 2, weight: 1, daily_stats: 4, imports: 10 } : null }));
      });

      await page.goto("/me/devices");
      await page.getByTestId("garmin-row").getByRole("button", { name: "Disconnect" }).click();
      const sheet = page.getByRole("dialog", { name: "Disconnect Garmin" });
      await expect(sheet.getByRole("radio", { name: /Keep what came in/ })).toHaveAttribute("aria-checked", "true");
      if (choice === "delete") await sheet.getByRole("radio", { name: /Delete all Garmin data/ }).click();
      await sheet.getByTestId("garmin-disconnect-confirm").click();
      await expect(sheet).toContainText(choice === "delete" ? "delete everything it brought in?" : "keep what came in?");
      expect(deletes).toEqual([]);
      await sheet.getByRole("button", { name: "Yes, disconnect" }).click();

      await expect(sheet).toBeHidden();
      expect(deletes).toHaveLength(1);
      expect(deletes[0]).toContain(choice === "delete" ? "delete_data=true" : "delete_data=false");
      await expect(page.getByTestId("devices-integrations").getByRole("status")).toHaveText(
        choice === "delete" ? "Garmin is disconnected and everything it brought in was deleted." : "Garmin is disconnected. What came in stays.",
      );
      await expect(page.getByTestId("garmin-row").getByRole("button", { name: "Connect" })).toBeVisible();
    });
  }
});

const at = (hour: number, minute = 0) => {
  const date = new Date();
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
};

function feedItem(kind: string, id: string, occurredAt: string, entry: Record<string, unknown>) {
  return { kind, id, occurred_at: occurredAt, occurred_tz: "UTC", journal_visibility: "private", choosable_visibilities: ["private", "coach_can_view"], entry };
}

const run = {
  id: "act-1",
  provider: "garmin",
  state: "own",
  sport: "run",
  activity_type: "running",
  title: "Morning run",
  started_at: at(7, 10),
  started_tz: "UTC",
  duration_seconds: 34 * 60,
  distance_meters: 6200,
  avg_heart_rate: 151,
  max_heart_rate: 178,
  calories: 420,
  journal_visibility: "private",
  candidates: [],
};

const fran = {
  id: "execution-1",
  master_workout_id: "wod-1",
  workout_title: "Fran",
  workout_type: "for_time",
  started_at_utc: at(18, 0),
  completed_at_utc: at(18, 52),
  completed_at_tz: "UTC",
  source: "class_booking",
  total_elapsed_ms: 252_000,
  scale_level_slug: null,
  status: "completed",
  device: { id: "act-2", provider: "garmin", sport: "strength", started_at: at(18, 0), duration_seconds: 52 * 60, distance_meters: null, avg_heart_rate: 148, max_heart_rate: 171, calories: 500 },
};

async function journalPage(page: Page, summary: Record<string, unknown>) {
  await common(page);
  await page.route("**/api/me/journal**", (route) =>
    route.fulfill(json({ items: [feedItem("execution", "execution-1", fran.completed_at_utc, fran), feedItem("device_activity", "act-1", run.started_at, run)], next_cursor: null })),
  );
  await page.route("**/api/me/devices/summary", (route) => route.fulfill(json(summary)));
}

const summary = {
  provider: "garmin",
  connected: true,
  status: "active",
  visible: true,
  new_total: 2,
  new_counts: { activity: 2, sleep: 0, weight: 0 },
  needs_confirmation: 1,
  latest_at: minutesAgo(30),
  seen_at: null as string | null,
  backfill_progress: 100,
};

test.describe("Garmin in the journal", () => {
  test("Ροή shows a watch workout and the watch's numbers on a matched class", async ({ page }) => {
    await journalPage(page, { ...summary, visible: false, new_total: 0, new_counts: {}, needs_confirmation: 0 });
    await page.goto("/journal");
    await expect(page.getByTestId("journal-device-card")).toHaveCount(0);

    const workout = page.getByTestId("journal-device-activity");
    await expect(workout).toContainText("Morning run");
    await expect(workout).toContainText("6.2 km · 34′ · avg 151 bpm");
    await expect(workout).toContainText("from Garmin");
    await expect(page.getByTestId("journal-device-attachment")).toHaveText(/from Garmin · 52′ · avg 148 bpm/);

    await workout.getByRole("button", { name: /Morning run/ }).click();
    const detail = page.getByRole("dialog", { name: "Morning run" });
    await expect(detail).toContainText("Highest heart rate");
    await expect(detail).toContainText("max 178 bpm");
    await expect(detail).not.toContainText(/kcal|calorie/i);
    // The header × and the footer button both close it.
    await detail.getByRole("button", { name: "Close" }).first().click();

    await page.getByTestId("journal-device-attachment").click();
    await expect(page.getByRole("dialog", { name: "Fran" })).toContainText("avg 148 bpm");
  });

  test("the device card opens the question, keeps the workout apart and marks itself seen", async ({ page }) => {
    let current = summary;
    await journalPage(page, summary);
    await page.unroute("**/api/me/devices/summary");
    await page.route("**/api/me/devices/summary", (route) => route.fulfill(json(current)));
    const seen = page.waitForRequest((request) => request.url().endsWith("/me/devices/summary/seen") && request.method() === "POST");
    await page.route("**/api/me/devices/summary/seen", (route) => {
      current = { ...summary, visible: false, new_total: 0, new_counts: { activity: 0, sleep: 0, weight: 0 }, seen_at: new Date().toISOString() };
      return route.fulfill(json(current));
    });
    const pendingActivity = {
      ...run,
      id: "act-3",
      state: "pending",
      sport: "strength",
      title: "Strength training",
      started_at: at(18, 2),
      distance_meters: null,
      candidates: [
        { kind: "class", id: "class-1", organization_id: "org-1", title: "CrossFit", starts_at: at(18, 0), ends_at: at(19, 0) },
        { kind: "training_log", id: "log-1", organization_id: null, title: "Open gym", starts_at: at(18, 10), ends_at: at(19, 0) },
      ],
    };
    await page.route("**/api/me/devices/garmin/pending", (route) =>
      route.fulfill(json({ imports: [{ id: "import-1", kind: "activity", received_at: minutesAgo(20), activity: pendingActivity }] })),
    );
    const confirmed = page.waitForRequest((request) => request.url().endsWith("/me/device-imports/import-1/confirm") && request.method() === "POST");
    await page.route("**/api/me/device-imports/import-1/confirm", (route) => route.fulfill(json({ activity: { ...pendingActivity, state: "own", candidates: [] } })));

    await page.goto("/journal");
    const card = page.getByTestId("journal-device-card");
    await expect(card).toContainText("Garmin · 2 new workouts");
    await expect(card).toContainText("1 needs confirming");
    await page.screenshot({ path: "test-results/garmin/journal-card.png", fullPage: true });
    await card.click();
    await seen;

    const question = page.getByRole("dialog", { name: /^Was this CrossFit .+\?$/ });
    await expect(question).toBeVisible();
    await expect(question.getByRole("radio", { name: /CrossFit/ })).toHaveAttribute("aria-checked", "true");
    await expect(question.getByRole("radio", { name: /Open gym/ })).toBeVisible();
    await page.screenshot({ path: "test-results/garmin/pending-sheet.png" });
    await question.getByRole("radio", { name: /Separate workout/ }).click();
    await question.getByRole("button", { name: "Confirm" }).click();
    expect(bodyOf(await confirmed)).toEqual({ as_new: true });

    const recent = page.getByRole("dialog", { name: "New from Garmin" });
    await expect(recent).toContainText("Morning run");
    // The header × and the footer button both close it.
    await recent.getByRole("button", { name: "Close" }).first().click();
    await expect(card).toHaveCount(0);
  });

  test("a merged choice sends the candidate", async ({ page }) => {
    await journalPage(page, { ...summary, new_counts: { activity: 0 }, new_total: 0 });
    await page.route("**/api/me/devices/garmin/pending", (route) =>
      route.fulfill(
        json({
          imports: [
            {
              id: "import-2",
              kind: "activity",
              received_at: minutesAgo(5),
              activity: { ...run, id: "act-4", state: "pending", candidates: [{ kind: "class", id: "class-9", title: "CrossFit", starts_at: at(18), ends_at: at(19) }, { kind: "execution", id: "exe-9", title: null, starts_at: at(18, 5), ends_at: at(18, 50) }] },
            },
          ],
        }),
      ),
    );
    const confirmed = page.waitForRequest((request) => request.url().endsWith("/me/device-imports/import-2/confirm"));
    await page.route("**/api/me/device-imports/import-2/confirm", (route) => route.fulfill(json({ activity: { ...run, state: "merged" } })));
    await page.goto("/journal");
    await page.getByTestId("journal-device-card").click();
    const question = page.getByRole("dialog", { name: /^Was this CrossFit/ });
    await question.getByRole("radio", { name: /Workout/ }).first().click();
    await question.getByRole("button", { name: "Confirm" }).click();
    expect(bodyOf(await confirmed)).toEqual({ target_id: "exe-9" });
    await expect(question).toBeHidden();
  });
});

test.describe("Garmin in Πρόοδος and the sync choices", () => {
  const point = (daysAgo: number, value: number) => {
    const date = new Date();
    date.setDate(date.getDate() - daysAgo);
    return { on: date.toISOString().slice(0, 10), value, source: "garmin" };
  };

  test("the resting heart rate card shows only with data, as an indicator", async ({ page }) => {
    await common(page);
    const ranges: string[] = [];
    await page.route("**/api/me/daily-stats?**", (route) => {
      const url = new URL(route.request().url());
      const range = url.searchParams.get("range") ?? "3m";
      ranges.push(`${url.searchParams.get("metric")}:${range}`);
      const points = range === "1m" ? [point(2, 52), point(1, 50), point(0, 49)] : [point(40, 55), point(2, 52), point(1, 50), point(0, 49)];
      return route.fulfill(
        json({ metric: "resting_hr", range, from: points[0].on, to: point(0, 0).on, points, latest: points[points.length - 1], average: range === "1m" ? 50 : 52, sources: ["garmin"] }),
      );
    });

    await page.goto("/journal/progress");
    const card = page.getByTestId("resting-hr-card");
    await expect(card).toContainText("Resting heart rate");
    await expect(card).toContainText("49 bpm");
    await expect(card).toContainText("Average 52 bpm over 4 days");
    await expect(card).toContainText("from Garmin");
    await expect(card).toContainText("not a medical reading");
    await card.getByRole("button", { name: "1 month" }).click();
    await expect(card).toContainText("Average 50 bpm over 3 days");
    expect(ranges).toEqual(["resting_hr:3m", "resting_hr:1m"]);
  });

  test("no data, no card", async ({ page }) => {
    await common(page);
    await page.route("**/api/me/daily-stats?**", (route) =>
      route.fulfill(json({ metric: "resting_hr", range: "3m", from: "2026-07-24", to: "2026-10-21", points: [], latest: null, average: null, sources: [] })),
    );
    const read = page.waitForRequest((request) => request.url().includes("/me/daily-stats"));
    await page.goto("/journal/progress");
    await read;
    await expect(page.getByTestId("resting-hr-card")).toHaveCount(0);
  });

  test("turning on sleep asks for the health-data consent when the server needs it", async ({ page }) => {
    const workoutsOnly = { activities: true, sleep: false, weight: false, resting_hr: false };
    await devicesPage(page, () =>
      garminRow("connected", { status: "active", last_synced_at: minutesAgo(5), backfill_status: "done", backfill_progress: 100, needs_reconnect: false, sync_prefs: workoutsOnly }),
    );
    const bodies: Record<string, unknown>[] = [];
    await page.route("**/api/me/devices/garmin", (route) => {
      if (route.request().method() !== "PATCH") return route.fallback();
      const body = bodyOf(route.request());
      bodies.push(body);
      if (!body.health_data_consent) return route.fulfill(json({ code: "health_data_consent_required", error: "consent" }, 403));
      return route.fulfill(
        json({ garmin: garminRow("connected", { status: "active", last_synced_at: minutesAgo(5), backfill_status: "done", backfill_progress: 100, needs_reconnect: false, sync_prefs: { ...workoutsOnly, sleep: true } }) }),
      );
    });

    await page.goto("/me/devices");
    const row = page.getByTestId("garmin-row");
    await row.getByRole("button", { name: "What syncs" }).click();
    await row.getByRole("switch", { name: "Sleep" }).click();
    await row.getByRole("button", { name: "Save" }).click();
    await expect(row.getByRole("status")).toHaveText("Tick the health-data line to continue.");
    await expect(row.getByRole("button", { name: "Save" })).toBeDisabled();
    await row.getByRole("checkbox").check();
    await row.getByRole("button", { name: "Save" }).click();
    await expect(row).toContainText("Workouts, Sleep");
    expect(bodies).toEqual([
      { sync_prefs: { ...workoutsOnly, sleep: true } },
      { sync_prefs: { ...workoutsOnly, sleep: true }, health_data_consent: true },
    ]);
  });
});
