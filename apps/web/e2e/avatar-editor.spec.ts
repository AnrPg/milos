import { crc32, deflateSync } from "node:zlib";

import { expect, test, type Page } from "./support/test";

// The avatar editor (settings → Avatar): it fits small phones in both
// orientations, locks the position sliders when the photo cannot move,
// rotates freely, and re-edits the current avatar without a new file.
// The API and the media host are stubbed.

const AVATAR_URL = "http://media.localhost:18080/palee-avatars/users/member-1/avatar.png";

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  avatar_url: AVATAR_URL,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

/** A PNG whose left half is red and right half blue, so rotation shows. */
function png(width: number, height: number) {
  const chunk = (type: string, data: Buffer) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body) >>> 0);
    return Buffer.concat([length, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // bit depth
  header[9] = 2; // RGB
  const rows = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const row = y * (width * 3 + 1);
    for (let x = 0; x < width; x += 1) {
      const left = x < width / 2;
      rows.set(left ? [220, 30, 30] : [30, 60, 220], row + 1 + x * 3);
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

async function stub(page: Page) {
  const state = { avatarRequests: 0, uploads: 0, avatarUpdates: [] as unknown[] };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", roles: ["member"], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/avatar/upload-url", (route) =>
    route.fulfill(json({ upload_url: "http://media.localhost:18080/upload/avatar.jpg", key: "users/member-1/new.jpg", required_headers: { "content-type": "image/jpeg" }, expires_in: 600, max_bytes: 5_242_880 })),
  );
  await page.route("**/api/me/avatar", (route) => {
    state.avatarUpdates.push(route.request().postDataJSON());
    return route.fulfill(json({ user: { id: user.id, avatar_url: AVATAR_URL } }));
  });
  // The media host (the CSP default) is another origin with open CORS, like the public bucket.
  await page.route("http://media.localhost:18080/**", (route) => {
    const cors = { "access-control-allow-origin": "*", "access-control-allow-methods": "GET, PUT", "access-control-allow-headers": "content-type" };
    const method = route.request().method();
    if (method === "OPTIONS") return route.fulfill({ status: 204, headers: cors, body: "" });
    if (method === "PUT") {
      state.uploads += 1;
      return route.fulfill({ status: 200, headers: cors, body: "" });
    }
    state.avatarRequests += 1;
    return route.fulfill({ status: 200, headers: { ...cors, "content-type": "image/png" }, body: png(300, 300) });
  });
  return state;
}

async function openSettings(page: Page) {
  await page.goto("/me/settings#avatar");
  await expect(page.getByRole("button", { name: "Change avatar" })).toBeVisible();
}

async function pick(page: Page, width: number, height: number) {
  await page.locator('input[type="file"][accept*="image/png"]').setInputFiles({ name: "photo.png", mimeType: "image/png", buffer: png(width, height) });
  const editor = page.getByTestId("avatar-editor");
  await expect(editor.getByRole("button", { name: "Use this picture" })).toBeEnabled();
  return editor;
}

async function expectInsideViewport(page: Page) {
  const viewport = page.viewportSize()!;
  const editor = page.getByTestId("avatar-editor");
  for (const locator of [
    editor,
    page.getByTestId("avatar-crop-area"),
    editor.getByRole("button", { name: "Use this picture" }),
    editor.getByRole("button", { name: "Cancel" }),
    editor.getByRole("slider", { name: "Zoom" }),
  ]) {
    const box = (await locator.boundingBox())!;
    expect(box.x).toBeGreaterThanOrEqual(0);
    expect(box.y).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width).toBeLessThanOrEqual(viewport.width + 0.5);
    expect(box.y + box.height).toBeLessThanOrEqual(viewport.height + 0.5);
  }
  const crop = (await page.getByTestId("avatar-crop-area").boundingBox())!;
  expect(Math.abs(crop.width - crop.height)).toBeLessThan(1);
  expect(crop.width).toBeGreaterThanOrEqual(100);
}

function preview(page: Page) {
  return page.getByTestId("avatar-editor").locator("canvas").evaluate((canvas: HTMLCanvasElement) => canvas.toDataURL());
}

/** The colour at a point of the preview, in 0–1 coordinates. */
function pixel(page: Page, x: number, y: number) {
  return page
    .getByTestId("avatar-editor")
    .locator("canvas")
    .evaluate(
      (canvas: HTMLCanvasElement, [px, py]) => Array.from(canvas.getContext("2d")!.getImageData(Math.floor(canvas.width * px), Math.floor(canvas.height * py), 1, 1).data.slice(0, 3)),
      [x, y],
    );
}

const isRed = ([r, , b]: number[]) => r > 150 && b < 100;
const isBlue = ([r, , b]: number[]) => b > 150 && r < 100;

for (const size of [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
]) {
  test.describe(`avatar editor at ${size.width}px`, () => {
    test.use({ viewport: size });

    test("fits the screen in portrait and landscape", async ({ page }) => {
      await stub(page);
      await openSettings(page);
      await pick(page, 1200, 800);
      await expectInsideViewport(page);
      await page.setViewportSize({ width: size.height, height: size.width });
      await expectInsideViewport(page);
    });

    test("locks the position sliders until zoom lets the photo move", async ({ page }) => {
      await stub(page);
      await openSettings(page);
      const editor = await pick(page, 600, 600);
      const horizontal = editor.getByRole("slider", { name: "Horizontal position" });
      const vertical = editor.getByRole("slider", { name: "Vertical position" });
      await expect(horizontal).toBeDisabled();
      await expect(horizontal).toHaveAttribute("aria-disabled", "true");
      await expect(vertical).toBeDisabled();

      await editor.getByRole("slider", { name: "Zoom" }).fill("2");
      await expect(horizontal).toBeEnabled();
      await expect(vertical).toBeEnabled();
      const before = await preview(page);
      await horizontal.fill("100");
      await expect.poll(() => preview(page)).not.toBe(before);
      // Pushed fully right: the photo's left (red) edge sits at the window's left edge.
      expect(isRed(await pixel(page, 0.5, 0.5))).toBe(true);

      await editor.getByRole("slider", { name: "Zoom" }).fill("1");
      await expect(horizontal).toBeDisabled();
    });

    test("dragging the photo pans it within the crop", async ({ page }) => {
      await stub(page);
      await openSettings(page);
      const editor = await pick(page, 600, 600);
      await editor.getByRole("slider", { name: "Zoom" }).fill("2");
      const area = (await page.getByTestId("avatar-crop-area").boundingBox())!;
      const y = area.y + area.height / 2;
      await page.mouse.move(area.x + area.width / 2, y);
      await page.mouse.down();
      await page.mouse.move(area.x + area.width, y, { steps: 5 });
      await page.mouse.move(area.x + area.width * 1.4, y, { steps: 5 });
      await page.mouse.up();
      // Dragged past the edge: clamped at the end of the range.
      await expect(editor.getByRole("slider", { name: "Horizontal position" })).toHaveValue("100");
      await expect(editor.getByRole("slider", { name: "Vertical position" })).toHaveValue("0");
    });

    test("rotation changes the preview", async ({ page }) => {
      await stub(page);
      await openSettings(page);
      const editor = await pick(page, 600, 600);
      expect(isRed(await pixel(page, 0.1, 0.5))).toBe(true);
      expect(isBlue(await pixel(page, 0.9, 0.5))).toBe(true);

      await editor.getByRole("slider", { name: "Rotation" }).fill("180");
      await expect.poll(async () => isBlue(await pixel(page, 0.1, 0.5))).toBe(true);
      expect(isRed(await pixel(page, 0.9, 0.5))).toBe(true);

      await editor.getByRole("button", { name: "Rotate right" }).click();
      await expect(editor.getByRole("slider", { name: "Rotation" })).toHaveValue("270");
      // A quarter turn puts the halves on top and bottom.
      expect(isBlue(await pixel(page, 0.5, 0.1))).toBe(true);
      await editor.getByRole("button", { name: "Reset" }).click();
      await expect(editor.getByRole("slider", { name: "Rotation" })).toHaveValue("0");
    });

    test("Edit opens the current avatar and saves it through the upload flow", async ({ page }) => {
      const state = await stub(page);
      await openSettings(page);
      await page.getByRole("button", { name: "Edit", exact: true }).click();
      const editor = page.getByTestId("avatar-editor");
      await expect(editor.getByRole("button", { name: "Use this picture" })).toBeEnabled();
      expect(state.avatarRequests).toBeGreaterThan(0);
      expect(isRed(await pixel(page, 0.1, 0.5))).toBe(true);

      await editor.getByRole("button", { name: "Rotate left" }).click();
      await editor.getByRole("button", { name: "Use this picture" }).click();
      await expect(editor).toBeHidden();
      expect(state.uploads).toBe(1);
      expect(state.avatarUpdates).toEqual([{ avatar_key: "users/member-1/new.jpg" }]);
    });
  });
}
