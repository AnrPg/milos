import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

const pages = [
  { path: "/about", heading: /milos training/i },
  { path: "/register", heading: /create your account/i },
];

async function analyzeAccessibility(page: Page) {
  try {
    return await new AxeBuilder({ page }).disableRules(["color-contrast"]).analyze();
  } catch (error) {
    if (error instanceof Error && error.message.includes("Execution context was destroyed")) {
      await page.waitForLoadState("networkidle");
      await page.waitForTimeout(500);
      return new AxeBuilder({ page }).disableRules(["color-contrast"]).analyze();
    }

    throw error;
  }
}

for (const pageSpec of pages) {
  test(`${pageSpec.path} renders without detectable accessibility violations`, async ({ page }) => {
    await page.route("**/api/auth/refresh", (route) =>
      route.fulfill({ status: 401, contentType: "application/json", body: "{}" }),
    );
    await page.route("**/api/theme", (route) =>
      route.fulfill({ status: 200, contentType: "application/json", body: "{}" }),
    );

    await page.goto(pageSpec.path);
    await expect(page.getByRole("heading", { name: pageSpec.heading }).first()).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);

    const accessibility = await analyzeAccessibility(page);

    expect(accessibility.violations).toEqual([]);
  });
}
