import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

import type { GuideProgress } from "@/api/guides";

import { anchorSelectors, GUIDE_ANCHORS, type GuideAnchor } from "./anchors";
import { availableGuides, guideState, onRoute, resolveRoute, resumeIndex, routeHref, shouldOffer, stripOrganization, visibleSteps } from "./engine";
import { cardPlacement, spotlightRect } from "./placement";
import { GUIDES, guideById } from "./registry";
import type { GuideAbilities } from "./types";

const MESSAGES = join(__dirname, "..", "..", "..", "messages");
const SOURCE = join(__dirname, "..", "..");
const LOCALES = readdirSync(MESSAGES).filter((name) => name.endsWith(".json"));

const everyone: GuideAbilities = { staff: true, manager: true, demo: false, hosts: true, inGymClub: true };
const member: GuideAbilities = { staff: false, manager: false, demo: false, hosts: false, inGymClub: false };

function lookup(tree: unknown, path: string): unknown {
  return path.split(".").reduce<unknown>((node, key) => (node && typeof node === "object" ? (node as Record<string, unknown>)[key] : undefined), tree);
}

function progress(patch: Partial<GuideProgress>): GuideProgress {
  return {
    guide_id: "shop_staff",
    version: 1,
    status: "started",
    step: 0,
    runs: 1,
    started_at: "2026-10-24T08:00:00Z",
    completed_at: null,
    updated_at: "2026-10-24T08:00:00Z",
    ...patch,
  };
}

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) return relative(SOURCE, path) === "api/generated" ? [] : sourceFiles(path);
    return entry.endsWith(".tsx") && !entry.includes(".test.") ? [path] : [];
  });
}

describe("guide registry (ADR-193)", () => {
  it("has copy for every step, chapter and label in every locale", () => {
    for (const file of LOCALES) {
      const messages = JSON.parse(readFileSync(join(MESSAGES, file), "utf8"));
      const missing: string[] = [];
      for (const guide of GUIDES) {
        for (const key of ["title", "summary"]) if (typeof lookup(messages, `Guides.${guide.id}.${key}`) !== "string") missing.push(`${guide.id}.${key}`);
        for (const step of guide.steps) {
          const keys = ["title", "body", ...(step.tip ? ["tip"] : [])].map((key) => `Guides.${guide.id}.${step.id}.${key}`);
          if (step.chapter) keys.push(`Guides.${guide.id}.chapters.${step.chapter}`);
          for (const [name, path] of Object.entries(step.labels ?? {})) {
            keys.push(path);
            const body = String(lookup(messages, `Guides.${guide.id}.${step.id}.body`) ?? "") + String(lookup(messages, `Guides.${guide.id}.${step.id}.tip`) ?? "");
            if (!body.includes(`{${name}}`)) missing.push(`${guide.id}.${step.id} never quotes {${name}}`);
          }
          for (const key of keys) if (typeof lookup(messages, key) !== "string") missing.push(key);
        }
      }
      expect(missing, file).toEqual([]);
    }
  });

  it("points only at anchors some screen marks", () => {
    const source = sourceFiles(SOURCE).map((path) => readFileSync(path, "utf8")).join("\n");
    const marked = (anchor: GuideAnchor) =>
      source.includes(`guideAnchor("${anchor}")`) ||
      source.includes(`guide="${anchor}"`) ||
      source.includes(`Guide="${anchor}"`) ||
      anchorSelectors(anchor).some((selector) => {
        const base = selector.match(/\[data-guide="([^"]+)"\]/)?.[1];
        return base !== undefined && base !== anchor && (source.includes(`guideAnchor("${base}")`) || source.includes(`guide="${base}"`));
      });
    const used = new Set<GuideAnchor>();
    for (const guide of GUIDES) {
      for (const step of guide.steps) {
        [step.anchor, step.leave, step.action?.target, step.action?.until, step.action?.untilGone].forEach((anchor) => anchor && used.add(anchor));
      }
    }
    expect([...used].filter((anchor) => !marked(anchor))).toEqual([]);
    expect([...used].every((anchor) => GUIDE_ANCHORS.includes(anchor))).toBe(true);
  });

  it("gives every step a unique id and ends on a closing step", () => {
    for (const guide of GUIDES) {
      const ids = guide.steps.map((step) => step.id);
      expect(new Set(ids).size, guide.id).toBe(ids.length);
      expect(ids.at(-1), guide.id).toBe("done");
      expect(guide.steps[0].route ?? guide.steps[0].anchor, guide.id).toBeUndefined();
    }
  });
});

describe("guide engine", () => {
  it("leaves out steps for what the person cannot do", () => {
    const guide = guideById("member_club_event");
    const ids = visibleSteps(guide, member).map((step) => step.id);
    expect(ids).toContain("noBox");
    expect(ids).not.toContain("groups");
    expect(visibleSteps(guide, everyone).map((step) => step.id)).not.toContain("noBox");
  });

  it("lists the guides each person may open, staff ones first", () => {
    expect(availableGuides(GUIDES, member).map((guide) => guide.id)).toEqual(["member_club_event"]);
    expect(availableGuides(GUIDES, everyone).map((guide) => guide.audience)).toEqual(["staff", "staff", "staff", "member"]);
  });

  it("matches routes under a business prefix and builds their links", () => {
    const route = { path: "/admin/shop", admin: true, query: { tab: "stock" } };
    expect(stripOrganization("/org/box-a/admin/shop")).toBe("/admin/shop");
    expect(onRoute(route, "/org/box-a/admin/shop", "tab=stock&x=1")).toBe(true);
    expect(onRoute(route, "/org/box-a/admin/shop", "tab=orders")).toBe(false);
    expect(routeHref(route, "box-a")).toBe("/org/box-a/admin/shop?tab=stock");
    expect(routeHref({ path: "/events" }, "box-a")).toBe("/events");
    expect(resolveRoute({ path: "/clubs/:gymClub" }, { gymClub: "c 1" })).toEqual({ path: "/clubs/c%201" });
    expect(resolveRoute({ path: "/clubs/:gymClub" }, {})).toBeNull();
  });

  it("reads stored progress", () => {
    const guide = guideById("shop_staff");
    expect(guideState(guide, null)).toBe("new");
    expect(guideState(guide, progress({ status: "completed" }))).toBe("completed");
    expect(guideState({ ...guide, version: 2 }, progress({ status: "completed" }))).toBe("outdated");
    expect(guideState({ ...guide, version: 2 }, progress({ status: "started", step: 4 }))).toBe("new");
  });

  it("resumes at the nearest step that can open on its own", () => {
    const guide = guideById("shop_staff");
    const steps = visibleSteps(guide, everyone);
    const photos = steps.findIndex((step) => step.id === "photos");
    const stock = steps.findIndex((step) => step.id === "stock");
    expect(resumeIndex(guide, progress({ step: photos }), steps)).toBe(0);
    expect(resumeIndex(guide, progress({ step: stock }), steps)).toBe(stock);
    expect(resumeIndex(guide, progress({ step: stock, status: "completed" }), steps)).toBe(0);
  });

  it("offers a guide once, on its home", () => {
    const guide = guideById("shop_staff");
    expect(shouldOffer(guide, null, "/org/a/admin/shop", "")).toBe(true);
    expect(shouldOffer(guide, null, "/org/a/admin/finance", "")).toBe(false);
    expect(shouldOffer(guide, progress({ status: "dismissed" }), "/org/a/admin/shop", "")).toBe(false);
    expect(shouldOffer(guide, progress({ status: "started" }), "/org/a/admin/shop", "")).toBe(false);
    expect(shouldOffer({ ...guide, version: 2 }, progress({ status: "completed" }), "/org/a/admin/shop", "")).toBe(true);
    expect(shouldOffer({ ...guide, version: 2 }, progress({ status: "dismissed" }), "/org/a/admin/shop", "")).toBe(false);
  });
});

describe("card placement", () => {
  const viewport = { width: 1200, height: 800 };
  const card = { width: 360, height: 200 };
  const spot = (top: number, height = 40, left = 100, width = 200) => ({ left, top, width, height, right: left + width, bottom: top + height });

  it("goes below the spot, then above, then beside, never over it", () => {
    expect(cardPlacement(spot(100), card, viewport)).toEqual({ kind: "float", left: 100, top: 152 });
    expect(cardPlacement(spot(700), card, viewport)).toEqual({ kind: "float", left: 100, top: 488 });
    const tall = cardPlacement(spot(50, 700), card, viewport);
    expect(tall).toEqual({ kind: "float", left: 312, top: 50 });
    expect(cardPlacement(spot(10, 780, 10, 1180), card, viewport)).toEqual({ kind: "float", left: 824, top: 584 });
  });

  it("is a sheet on phones, on the edge away from the spot", () => {
    const phone = { width: 390, height: 800 };
    expect(cardPlacement(spot(100), card, phone)).toEqual({ kind: "sheet", edge: "bottom" });
    expect(cardPlacement(spot(600), card, phone)).toEqual({ kind: "sheet", edge: "top" });
    expect(cardPlacement(null, card, phone)).toEqual({ kind: "center" });
  });

  it("keeps the highlighted hole on screen", () => {
    expect(spotlightRect(spot(0, 40, 0, 50), viewport)).toEqual({ left: 2, top: 2, width: 54, height: 44 });
  });
});
