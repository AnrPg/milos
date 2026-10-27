import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

// docs/product/ontology.md §1: Greek never shows "PT" or "squad", roles name
// the person (not the department), and a member always says what of.
const locales = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];
const ROLE_KEYS = ["roleOwner", "roleAdmin", "roleCoach", "roleFrontDesk", "roleAccountant", "roleJanitor", "roleMember", "roleAthlete"];

function catalog(locale: string) {
  return JSON.parse(fs.readFileSync(path.resolve("messages", `${locale}.json`), "utf8")) as Record<string, unknown>;
}

function strings(node: unknown): string[] {
  if (typeof node === "string") return [node];
  if (node && typeof node === "object") return Object.values(node).flatMap(strings);
  return [];
}

describe("canonical wording", () => {
  it("never writes PT or squad in Greek", () => {
    const offending = strings(catalog("el")).filter((text) => /\bPT\b|squad/i.test(text));
    expect(offending).toEqual([]);
  });

  it("labels every role in every locale", () => {
    for (const locale of locales) {
      const ui = catalog(locale).Ui as Record<string, string>;
      for (const key of ROLE_KEYS) expect(ui[key], `${locale}.${key}`).toBeTruthy();
    }
  });

  it("uses person words for Greek roles and a qualified member", () => {
    const ui = catalog("el").Ui as Record<string, string>;
    expect(ui.roleJanitor).toBe("Προσωπικό καθαριότητας");
    expect(ui.roleAccountant).toBe("Λογιστής");
    expect(ui.roleMember).not.toBe("Μέλος");
  });
});
