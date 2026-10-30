import { expect, type Page } from "@playwright/test";

/**
 * Once every overlay is closed the page scrolls again: no overlay left
 * `overflow: hidden` on <body> (the frozen-page bug, lib/scroll-lock.ts).
 */
export async function expectPageScrolls(page: Page) {
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => document.body.style.overflow)).not.toBe("hidden");
}
