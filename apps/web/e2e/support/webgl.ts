import { expect, test, type Locator, type Page } from "@playwright/test";

const PROBE_TIMEOUT_MS = 15_000;

/**
 * Whether the page can make a context the way the figure's renderer asks for
 * one. A browser whose GPU process is wedged can block context creation, so a
 * probe that does not answer in time counts as "no WebGL" instead of hanging.
 */
export async function webglAvailable(page: Page) {
  const probe = page.evaluate(() => {
    const canvas = document.createElement("canvas");
    const attributes: WebGLContextAttributes = { alpha: true, antialias: false };
    const context: WebGLRenderingContext | WebGL2RenderingContext | null =
      canvas.getContext("webgl2", attributes) ?? canvas.getContext("webgl", attributes);
    // Hand the context back at once: a page may hold only a few.
    context?.getExtension("WEBGL_lose_context")?.loseContext();
    return Boolean(context);
  });
  const timeout = new Promise<false>((resolve) => setTimeout(() => resolve(false), PROBE_TIMEOUT_MS));
  return Promise.race([probe.catch(() => false), timeout]);
}

/**
 * The 3D figure needs WebGL. A browser that cannot make a WebGL context at
 * all (a GPU-less runner whose Chrome refuses SwiftShader) skips the test with
 * a visible reason instead of failing the build; everywhere else it runs.
 */
export async function requireWebgl(page: Page) {
  test.skip(!(await webglAvailable(page)), "This browser cannot create a WebGL context, so the 3D figure cannot render here.");
}

/**
 * Waits until a figure (`[data-anatomy-status]`) has loaded or failed. The
 * figure says why it failed: when the browser could not make a WebGL context
 * (`data-anatomy-failure="webgl"`, a runner whose software GL gave out mid-run)
 * the test skips like `requireWebgl`; any other failure fails the test.
 */
export async function waitForFigure(figure: Locator, timeout = 120_000) {
  await expect(figure).not.toHaveAttribute("data-anatomy-status", "loading", { timeout });
  if ((await figure.getAttribute("data-anatomy-status")) !== "error") return;
  const failure = await figure.getAttribute("data-anatomy-failure");
  test.skip(failure === "webgl", "The browser could not create a WebGL context during the run, so the 3D figure cannot render here.");
  expect(failure, "the figure failed for a reason other than WebGL").toBeNull();
}
