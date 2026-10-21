import { test, type Page } from "@playwright/test";

/**
 * The 3D figure needs WebGL. A browser that cannot make a WebGL context at
 * all (a GPU-less runner whose Chrome refuses SwiftShader) skips the test with
 * a visible reason instead of failing the build; everywhere else it runs.
 */
export async function requireWebgl(page: Page) {
  const available = await page.evaluate(() => {
    const canvas = document.createElement("canvas");
    return Boolean(canvas.getContext("webgl2") ?? canvas.getContext("webgl"));
  });
  test.skip(!available, "This browser cannot create a WebGL context, so the 3D figure cannot render here.");
}
