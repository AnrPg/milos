import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const locales = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];

describe("package-count translations", () => {
  it("uses one ICU plural message in every supported locale", () => {
    for (const locale of locales) {
      const catalog = JSON.parse(
        fs.readFileSync(path.resolve("messages", `${locale}.json`), "utf8"),
      ) as { Ui: Record<string, string> };

      expect(catalog.Ui.activePackagesCount02af29c).toMatch(/\{count, plural,/);
    }
  });

  it("uses the Greek plural form for multiple packages", () => {
    const catalog = JSON.parse(
      fs.readFileSync(path.resolve("messages/el.json"), "utf8"),
    ) as { Ui: Record<string, string> };

    expect(catalog.Ui.activePackagesCount02af29c).toContain("# ενεργά πακέτα");
  });
});
