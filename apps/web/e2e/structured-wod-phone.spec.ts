import { expect, test } from "./support/test";

import {
  cellInput,
  expectNoCroppedFields,
  expectNoHorizontalScroll,
  expectStep,
  nameInput,
  openStructuredEditor,
  pickFlow,
  rowIds,
  rows,
  stubCoach,
  typeParam,
} from "./support/structured-wod";

// ADR-270 on a phone (ANR: "cluttered / units far / cropped"): every exercise
// is a card and its sets are rows, nothing scrolls sideways and no field cuts
// its text off.

test.use({ viewport: { width: 390, height: 844 } });

test("on a 390px phone every exercise is a card, sets are rows, nothing scrolls sideways or is cropped", async ({ page }) => {
  await stubCoach(page);
  await openStructuredEditor(page);
  await expectNoHorizontalScroll(page);

  await pickFlow(page, "σετ");
  await typeParam(page, "sets", "3");
  await expectNoHorizontalScroll(page);
  await page.getByTestId("plan-step-exercises").click();
  await expectStep(page, "exercises");

  const [first] = await rowIds(page);
  await nameInput(page, first).fill("Romanian Deadlift");
  await cellInput(page, first, 0, "d").fill("8-12");
  await cellInput(page, first, 0, "l").fill("22.5 kg");
  await cellInput(page, first, 1, "l").fill("+2.5");
  await cellInput(page, first, 2, "l").fill("27.5");

  await page.getByTestId("plan-add-exercise").click();
  await expect(rows(page)).toHaveCount(2);
  const [, second] = await rowIds(page);
  await nameInput(page, second).fill("Walking Lunge");
  await cellInput(page, second, 0, "d").fill("10 / πλευρά");
  await cellInput(page, second, 0, "l").fill("βαρύ");

  // Cards: each exercise fits the screen width.
  for (const row of await rows(page).all()) {
    const box = await row.boundingBox();
    expect(box).toBeTruthy();
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(390);
  }
  // Sets are rows inside the card: set 2 sits under set 1, not beside it.
  const set1 = await cellInput(page, first, 0, "d").boundingBox();
  const set2 = await cellInput(page, first, 1, "d").boundingBox();
  expect(set1 && set2).toBeTruthy();
  expect(set2!.y).toBeGreaterThanOrEqual(set1!.y + set1!.height - 1);

  await expectNoHorizontalScroll(page);
  await expectNoCroppedFields(page);
});
