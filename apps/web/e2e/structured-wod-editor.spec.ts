import { expect, test } from "./support/test";

import {
  draftId,
  expectStep,
  nameAndEnter,
  openStructuredEditor,
  paramInput,
  pickFlow,
  planWorkout,
  rows,
  stubCoach,
  switchAuthoring,
  typeParam,
} from "./support/structured-wod";

// ADR-270 structured WOD editor: free text stays the default, the toggle
// switches a workout to Structured and back, and the per-section wizard
// (Ροή → Χρόνος → Ασκήσεις → Σκορ) runs on the keyboard alone, as in the
// approved mockup `docs/product/mockups/structured-wod-editor-mockup.html`.

test.describe("structured WOD editor", () => {
  // Keyboard flows are a desktop affair; the phone layout has its own spec.
  test.beforeEach(() => test.skip(test.info().project.name !== "chromium", "desktop keyboard flow"));

  test("a new workout opens in free text and the toggle switches to Structured and back", async ({ page }) => {
    await stubCoach(page);
    await page.goto("/admin/workouts/new");

    const toggle = page.getByTestId("authoring-toggle");
    await expect(toggle).toBeVisible({ timeout: 15_000 });
    // Free text is the default way to write a WOD.
    await expect(page.locator('[contenteditable="true"]').first()).toBeVisible();
    await expect(page.getByTestId("plan-editor")).toHaveCount(0);

    await switchAuthoring(page, "structured");
    await expect(page.getByTestId("plan-editor")).toBeVisible();
    await expect(page.locator('[contenteditable="true"]')).toHaveCount(0);

    await switchAuthoring(page, "free");
    await expect(page.getByTestId("plan-editor")).toHaveCount(0);
    await expect(page.locator('[contenteditable="true"]').first()).toBeVisible();
  });

  test("a workout written in Structured opens in Structured", async ({ page }) => {
    await stubCoach(page, planWorkout());
    await page.goto(`/admin/workouts/new?draft=${draftId}`);

    const editor = page.getByTestId("plan-editor");
    await expect(editor).toBeVisible({ timeout: 15_000 });
    const card = page.getByTestId("plan-section-card").first();
    await expect(card).toContainText("Σετ");
    await expect(card).toContainText("Bench Press");
  });

  test("the wizard runs on the keyboard alone: emom → params → exercises → score", async ({ page }) => {
    await stubCoach(page);
    await openStructuredEditor(page);

    // Step Ροή: typing filters, Enter takes the best match.
    await pickFlow(page, "emom");
    await expectStep(page, "time");
    await expect(paramInput(page, "every")).toBeFocused();

    await typeParam(page, "every", "1:00");
    await typeParam(page, "times", "10");

    // Alt+→ to Ασκήσεις: the first exercise name has the focus.
    await page.keyboard.press("Alt+ArrowRight");
    await expectStep(page, "exercises");
    await expect(rows(page)).toHaveCount(1);
    await expect(rows(page).first().locator("input").first()).toBeFocused();

    // Enter adds the next exercise and moves there.
    await nameAndEnter(page, "Burpee");
    await expect(rows(page).nth(1).locator("input").first()).toBeFocused();
    await nameAndEnter(page, "Wall Ball");
    await expect(rows(page)).toHaveCount(3);
    await expect(rows(page).first().locator("input").first()).not.toHaveValue("");

    // Alt+→ to Σκορ.
    await page.keyboard.press("Alt+ArrowRight");
    await expectStep(page, "score");

    // Alt+← goes back a step, Alt+1 jumps to Ροή.
    await page.keyboard.press("Alt+ArrowLeft");
    await expectStep(page, "exercises");
    await page.keyboard.press("Alt+1");
    await expectStep(page, "flow");
  });

  test("a preset pre-fills its flow: Tabata = Intervals 20″ / 10″ × 8", async ({ page }) => {
    await stubCoach(page);
    await openStructuredEditor(page);

    // Fuzzy: a typo still finds the preset.
    await pickFlow(page, "tabta");
    await expectStep(page, "time");

    const value = (key: string) => paramInput(page, key);
    await expect(value("work")).toHaveValue("20″");
    await expect(value("off")).toHaveValue("10″");
    await expect(value("rounds")).toHaveValue("8");
    // A preset is a shortcut into a flow, never a format of its own.
    await expect(page.getByTestId("plan-editor")).toContainText("Intervals");
  });
});
