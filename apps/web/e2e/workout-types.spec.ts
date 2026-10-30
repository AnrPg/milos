import { expect, test } from "./support/test";
import { chooseOption } from "./support/select";
import { draftId, json, stubCoach } from "./support/structured-wod";

// ADR-275: a WOD's «Τύπος προπόνησης» comes from one fixed list grouped in
// families (martial arts and dance included), translated, limited to the kinds
// the box offers in its settings.

const sectionedDraft = {
  id: draftId,
  status: "draft",
  title: "",
  type: null,
  authoring_mode: "sectioned_text",
  free_text_body: null,
  dsl_source_revision: 1,
  available_scale_levels: [],
  sections: [{ name: "Ενότητα 1", free_text_body: "", timer_preset: null, exercises: [] }],
  draft_data: { authoring_mode: "sectioned_text" },
};

test("the editor offers the box's workout types in Greek, by family", async ({ page }) => {
  const server = await stubCoach(page, sectionedDraft);
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) =>
    json(route, { wod_assistant_enabled: true, workout_types: ["crossfit", "strength", "boxing", "muay_thai", "dance"] }),
  );
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const picker = page.getByTestId("workout-type-select");
  await picker.click();
  const options = page.getByRole("listbox").getByRole("option");
  await expect(options).toHaveText(["Διάλεξε τύπο…", "CrossFit", "Δύναμη", "Πυγμαχία", "Muay Thai", "Χορός"]);
  await expect(page.getByRole("listbox")).toContainText("Μαχητικά αθλήματα");
  await expect(page.getByRole("listbox").getByText("crossfit", { exact: true })).toHaveCount(0);
  await page.keyboard.press("Escape");

  await chooseOption(page, picker, "muay_thai");
  await expect(picker).toContainText("Muay Thai");
  await expect.poll(() => server.saves.at(-1)?.type).toBe("muay_thai");
});

test("a WOD keeps a type the box has since hidden", async ({ page }) => {
  await stubCoach(page, { ...sectionedDraft, type: "yoga" });
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) =>
    json(route, { wod_assistant_enabled: true, workout_types: ["crossfit"] }),
  );
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const picker = page.getByTestId("workout-type-select");
  await expect(picker).toContainText("Γιόγκα");
  await picker.click();
  await expect(page.getByRole("listbox").getByRole("option")).toHaveText(["Διάλεξε τύπο…", "CrossFit", "Γιόγκα"]);
});
