import { expect, test, type Page } from "./support/test";

import { chromeArgs } from "../playwright.config";
import { requireWebgl, waitForFigure } from "./support/webgl";

// ADR-164 smoke test: the 3D anatomy figure renders (WebGL headless through
// SwiftShader), loads three and the atlas lazily, answers taps (group, then
// head) and focus, and a page with many thumbnails creates ONE WebGL context
// for all of them. Uses the dev-only preview route /dev/anatomy
// (src/app/dev/anatomy/page.dev.tsx, absent from production builds).

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
test.use({
  launchOptions: {
    ...(executablePath ? { executablePath } : {}),
    args: [...chromeArgs, "--use-gl=angle"],
  },
  // SwiftShader renders on the CPU: at the phone's 2.6x density the figure and
  // its 24 thumbnails took more than three minutes on the CI runner. The
  // checks below are about loading, picking and context sharing, not pixel
  // density, so every project renders at 1x.
  deviceScaleFactor: 1,
});
test.describe.configure({ timeout: 300_000 });

async function countWebglContexts(page: Page) {
  await page.addInitScript(() => {
    // Live contexts only: a figure disposed on unmount (React strict mode mounts twice in dev) loses its context.
    const created = new Set<WebGLRenderingContext | WebGL2RenderingContext>();
    const original = HTMLCanvasElement.prototype.getContext;
    (window as unknown as { __webglContexts: () => number }).__webglContexts = () =>
      [...created].filter((context) => !context.isContextLost()).length;
    HTMLCanvasElement.prototype.getContext = function (this: HTMLCanvasElement, type: string, ...rest: unknown[]) {
      const context = (original as (...args: unknown[]) => RenderingContext | null).call(this, type, ...rest);
      if (context && /webgl/.test(type)) created.add(context as WebGLRenderingContext);
      return context;
    } as typeof HTMLCanvasElement.prototype.getContext;
  });
}

test("renders the figure, picks, focuses and shares one context across thumbnails", async ({ page }) => {
  await requireWebgl(page);
  await countWebglContexts(page);
  const glb: string[] = [];
  page.on("request", (request) => {
    if (request.url().includes("/anatomy/v1/")) glb.push(new URL(request.url()).pathname);
  });

  await page.goto("/dev/anatomy");
  const figure = page.locator("[data-anatomy-status]");
  await waitForFigure(page, figure);
  await expect(figure).toHaveAttribute("data-anatomy-status", "ready");
  await expect(figure).toHaveAttribute("aria-label", /Primary: .*Quadriceps/);
  expect(glb).toEqual(expect.arrayContaining(["/anatomy/v1/muscles.glb", "/anatomy/v1/bones.glb"]));

  // The canvas has drawn something other than transparent pixels.
  const canvas = figure.locator("canvas");
  await expect
    .poll(async () => {
      const shot = await canvas.screenshot({ omitBackground: true });
      return shot.length;
    })
    .toBeGreaterThan(8_000);

  // Every thumbnail becomes an image; the figure plus all thumbnails use two contexts in total.
  const thumbs = page.locator("[data-anatomy-thumb]");
  await expect(thumbs).toHaveCount(24);
  await expect(page.locator('[data-anatomy-thumb="ready"]')).toHaveCount(24, { timeout: 120_000 });
  expect(await page.evaluate(() => (window as unknown as { __webglContexts: () => number }).__webglContexts())).toBe(2);
  await expect(page.locator("canvas")).toHaveCount(1);

  // Tap the right thigh on the front figure: the group first, then the head under the pointer.
  await page.getByTestId("view-front").click();
  await expect(figure).toHaveAttribute("data-anatomy-framed", "body");
  const box = (await canvas.boundingBox())!;
  const thigh = { x: box.x + box.width * 0.43, y: box.y + box.height * 0.6 };
  await page.mouse.click(thigh.x, thigh.y);
  await expect(page.getByTestId("pick")).toHaveAttribute("data-node", "quadriceps");
  await expect(page.getByTestId("pick")).toHaveAttribute("data-level", "group");
  await page.mouse.click(thigh.x, thigh.y);
  await expect(page.getByTestId("pick")).toHaveAttribute("data-level", "head");
  expect(["rectus-femoris", "vastus-lateralis", "vastus-medialis", "vastus-intermedius"]).toContain(
    await page.getByTestId("pick").getAttribute("data-node"),
  );

  // Focus turns to the back for the glutes and frames them.
  await page.getByTestId("focus-glutes").click();
  await expect(figure).toHaveAttribute("data-anatomy-framed", "glutes");
  await page.mouse.click(box.x + box.width * 0.42, box.y + box.height * 0.5);
  await expect(page.getByTestId("pick")).toHaveAttribute("data-node", "glutes");
});
