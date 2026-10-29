import { expect, test, type Page } from "./support/test";

import {
  cellInput,
  draftId,
  expectStep,
  openStructuredEditor,
  pickFlow,
  rowIds,
  stubCoach,
  stubMember,
  typeName,
  typeParam,
  type EditorServer,
} from "./support/structured-wod";

// ADR-270 end to end: the editor saves `authoring_mode: "structured_plan"`
// with one `sections[].plan` per section, the WOD view renders the plan
// (tempo ↓3 ·1 ↑X ·1, «ανά πλευρά»), and execution runs a superset set-wise
// (set 1 of every exercise of the group, then set 2) and stops for the
// interruption every 2:00.

type PlanRowBody = { name: string; group?: string | null; cells: Array<Record<string, string>> };
type SaveBody = {
  authoring_mode?: string;
  sections?: Array<{ plan?: { v: number; flow: string; params: Record<string, string>; blocks: PlanRowBody[][]; structs?: Record<string, { kind: string }> } }>;
};

const lastStructured = (server: EditorServer) =>
  (server.saves as SaveBody[]).filter((save) => save.authoring_mode === "structured_plan").at(-1);

/** Drafts save on their own; if no autosave came, publishing saves too. */
async function ensureSaved(page: Page, server: EditorServer) {
  const saved = await expect
    .poll(() => Boolean(lastStructured(server)), { timeout: 8_000 })
    .toBe(true)
    .then(() => true, () => false);
  if (!saved) await page.getByRole("button", { name: /Δημοσίευση|Αποθήκευση|Publish|Save/ }).first().click();
  await expect.poll(() => Boolean(lastStructured(server))).toBe(true);
}

test("saving sends authoring_mode structured_plan with sections[].plan", async ({ page }) => {
  test.skip(test.info().project.name !== "chromium", "desktop keyboard flow");
  const server = await stubCoach(page);
  await openStructuredEditor(page);

  await pickFlow(page, "σετ");
  await typeParam(page, "sets", "3");
  await page.keyboard.press("Alt+ArrowRight");
  await expectStep(page, "exercises");
  await typeName(page, "Bench Press");
  await page.keyboard.press("Enter");
  await typeName(page, "Pull-up");
  await page.keyboard.press("Alt+G");

  const [bench, pull] = await rowIds(page);
  await cellInput(page, bench, 0, "d").fill("12");
  await cellInput(page, bench, 0, "l").fill("60%");
  await cellInput(page, bench, 1, "l").fill("+5");
  await cellInput(page, pull, 0, "d").fill("8");
  await cellInput(page, pull, 0, "d").press("Tab");

  await ensureSaved(page, server);
  await expect
    .poll(() => lastStructured(server)?.sections?.[0]?.plan?.blocks?.[0]?.[0]?.cells?.[1]?.l, { timeout: 15_000 })
    .toBe("+5");

  const body = lastStructured(server)!;
  expect(body.authoring_mode).toBe("structured_plan");
  expect(body.sections).toHaveLength(1);
  const plan = body.sections![0].plan!;
  expect(plan).toMatchObject({ v: 1, flow: "sets", params: { sets: "3" } });
  const [first, second] = plan.blocks[0];
  expect([first.name, second.name]).toEqual(["Bench Press", "Pull-up"]);
  // Values are stored as typed: the unit once, the progression as "+5".
  expect(first.cells[0]).toMatchObject({ d: "12", l: "60%" });
  expect(first.cells[1]).toMatchObject({ l: "+5" });
  expect(second.cells[0]).toMatchObject({ d: "8" });
  // Alt+G: one superset group.
  expect(first.group).toBeTruthy();
  expect(second.group).toBe(first.group);
  // A group is a superset unless another structure is set for it.
  expect([undefined, { kind: "superset" }]).toContainEqual(plan.structs?.[first.group!]);
  expect(page.url()).toContain(draftId);
});

test("the WOD view renders the plan: superset, tempo ↓3 ·1 ↑X ·1 and «ανά πλευρά»", async ({ page }) => {
  await stubMember(page);
  await page.goto("/box");
  await expect(page.getByRole("heading", { name: "Upper" })).toBeVisible({ timeout: 15_000 });

  const view = page.getByTestId("plan-view").first();
  if (!(await view.isVisible())) await page.getByRole("button", { expanded: false }).filter({ hasText: /^A\b|Σετ/ }).first().click();
  await expect(view).toBeVisible();
  await expect(view).toContainText("Bench Press");
  await expect(view).toContainText("Pull-up");
  await expect(view).toContainText("Superset");
  await expect(view).toContainText(/↓3\s*·1\s*↑X\s*·1/);
  await expect(view).toContainText("Walking Lunge");
  await expect(view).toContainText("ανά πλευρά");
  // The interruption is part of the plan's text.
  await expect(view).toContainText("Burpee");
  // Tempo never shows raw next to its nice form.
  await expect(view).not.toContainText("31X1");
});

test("execution runs the superset set-wise and stops for the interruption", async ({ page }) => {
  await page.clock.install();
  await stubMember(page);
  await page.goto("/workouts/exec-1/execute");

  const run = page.getByTestId("plan-run");
  await expect(run).toBeVisible({ timeout: 15_000 });
  const current = run.locator('section[aria-live="polite"]');
  const name = current.getByRole("heading", { level: 2 });
  const next = page.getByTestId("plan-run-next");

  // Ready: the first exercise is announced; Next starts.
  await expect(current).toContainText("Bench Press");
  await next.click();

  // Set 1 of every exercise in the group, then set 2.
  await expect(name).toHaveText("Bench Press");
  await expect(current).toContainText("Σετ 1 από 2");
  await next.click();
  await expect(name).toHaveText("Pull-up");
  await expect(current).toContainText("Σετ 1 από 2");
  await next.click();
  // The 90″ rest between sets runs on the clock.
  if (!(await name.isVisible())) await page.clock.fastForward(91_000);
  await expect(name).toHaveText("Bench Press");
  await expect(current).toContainText("Σετ 2 από 2");

  // Every 2:00: stop for the interrupt rows, then resume where you left off.
  await page.clock.fastForward(30_000);
  await expect(current).toContainText("Διακοπή");
  await expect(name).toHaveText("Burpee");
  await next.click();
  await expect(name).toHaveText("Bench Press");
  await expect(current).toContainText("Σετ 2 από 2");
});
