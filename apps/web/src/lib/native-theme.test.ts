import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { describe, expect, it } from "vitest";

import { nativeThemeFiles } from "./native-theme";

const REPOSITORY_ROOT = join(__dirname, "../../../..");
// `npm run theme:native` sets this to rewrite the files instead of checking them.
const WRITE = process.env.PALEE_WRITE_NATIVE_THEME === "1";

describe("native theme files", () => {
  it.each(Object.entries(nativeThemeFiles()))("%s matches src/lib/theme.ts", (path, contents) => {
    const file = join(REPOSITORY_ROOT, path);
    if (WRITE) {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, contents);
    }
    expect(existsSync(file), `${path} is missing: run npm run theme:native`).toBe(true);
    expect(readFileSync(file, "utf8"), `${path} is out of date: run npm run theme:native`).toBe(contents);
  });
});
