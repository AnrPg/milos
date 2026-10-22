import { expect, test, type Locator, type Page } from "@playwright/test";

/** Whether the page can make a context the way the figure's renderer asks for one. */
export function webglAvailable(page: Page) {
  return page.evaluate(() => {
    const canvas = document.createElement("canvas");
    const attributes: WebGLContextAttributes = { alpha: true, antialias: false };
    const context: WebGLRenderingContext | WebGL2RenderingContext | null =
      canvas.getContext("webgl2", attributes) ?? canvas.getContext("webgl", attributes);
    // Hand the context back at once: a page may hold only a few.
    context?.getExtension("WEBGL_lose_context")?.loseContext();
    return Boolean(context);
  });
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
 * Waits until a figure (`[data-anatomy-status]`) has loaded or failed. A
 * failure while the browser can still make contexts is a real bug and fails
 * the test; a browser that lost WebGL mid-run (its GPU process gave up, as a
 * loaded software-GL runner does) skips like `requireWebgl`, quickly, instead
 * of timing out.
 */
export async function waitForFigure(page: Page, figure: Locator, timeout = 120_000) {
  await expect(figure).not.toHaveAttribute("data-anatomy-status", "loading", { timeout });
  if ((await figure.getAttribute("data-anatomy-status")) === "error") {
    test.skip(!(await webglAvailable(page)), "The browser lost WebGL during the run, so the 3D figure cannot render here.");
  }
}
