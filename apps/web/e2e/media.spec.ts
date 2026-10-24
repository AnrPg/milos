import { expect, test, type Page, type Route } from "./support/test";

// P2-M9 (ADR-157, board 12): photos and video in posts. Compose uploads each
// picked file at once (presigned PUT stubbed here too), alt text with a
// suggestion, the author's «processing» post, the carousel and full-screen
// viewer, an inline video with its poster, the subtle report flag, and
// sharing a just-logged PR. The API is stubbed; unlisted routes answer {}.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

// A 4×3 PNG, small enough to inline, decodable by the browser for the resize step.
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

const channel = (id: string, kind: string, extra: Record<string, unknown> = {}) => ({
  id,
  kind,
  name: null,
  write_policy: "members",
  membership: "everyone",
  joined: true,
  can_post: true,
  can_leave: false,
  ...extra,
});

const gymClub = {
  id: "club-1",
  kind: "gym",
  name: "Box Kypseli",
  organization_id: "org-1",
  organization_slug: "kypseli",
  role: "member",
  notify_level: "all",
  logo_url: null,
  primary_color: null,
  channels: [channel("ch-ann", "announcements", { write_policy: "staff", can_post: false }), channel("ch-wod", "wod")],
};

const photo = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  kind: "image",
  status: "ready",
  width: 1600,
  height: 1200,
  thumb_url: `/__media/${id}-thumb.png`,
  feed_url: `/__media/${id}-feed.png`,
  full_url: `/__media/${id}-full.png`,
  placeholder: null,
  alt_text: null,
  duration_ms: null,
  video_url: null,
  ...extra,
});

function post(id: string, extra: Record<string, unknown> = {}) {
  return {
    id,
    origin: "club",
    audience: "club_channel",
    author: { id: "member-2", nickname: "Eleni", avatar_url: null },
    body: "Saturday partner WOD",
    attachment: null,
    attachment_id: null,
    attachment_type: null,
    can_delete: false,
    can_moderate: false,
    can_pin: false,
    can_report: true,
    channel: { id: "ch-wod", kind: "wod", name: null },
    club: { id: "club-1", name: "Box Kypseli", organization_slug: "kypseli", kind: "gym" },
    comment_count: 0,
    hidden: false,
    inserted_at: new Date().toISOString(),
    kudos_by_me: false,
    kudos_count: 0,
    pinned: false,
    media: [],
    media_status: "ready",
    ...extra,
  };
}

type Calls = {
  uploads: unknown[];
  puts: string[];
  patches: Array<{ id: string; body: unknown }>;
  posts: Array<Record<string, unknown>>;
  reports: unknown[];
  feedAfterPublish: number;
};

async function stub(page: Page, feed: () => unknown[]) {
  const { user, token } = persona();
  const calls: Calls = { uploads: [], puts: [], patches: [], posts: [], reports: [], feedAfterPublish: 0 };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" } }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [gymClub] })));
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/api/me/feed**", (route) => {
    if (calls.posts.length) calls.feedAfterPublish += 1;
    return route.fulfill(json({ posts: feed(), pinned: [], next_cursor: null }));
  });
  await page.route("**/api/me/media/capabilities", (route) =>
    route.fulfill(
      json({
        max_photos: 10,
        max_videos: 1,
        video: true,
        max_video_seconds: 120,
        photo_content_types: ["image/heic", "image/heif", "image/jpeg", "image/png", "image/webp"],
        video_content_types: ["video/mp4", "video/quicktime", "video/webm"],
        max_photo_bytes: 26214400,
        max_video_bytes: 524288000,
        max_alt_text: 500,
      }),
    ),
  );
  await page.route("**/__media/**", (route) =>
    route.fulfill({ status: 200, contentType: route.request().url().endsWith(".mp4") ? "video/mp4" : "image/png", body: PNG }),
  );
  await page.route("**/api/me/community/reports", (route) => {
    calls.reports.push(route.request().postDataJSON());
    return route.fulfill(json({ reported: true, target_type: "post", target_id: "post-1" }, 201));
  });
  return calls;
}

/** Upload endpoints for compose; `gate` holds the first PUT until released, to see progress. */
async function uploads(page: Page, calls: Calls, gate: Promise<void>) {
  let next = 0;
  const polls = new Map<string, number>();
  const media = (id: string, status: string, extra: Record<string, unknown> = {}) => ({
    id,
    purpose: "post_photo",
    kind: "image",
    content_type: "image/jpeg",
    status,
    width: 2,
    height: 2,
    url: null,
    alt_text: null,
    ...extra,
  });
  await page.route("**/api/me/media/uploads", (route) => {
    next += 1;
    calls.uploads.push(route.request().postDataJSON());
    const id = `m${next}`;
    return route.fulfill(json({ media_id: id, upload_url: `/__upload/${id}`, required_headers: { "content-type": "image/jpeg" }, max_bytes: 26214400, expires_in: 900 }));
  });
  await page.route("**/__upload/**", async (route: Route) => {
    const id = route.request().url().split("/").pop()!;
    calls.puts.push(id);
    await gate;
    return route.fulfill({ status: 200, body: "" });
  });
  await page.route("**/api/me/media/*/complete", (route) => {
    const id = route.request().url().split("/").at(-2)!;
    return route.fulfill(json({ media: media(id, "processing") }));
  });
  await page.route("**/api/me/media/*/alt-text-suggestion", (route) =>
    route.fulfill(json({ suggestion: "Two athletes high-five after a workout" })),
  );
  await page.route(/\/api\/me\/media\/m\d+$/, (route) => {
    const id = route.request().url().split("/").pop()!;
    if (route.request().method() === "PATCH") {
      const body = route.request().postDataJSON();
      calls.patches.push({ id, body });
      return route.fulfill(json({ media: media(id, "ready", body) }));
    }
    if (route.request().method() === "DELETE") return route.fulfill({ status: 204, body: "" });
    const count = (polls.get(id) ?? 0) + 1;
    polls.set(id, count);
    return route.fulfill(json({ media: media(id, count >= 1 ? "ready" : "processing") }));
  });
}

const pngs = (count: number) =>
  Array.from({ length: count }, (_, index) => ({ name: `photo-${index + 1}.png`, mimeType: "image/png", buffer: PNG }));

test.describe("photos and video in posts", () => {
  test("compose uploads three photos with progress, reorders, describes one, publishes; the author sees processing then ready", async ({ page }) => {
    let published: Record<string, unknown> | null = null;
    const calls = await stub(page, () => {
      if (!published) return [];
      const ids = (calls.posts[0]?.media_ids as string[]) ?? [];
      const ready = calls.feedAfterPublish > 1;
      return [
        post("post-mine", {
          author: { id: "member-1", nickname: "Maria", avatar_url: null },
          body: published.body,
          can_report: false,
          can_delete: true,
          media_status: ready ? "ready" : "processing",
          media: ids.map((id) => (ready ? photo(id) : { id, kind: "image", status: "processing" })),
        }),
      ];
    });
    let release!: () => void;
    await uploads(page, calls, new Promise<void>((resolve) => (release = resolve)));
    await page.route("**/api/me/community/posts", (route) => {
      published = route.request().postDataJSON();
      calls.posts.push(published!);
      return route.fulfill(json({ post: post("post-mine") }, 201));
    });

    await page.goto("/clubs/club-1");
    await page.getByRole("button", { name: "New post" }).click();
    const compose = page.getByRole("dialog", { name: "New post" });
    await expect(compose.getByRole("button", { name: /Add photos or a video/ })).toBeFocused();

    await compose.getByTestId("media-input").setInputFiles(pngs(3));
    const tiles = compose.getByTestId("media-tile");
    await expect(tiles).toHaveCount(3);
    // The PUTs are held: the tiles show progress and publishing waits.
    await expect(tiles.first()).toHaveAttribute("data-phase", "uploading");
    await expect(tiles.first().getByRole("progressbar")).toBeVisible();
    await compose.getByLabel("What's on your mind?").or(compose.locator("#compose-body")).first().fill("Partner WOD with Eleni");
    await expect(compose.getByRole("button", { name: "Publish" })).toBeDisabled();
    await expect(compose.getByText("Wait for the files to upload.")).toBeVisible();
    release();
    for (const index of [0, 1, 2]) await expect(tiles.nth(index)).toHaveAttribute("data-phase", /processing|ready/);
    // The uploads start in parallel, so which tile got which id is up to the
    // browser; read it off the tiles instead of assuming file order.
    const ids = await tiles.evaluateAll((nodes) => nodes.map((node) => node.getAttribute("data-media-id")));
    expect(new Set(ids)).toEqual(new Set(["m1", "m2", "m3"]));
    expect(calls.uploads).toEqual(Array(3).fill(expect.objectContaining({ purpose: "post_photo", content_type: "image/jpeg" })));

    // Move the first photo one place later (keyboard-reachable buttons).
    await compose.getByRole("button", { name: "Photo 1 of 3", exact: true }).click();
    await compose.getByRole("button", { name: "Move later" }).click();
    await expect(compose.getByRole("button", { name: "Photo 2 of 3", exact: true })).toHaveAttribute("aria-pressed", "true");

    // Describe it, with the suggestion used only on tap.
    await compose.getByRole("button", { name: /^Description/ }).click();
    const alt = page.getByRole("dialog", { name: "Photo description" });
    await alt.getByRole("button", { name: "Suggest a description" }).click();
    await expect(alt.getByTestId("alt-suggestion")).toHaveText("Two athletes high-five after a workout");
    await expect(alt.getByRole("textbox")).toHaveValue("");
    await alt.getByRole("button", { name: "Use suggestion" }).click();
    await expect(alt.getByRole("textbox")).toHaveValue("Two athletes high-five after a workout");
    await alt.getByRole("button", { name: "Save" }).click();
    await expect(alt).toBeHidden();
    await expect(compose).toBeVisible();
    expect(calls.patches).toEqual([{ id: ids[0], body: { alt_text: "Two athletes high-five after a workout" } }]);

    await compose.getByRole("button", { name: "Publish" }).click();
    await expect(compose).toBeHidden();
    expect(calls.posts[0]).toMatchObject({ channel_id: "ch-wod", body: "Partner WOD with Eleni", media_ids: [ids[1], ids[0], ids[2]] });

    const card = page.getByRole("article").filter({ hasText: "Partner WOD with Eleni" });
    await expect(card.getByText("Processing…", { exact: true })).toBeVisible();
    await expect(card.getByText("Processing…", { exact: true })).toBeHidden({ timeout: 15_000 });
    await expect(card.getByTestId("media-counter")).toHaveText("1/3");
  });

  test("a carousel swipes, steps with arrows and keys, and the viewer opens and closes with Escape", async ({ page, isMobile }) => {
    await stub(page, () => [post("post-1", { media: [photo("p1", { alt_text: "Rowing" }), photo("p2"), photo("p3")] })]);
    await page.goto("/clubs/club-1");

    const carousel = page.getByTestId("media-carousel");
    const counter = carousel.getByTestId("media-counter");
    await expect(counter).toHaveText("1/3");
    if (!isMobile) {
      await carousel.getByRole("button", { name: "Next" }).click();
      await expect(counter).toHaveText("2/3");
      await carousel.getByRole("button", { name: "Previous" }).click();
      await expect(counter).toHaveText("1/3");
    }
    // A swipe is a horizontal scroll of the snap track.
    await carousel.locator(".snap-x").evaluate((track) => track.scrollTo({ left: track.clientWidth * 2 }));
    await expect(counter).toHaveText("3/3");
    await carousel.getByRole("button", { name: "Go to photo 1" }).click();
    await expect(counter).toHaveText("1/3");

    const first = carousel.getByRole("button", { name: /Rowing · Open full screen/ });
    await first.focus();
    await page.keyboard.press("ArrowRight");
    await expect(counter).toHaveText("2/3");
    await page.keyboard.press("ArrowLeft");
    await expect(counter).toHaveText("1/3");

    await first.click();
    const viewer = page.getByRole("dialog", { name: "Photos and video" });
    await expect(viewer).toBeVisible();
    await expect(viewer.getByText("Saturday partner WOD")).toBeVisible();
    await expect(viewer).toContainText("Description: Rowing");
    await expect(viewer.getByText("1/3")).toBeVisible();
    await page.keyboard.press("ArrowRight");
    await expect(viewer.getByText("2/3")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(viewer).toBeHidden();
    await expect(first).toBeFocused();
  });

  test("a video post shows its poster, plays inline muted, and a tap turns the sound on", async ({ page }) => {
    await stub(page, () => [
      post("post-v", {
        media: [
          {
            id: "v1",
            kind: "video",
            status: "ready",
            width: 1280,
            height: 720,
            thumb_url: "/__media/v1-thumb.png",
            feed_url: "/__media/v1-poster.png",
            full_url: "/__media/v1-full.png",
            video_url: "/__media/v1.mp4",
            duration_ms: 42_000,
            placeholder: null,
            alt_text: null,
          },
        ],
      }),
    ]);
    await page.goto("/clubs/club-1");

    const video = page.getByTestId("post-video");
    await expect(video).toHaveAttribute("poster", "/__media/v1-poster.png");
    await expect(video).toHaveAttribute("playsinline", "");
    expect(await video.evaluate((element: HTMLVideoElement) => element.muted)).toBe(true);
    await expect(page.getByText("0:42")).toBeVisible();
    await page.getByRole("button", { name: "Turn sound on" }).click();
    expect(await video.evaluate((element: HTMLVideoElement) => element.muted || !element.controls)).toBe(false);
  });

  test("the subtle report flag opens the report sheet, from the card and from the viewer", async ({ page }) => {
    const calls = await stub(page, () => (calls.reports.length ? [] : [post("post-1", { media: [photo("p1")] })]));
    await page.goto("/clubs/club-1");

    const card = page.getByRole("article").filter({ hasText: "Saturday partner WOD" });
    const flag = card.getByRole("button", { name: "Report", exact: true });
    await flag.focus();
    await expect(flag).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.getByRole("dialog", { name: "Report this post" })).toBeVisible();
    await page.getByRole("dialog", { name: "Report this post" }).getByRole("button", { name: "Cancel" }).click();

    await card.getByRole("button", { name: /Open full screen/ }).click();
    const viewer = page.getByRole("dialog", { name: "Photos and video" });
    await viewer.getByRole("button", { name: "Report", exact: true }).click();
    await expect(viewer).toBeHidden();
    const sheet = page.getByRole("dialog", { name: "Report this post" });
    await sheet.getByRole("radio", { name: "Spam" }).click();
    await sheet.getByRole("button", { name: "Send report" }).click();
    await expect(page.getByText("Thanks, staff will take a look.")).toBeVisible();
    expect(calls.reports).toEqual([{ target_type: "post", target_id: "post-1", reason: "spam", note: null }]);
  });

  test("after logging a PR, «Share it» opens compose with the PR attached, photos first and the box club as audience", async ({ page }) => {
    const calls = await stub(page, () => []);
    const pr = {
      id: "pr-9",
      user_id: "member-1",
      organization_id: "org-1",
      name: "Clean",
      current_score: 90,
      unit: "kg",
      higher_is_better: true,
      beaten_on: "2026-10-20",
      supporting_metrics: {},
      comments: [],
      inserted_at: "2026-10-20T10:00:00Z",
      updated_at: "2026-10-20T10:00:00Z",
    };
    await page.route("**/api/prs", (route) =>
      route.request().method() === "POST" ? route.fulfill(json({ pr }, 201)) : route.fulfill(json({ prs: [] })),
    );
    await page.route("**/api/pr-sharing/shared-with-me", (route) => route.fulfill(json({ shared: [] })));
    await page.route("**/api/me/post-attachments/pr/pr-9", (route) =>
      route.fulfill(json({ attachment_type: "pr", attachment_id: "pr-9", attachment: { title: "Clean", score: 90, unit: "kg", occurred_on: "2026-10-20" } })),
    );
    await page.route("**/api/me/community/posts", (route) => {
      calls.posts.push(route.request().postDataJSON());
      return route.fulfill(json({ post: post("post-pr") }, 201));
    });

    await page.goto("/journal/progress");
    await page.getByRole("button", { name: "+ Add PR" }).first().click();
    await page.getByPlaceholder("e.g. Back Squat 1RM").fill("Clean");
    await page.getByRole("spinbutton").first().fill("90");
    await page.getByRole("button", { name: "Add PR", exact: true }).click();

    const logged = page.getByRole("dialog", { name: "New PR!" });
    await expect(logged).toBeVisible();
    await logged.getByRole("button", { name: "Share it" }).click();

    const compose = page.getByRole("dialog", { name: "New post" });
    await expect(compose).toBeVisible();
    await expect(compose.getByRole("button", { name: /Add photos or a video/ })).toBeFocused();
    await expect(compose.getByTestId("compose-attachment-preview")).toContainText("Clean");
    await expect(compose.getByText("Box Kypseli › #wod-today")).toBeVisible();
    await expect(compose.getByRole("button", { name: "Publish" })).toBeEnabled();
    expect(calls.posts).toEqual([]);
  });
});
