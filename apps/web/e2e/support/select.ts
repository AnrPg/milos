import { expect, type Locator, type Page } from "@playwright/test";

/** Picks a value in a ui/Select (the themed dropdown that replaced <select>). */
export async function chooseOption(page: Page, trigger: Locator, value: string) {
  await trigger.click();
  await page.locator(`[role="option"][data-value="${value}"]`).click();
  await expect(trigger).toHaveAttribute("data-value", value);
}

/** Picks a day ("2026-10-22") in a ui/DateInput, paging months forward or back as needed. */
export async function chooseDate(page: Page, trigger: Locator, isoDay: string) {
  await trigger.click();
  const day = page.locator(`[data-day="${isoDay}"]:not([disabled])`);
  const current = (await trigger.getAttribute("data-value")) || new Date().toISOString().slice(0, 10);
  const direction = isoDay < current ? "previous" : "next";
  for (let step = 0; step < 36 && (await day.count()) === 0; step += 1) {
    await page.locator(`[data-nav="${direction}"]`).click();
  }
  await day.click();
  await expect(trigger).toHaveAttribute("data-value", isoDay);
}
