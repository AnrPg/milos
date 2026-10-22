import { expect, test, type Page, type Request, type Route } from "@playwright/test";

// P3-M13 voice logging (ADR-175): «Με φωνή» in Νέα καταχώρηση records with
// the real browser recorder (Chromium's fake microphone), sends a 16 kHz
// mono WAV, and opens the parsed draft in the normal log form. Nothing is
// saved until the member confirms the form. The API is stubbed; every other
// route answers an empty object.

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
test.use({
  launchOptions: {
    ...(executablePath ? { executablePath } : {}),
    // A synthetic microphone (a beep) that needs no permission prompt.
    args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream"],
  },
  permissions: ["microphone"],
});

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const member = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  completed_tours: ["admin", "member", "athlete"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function memberToken() {
  const payload = Buffer.from(
    JSON.stringify({ sub: member.id, role: member.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const availability = (overrides: Record<string, unknown> = {}) => ({
  voice: { available: true, enabled: true, max_seconds: 60, daily_limit: 20, remaining_today: 20, ...overrides },
});

const transcript = "Back squats five sets of five at one hundred kilos, then ten minutes of rowing. Forty five minutes, felt like an eight.";
const parsedDraft = {
  transcript,
  parsed: true,
  draft: {
    title: "Squat day",
    days_ago: 0,
    duration_minutes: 45,
    perceived_effort: 8,
    notes: "Ten minutes of rowing to finish.",
    exercises: [{ name: "Back squat", sets: 5, reps: 5, load: 100, load_unit: "kg" }],
  },
};

type Handler = (route: Route, path: string, method: string) => Promise<void> | null;

async function stubMember(page: Page, extra: Handler) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const handled = extra(route, path, method);
    if (handled) return handled;
    if (path === "/api/auth/refresh") return json(route, { access_token: memberToken(), refresh_token: "refresh" });
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
    if (path === "/api/me/training-log/sources") return json(route, { classes: [], assignments: [], library_workouts: [] });
    if (path === "/api/me/journal") return json(route, { items: [], next_cursor: null });
    return json(route, {});
  });
}

async function openVoice(page: Page) {
  await page.goto("/journal");
  const menu = page.getByRole("dialog", { name: "New entry" });
  // A tap before the page hydrates is lost, so tap again until the menu opens.
  await expect(async () => {
    await page.getByRole("button", { name: "New entry" }).click();
    await expect(menu).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 20_000 });
  await menu.getByRole("button", { name: /By voice/ }).click();
  const sheet = page.getByRole("dialog", { name: "Log by voice" });
  await expect(sheet).toBeVisible();
  await expect(sheet).toContainText("The recording is not kept.");
  return sheet;
}

/** Sample rate, channels and bits per sample from a base64 WAV header. */
function wavHeader(base64: string) {
  const bytes = Buffer.from(base64, "base64");
  return {
    riff: bytes.toString("ascii", 0, 4),
    wave: bytes.toString("ascii", 8, 12),
    channels: bytes.readUInt16LE(22),
    sampleRate: bytes.readUInt32LE(24),
    bitsPerSample: bytes.readUInt16LE(34),
    dataBytes: bytes.readUInt32LE(40),
  };
}

test.describe("Νέα καταχώρηση › Με φωνή", () => {
  test("records, sends a 16 kHz mono WAV and saves only the reviewed form", async ({ page }) => {
    const drafts: Array<Record<string, unknown>> = [];
    const entries: Array<Record<string, unknown>> = [];
    await stubMember(page, (route, path, method) => {
      if (path === "/api/me/training-log/voice") return json(route, availability());
      if (path === "/api/me/training-log/voice/drafts" && method === "POST") {
        drafts.push(route.request().postDataJSON() as Record<string, unknown>);
        return json(route, parsedDraft);
      }
      if (path === "/api/me/training-log/entries" && method === "POST") {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        entries.push(body);
        return json(route, { entry: { id: "entry-1", source_type: "freeform", title: body.title, performed_at_utc: body.performed_at } }, 201);
      }
      return null;
    });

    const sheet = await openVoice(page);
    await expect(sheet.getByText("Tap to start")).toBeVisible();
    await sheet.getByRole("button", { name: "Start recording" }).click();
    const stop = sheet.getByRole("button", { name: "Stop recording" });
    await expect(stop).toHaveAttribute("aria-pressed", "true");
    await expect(sheet.getByText(/Recording 0:01 \/ 1:00/)).toBeVisible();
    await stop.click();

    // The draft opens in the log form; nothing has been saved yet.
    const notice = page.getByTestId("voice-draft-notice");
    await expect(notice).toContainText("Draft from your voice. Check and correct it before saving.");
    expect(entries).toHaveLength(0);

    expect(drafts).toHaveLength(1);
    const sent = drafts[0];
    expect(sent).toMatchObject({ mime_type: "audio/wav", locale: "en" });
    expect(sent.duration_ms).toBeGreaterThanOrEqual(1_000);
    const header = wavHeader(String(sent.audio_base64));
    expect(header).toMatchObject({ riff: "RIFF", wave: "WAVE", channels: 1, sampleRate: 16_000, bitsPerSample: 16 });
    // About a second or more of 16-bit samples at 16 kHz.
    expect(header.dataBytes).toBeGreaterThan(16_000);

    await notice.getByText("What was heard").click();
    await expect(notice).toContainText(transcript);

    await expect(page.getByLabel("Workout name")).toHaveValue("Squat day");
    await expect(page.getByLabel("Duration (minutes)")).toHaveValue("45");
    await expect(page.getByLabel("Perceived effort (1–10)")).toHaveAttribute("data-value", "8");
    await expect(page.getByRole("textbox", { name: "Exercise", exact: true })).toHaveValue("Back squat");
    await expect(page.getByRole("textbox", { name: "Sets" })).toHaveValue("5");
    await expect(page.getByRole("textbox", { name: "Reps" })).toHaveValue("5");
    await expect(page.getByRole("textbox", { name: "Load" })).toHaveValue("100");
    await expect(page.getByRole("textbox", { name: "Comment", exact: true })).toHaveValue("Ten minutes of rowing to finish.");

    // The member corrects the draft, then confirms.
    await page.getByLabel("Workout name").fill("Squat day, heavy");
    await page.getByRole("button", { name: "Save log" }).click();

    await expect.poll(() => entries.length).toBe(1);
    expect(entries[0]).toMatchObject({
      source_type: "freeform",
      source_reference_id: null,
      title: "Squat day, heavy",
      duration_seconds: 45 * 60,
      perceived_effort: 8,
      comments: [{ body: "Ten minutes of rowing to finish." }],
    });
    expect(JSON.stringify(entries[0].performed_exercises)).toContain("Back squat");
    // The audio and the transcript never reach the saved entry.
    expect(JSON.stringify(entries[0])).not.toContain("audio");
    expect(JSON.stringify(entries[0])).not.toContain(transcript);
    await expect(notice).toBeHidden();
  });

  test("a failed parse still opens the form, with the transcript as the note", async ({ page }) => {
    await stubMember(page, (route, path, method) => {
      if (path === "/api/me/training-log/voice") return json(route, availability());
      if (path === "/api/me/training-log/voice/drafts" && method === "POST") {
        return json(route, {
          transcript,
          parsed: false,
          draft: { title: null, days_ago: 0, duration_minutes: null, perceived_effort: null, notes: transcript, exercises: [] },
        });
      }
      return null;
    });

    const sheet = await openVoice(page);
    await sheet.getByRole("button", { name: "Start recording" }).click();
    await expect(sheet.getByText(/Recording 0:01/)).toBeVisible();
    await sheet.getByRole("button", { name: "Stop recording" }).click();

    await expect(page.getByTestId("voice-draft-notice")).toBeVisible();
    await expect(page.getByLabel("Workout name")).toHaveValue("Workout");
    await expect(page.getByRole("textbox", { name: "Comment", exact: true })).toHaveValue(transcript);
  });

  test("the daily limit answer explains itself and the button stays off", async ({ page }) => {
    await stubMember(page, (route, path, method) => {
      if (path === "/api/me/training-log/voice") return json(route, availability({ remaining_today: 1 }));
      if (path === "/api/me/training-log/voice/drafts" && method === "POST") {
        return json(route, { code: "voice_log_daily_limit", message: "daily limit" }, 429);
      }
      return null;
    });

    const sheet = await openVoice(page);
    await sheet.getByRole("button", { name: "Start recording" }).click();
    await expect(sheet.getByText(/Recording 0:01/)).toBeVisible();
    await sheet.getByRole("button", { name: "Stop recording" }).click();

    await expect(sheet.getByRole("alert")).toHaveText("You've reached today's recording limit.");
    await expect(sheet.getByRole("button", { name: "Start recording" })).toBeDisabled();
    await expect(page.getByTestId("voice-draft-notice")).toHaveCount(0);
    await sheet.getByRole("button", { name: "Cancel" }).click();
    await expect(sheet).toBeHidden();
  });

  test("a refused microphone says how to allow it, and nothing is sent", async ({ page }) => {
    const sent: Request[] = [];
    page.on("request", (request) => {
      if (request.url().includes("/voice/drafts")) sent.push(request);
    });
    await page.addInitScript(() => {
      navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException("denied", "NotAllowedError"));
    });
    await stubMember(page, (route, path) => (path === "/api/me/training-log/voice" ? json(route, availability()) : null));

    const sheet = await openVoice(page);
    await sheet.getByRole("button", { name: "Start recording" }).click();
    await expect(sheet.getByRole("alert")).toHaveText("No access to the microphone. Allow it in your device settings.");
    // Allowing it in the settings and trying again is possible.
    await expect(sheet.getByRole("button", { name: "Start recording" })).toBeEnabled();
    expect(sent).toHaveLength(0);
  });

  test("«By voice» is not offered when the gym has it off or today's drafts are used up", async ({ page }) => {
    let voice = availability({ available: false, enabled: false, remaining_today: 0 });
    await stubMember(page, (route, path) => (path === "/api/me/training-log/voice" ? json(route, voice) : null));

    // Asserts only after the availability answer arrived, so «not shown» is not just «not loaded yet».
    const openMenu = async () => {
      const answered = page.waitForResponse((response) => response.url().endsWith("/me/training-log/voice"));
      const menu = page.getByRole("dialog", { name: "New entry" });
      await expect(async () => {
        await page.getByRole("button", { name: "New entry" }).click();
        await expect(menu).toBeVisible({ timeout: 2_000 });
      }).toPass({ timeout: 20_000 });
      await answered;
      await expect(menu.getByRole("button", { name: /Workout/ })).toBeVisible();
      return menu;
    };

    await page.goto("/journal");
    let menu = await openMenu();
    await expect(menu.getByRole("button", { name: /By voice/ })).toHaveCount(0);
    await menu.getByRole("button", { name: "Cancel" }).click();

    voice = availability({ available: false, enabled: true, remaining_today: 0 });
    await page.reload();
    menu = await openMenu();
    await expect(menu.getByRole("button", { name: /By voice/ })).toHaveCount(0);
  });
});
