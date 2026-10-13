import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

import { TOUR_STEPS, checklistLaterKey } from "./onboarding";

const locales = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];
const CHECKLIST_STEPS = ["settings", "classes", "packages", "workout", "invite", "tour"];

function catalog(locale: string) {
  return JSON.parse(fs.readFileSync(path.resolve("messages", `${locale}.json`), "utf8")).Onboarding;
}

describe("onboarding copy", () => {
  it.each(locales)("%s has a title and body for every tour step and checklist step", (locale) => {
    const messages = catalog(locale);
    for (const [audience, steps] of Object.entries(TOUR_STEPS)) {
      expect(steps.length).toBeGreaterThanOrEqual(3);
      expect(steps.length).toBeLessThanOrEqual(6);
      for (const step of steps) {
        expect(messages.tour[audience][step.id].title, `${audience}.${step.id}`).toBeTruthy();
        expect(messages.tour[audience][step.id].body, `${audience}.${step.id}`).toBeTruthy();
      }
    }
    for (const step of CHECKLIST_STEPS) {
      expect(Object.keys(messages.steps[step]).sort()).toEqual(["body", "cta", "title"]);
    }
  });

  it("builds namespaced storage keys", () => {
    expect(checklistLaterKey("acme")).toBe("milos:onboarding-later:acme");
  });
});
