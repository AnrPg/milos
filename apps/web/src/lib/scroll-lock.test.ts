import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { lockPageScroll, pageScrollLocks } from "@/lib/scroll-lock";

describe("lockPageScroll", () => {
  afterEach(() => {
    document.body.style.overflow = "";
  });

  it("locks once and restores the page's own value after the last release", () => {
    document.body.style.overflow = "auto";
    const first = lockPageScroll();
    const second = lockPageScroll();
    expect(document.body.style.overflow).toBe("hidden");
    expect(pageScrollLocks()).toBe(2);

    first();
    expect(document.body.style.overflow).toBe("hidden");
    second();
    expect(document.body.style.overflow).toBe("auto");
    expect(pageScrollLocks()).toBe(0);
  });

  it("ignores a release that runs twice", () => {
    const first = lockPageScroll();
    const second = lockPageScroll();
    first();
    first();
    expect(document.body.style.overflow).toBe("hidden");
    second();
    expect(document.body.style.overflow).toBe("");
  });

  it("starts fresh after the page was unlocked", () => {
    lockPageScroll()();
    document.body.style.overflow = "clip";
    const release = lockPageScroll();
    expect(document.body.style.overflow).toBe("hidden");
    release();
    expect(document.body.style.overflow).toBe("clip");
  });
});

describe("scroll-lock guard", () => {
  // Every overlay goes through lockPageScroll; a hand-made save-and-restore
  // of body overflow brings back the frozen-page bug.
  it("finds no other code that writes body or html overflow", () => {
    const root = join(__dirname, "..");
    const offenders: string[] = [];
    const walk = (dir: string) => {
      for (const name of readdirSync(dir)) {
        const path = join(dir, name);
        if (statSync(path).isDirectory()) {
          walk(path);
        } else if (/\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name) && !path.endsWith(join("lib", "scroll-lock.ts"))) {
          const source = readFileSync(path, "utf8");
          if (/(body|documentElement)\.style\.overflow\w*\s*=(?!=)/.test(source)) offenders.push(path.slice(root.length + 1));
        }
      }
    };
    walk(root);
    expect(offenders).toEqual([]);
  });
});
