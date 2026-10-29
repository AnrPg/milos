import { expect, test, type Locator, type Page } from "./support/test";

import {
  cell,
  cellInput,
  type Col,
  clickOutside,
  columns,
  expectStep,
  isRed,
  nameInput,
  openPopups,
  openStructuredEditor,
  pickFlow,
  rowIds,
  rows,
  stubCoach,
  typeName,
  typeParam,
} from "./support/structured-wod";

// ADR-270 structured WOD editor, the exercise grid: values per set and per
// round, progressions shown inside the field, the load unit once per row,
// measures (Alt+P), different rounds (Alt+S), supersets (Alt+G), the row
// menu (Alt+M) and pop-ups that close on a click outside them.

test.beforeEach(() => test.skip(test.info().project.name !== "chromium", "desktop keyboard flow"));

/** A new section with this flow (and params), on step Ασκήσεις with the first name typed. */
async function section(page: Page, flow: string, params: Record<string, string>, firstName: string) {
  await stubCoach(page);
  await openStructuredEditor(page);
  await pickFlow(page, flow);
  for (const [key, value] of Object.entries(params)) await typeParam(page, key, value);
  await page.keyboard.press("Alt+ArrowRight");
  await expectStep(page, "exercises");
  await typeName(page, firstName);
  const [rowId] = await rowIds(page);
  return rowId;
}

/** What a field shows: what was typed, else the computed value drawn inside it, else its placeholder. */
async function shown(page: Page, rowId: string, col: Col, key: string) {
  const input = cellInput(page, rowId, col, key);
  const box = cell(page, rowId, col, key);
  const value = await input.inputValue();
  const drawn = (await box.innerText().catch(() => "")).trim();
  return [value, drawn, (await input.getAttribute("placeholder")) ?? ""].join(" ");
}

/** `inner` is drawn inside `outer` (never as an extra line under it). */
async function expectInside(inner: Locator, outer: Locator) {
  const a = await inner.boundingBox();
  const b = await outer.boundingBox();
  expect(a && b).toBeTruthy();
  expect(a!.y).toBeGreaterThanOrEqual(b!.y - 1);
  expect(a!.y + a!.height).toBeLessThanOrEqual(b!.y + b!.height + 1);
  expect(a!.x).toBeGreaterThanOrEqual(b!.x - 1);
  expect(a!.x + a!.width).toBeLessThanOrEqual(b!.x + b!.width + 1);
}

test("Σετ: reps 12-10-8-8 per set, load 60% then +5 shows 65 inside the field", async ({ page }) => {
  const id = await section(page, "σετ", { sets: "4" }, "Back Squat");
  await expect(columns(page, id, "d")).toHaveCount(4);

  for (const [col, reps] of ["12", "10", "8", "8"].entries()) await cellInput(page, id, col, "d").fill(reps);
  await cellInput(page, id, 0, "l").fill("60%");
  const plus = cellInput(page, id, 1, "l");
  await plus.fill("+5");

  // The coach's own text stays; once the field is left, the computed 65 sits
  // inside the same field (with a small +5 badge), never on a line under it.
  await cellInput(page, id, 2, "d").focus();
  await expect(plus).toHaveValue("+5");
  const computed = page.getByTestId(`plan-cell-${id}-1-l-display`);
  await expect(computed).toBeVisible();
  await expect(computed).toContainText("65");
  await expectInside(computed, cell(page, id, 1, "l"));
  // The quiet hint line explains the focused value.
  await plus.focus();
  await expect(page.getByTestId("plan-hint").filter({ hasText: "65" })).toBeVisible();

  // +5 keeps going in the empty sets after it; no row is red (the unit is on set 1).
  await expect.poll(() => shown(page, id, 2, "l")).toContain("70");
  await expect.poll(() => shown(page, id, 3, "l")).toContain("75");
  for (let col = 0; col < 4; col += 1) await expect(cellInput(page, id, col, "l")).not.toHaveAttribute("aria-invalid", "true");
});

test("bare load numbers with no unit anywhere in the row are red until kg or % is written once", async ({ page }) => {
  const id = await section(page, "σετ", { sets: "3" }, "Deadlift");
  await cellInput(page, id, 0, "d").fill("5");
  await cellInput(page, id, 0, "l").fill("100");
  await cellInput(page, id, 1, "l").fill("110");
  await cellInput(page, id, 0, "d").focus();

  for (const col of [0, 1]) {
    const load = cellInput(page, id, col, "l");
    await expect(load).toHaveAttribute("aria-invalid", "true");
    expect(await isRed(load)).toBe(true);
  }
  await cellInput(page, id, 0, "l").focus();
  await expect(page.getByTestId("plan-editor")).toContainText(/Γράψε kg ή %/);

  // The unit once, in one set: the whole row reads.
  await cellInput(page, id, 0, "l").fill("100kg");
  for (const col of [0, 1]) await expect(cellInput(page, id, col, "l")).not.toHaveAttribute("aria-invalid", "true");
  expect(await isRed(cellInput(page, id, 1, "l"))).toBe(false);

  // A kg / % mix in one row is red too.
  await cellInput(page, id, 1, "l").fill("80%");
  await expect
    .poll(async () => [await cellInput(page, id, 0, "l").getAttribute("aria-invalid"), await cellInput(page, id, 1, "l").getAttribute("aria-invalid")])
    .toContain("true");
});

test("Alt+P adds a measure through fuzzy search", async ({ page }) => {
  const id = await section(page, "σετ", { sets: "3" }, "Back Squat");
  await cellInput(page, id, 0, "d").focus();
  await page.keyboard.press("Alt+P");
  const picker = page.getByTestId("plan-row-menu");
  await expect(picker).toBeVisible();
  await expect(picker).toContainText("RPE");

  // Keyboard only: what the coach types next filters the list (never lands
  // in the field), and a typo still finds Tempo. Enter adds its column.
  await page.keyboard.type("tmpo");
  await expect(cellInput(page, id, 0, "d")).toHaveValue("");
  await expect(picker).toContainText("Tempo");
  await expect(picker).not.toContainText("RPE");
  await page.keyboard.press("Enter");
  await expect(openPopups(page)).toHaveCount(0);
  await expect(columns(page, id, "tempo")).toHaveCount(3);
  await expect(cellInput(page, id, 0, "tempo")).toBeFocused();
});

test("AMRAP: Alt+V gives values per round and the round columns grow as the coach types", async ({ page }) => {
  const id = await section(page, "amrap", { dur: "12" }, "Wall Ball");
  // One value for every round until Alt+V.
  await expect(columns(page, id, "d")).toHaveCount(1);
  await cellInput(page, id, "same", "d").fill("15");
  await cellInput(page, id, "same", "d").focus();

  await page.keyboard.press("Alt+V");
  // AMRAP has no last round: the written round plus one empty column.
  await expect(columns(page, id, "d")).toHaveCount(2);
  await expect(cellInput(page, id, 0, "d")).toHaveValue("15");
  await expect(cellInput(page, id, 1, "d")).toHaveValue("");

  await cellInput(page, id, 1, "d").pressSequentially("20");
  await expect(columns(page, id, "d")).toHaveCount(3);
  await cellInput(page, id, 2, "d").pressSequentially("25");
  await expect(columns(page, id, "d")).toHaveCount(4);
  // After the last written round the coach's own value applies (no invented default).
  await expect.poll(() => shown(page, id, 3, "d")).toContain("25");
});

test("Alt+S adds a different round: rounds 1, 3… and 2, 4… alternate", async ({ page }) => {
  const id = await section(page, "for time", { rounds: "4" }, "Row");
  await nameInput(page, id).focus();
  const before = await rows(page).count();

  await page.keyboard.press("Alt+S");
  await expect(rows(page)).toHaveCount(before + 1);
  // The new kind of round starts with its own empty exercise, focused.
  await expect(rows(page).last().locator('[data-testid^="plan-name-"]')).toBeFocused();
  const editor = page.getByTestId("plan-editor");
  await expect(editor).toContainText(/1, 3/);
  await expect(editor).toContainText(/2, 4/);
  await expect(page.getByTestId("plan-add-round")).toBeVisible();
});

test("Alt+G makes a superset with the row above", async ({ page }) => {
  await section(page, "σετ", { sets: "3" }, "Bench Press");
  await page.keyboard.press("Enter");
  if ((await rows(page).count()) === 1) await page.keyboard.press("Enter");
  await expect(rows(page)).toHaveCount(2);
  await typeName(page, "Pull-up");

  await page.keyboard.press("Alt+G");
  await expect(page.getByTestId("plan-editor")).toContainText("Superset");
  // Both rows stay, now one unit.
  await expect(rows(page)).toHaveCount(2);
});

test("the row menu opens with Alt+M and every pop-up closes on a click outside and on Esc", async ({ page }) => {
  const id = await section(page, "σετ", { sets: "3" }, "Back Squat");
  await nameInput(page, id).focus();

  // Row menu (⋯): Alt+M, then a click outside.
  await page.keyboard.press("Alt+M");
  const menu = page.getByTestId("plan-row-menu");
  await expect(menu).toBeVisible();
  await clickOutside(page);
  await expect(menu).toBeHidden();
  // … and Esc.
  await nameInput(page, id).focus();
  await page.keyboard.press("Alt+M");
  await expect(menu).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(menu).toBeHidden();

  // Measure picker (Alt+P).
  await cellInput(page, id, 0, "d").focus();
  await page.keyboard.press("Alt+P");
  await expect(openPopups(page).first()).toBeVisible();
  await clickOutside(page);
  await expect(openPopups(page)).toHaveCount(0);

  // Exercise name suggestions.
  await nameInput(page, id).focus();
  await page.keyboard.press("Enter");
  const fresh = rows(page).last().locator('[data-testid^="plan-name-"]');
  await fresh.focus();
  await fresh.pressSequentially("squ");
  await expect(openPopups(page).first()).toBeVisible();
  await clickOutside(page);
  await expect(openPopups(page)).toHaveCount(0);
});
