import { test as base, type Page } from "@playwright/test";

export * from "@playwright/test";

const HYDRATION_TIMEOUT_MS = 15_000;

/** Waits for the root layout's HydrationMarker; pages without the app shell just move on. */
async function waitForHydration(page: Page) {
  await page
    .waitForFunction(() => document.documentElement.dataset.hydrated === "true", undefined, { timeout: HYDRATION_TIMEOUT_MS })
    .catch(() => undefined);
}

/**
 * The shared `test`: `page.goto` and `page.reload` resolve only once React has
 * hydrated the page, so a first tap is never lost on server-rendered HTML
 * (the cause of the intermittent "New entry" / "+ New PR" failures in CI).
 */
export const test = base.extend({
  page: async ({ page }, provide) => {
    const goto = page.goto.bind(page);
    const reload = page.reload.bind(page);
    page.goto = async (...args: Parameters<Page["goto"]>) => {
      const response = await goto(...args);
      await waitForHydration(page);
      return response;
    };
    page.reload = async (...args: Parameters<Page["reload"]>) => {
      const response = await reload(...args);
      await waitForHydration(page);
      return response;
    };
    await provide(page);
  },
});
