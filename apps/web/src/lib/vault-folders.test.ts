import { describe, expect, it } from "vitest";

import type { VaultGroup } from "@/api/account-training";

import { folderTrail, vaultFolders } from "./vault-folders";

const box = { kind: "organization" as const, organization_id: "org-box", name: "Box", former: false };
const coach = { kind: "organization" as const, organization_id: "org-coach", name: "Nikos", former: false };
const freeform = { kind: "freeform" as const, organization_id: null, name: null, former: false };

const group = (identity: string, type: string | null, sources: VaultGroup["sources"]): VaultGroup => ({
  identity,
  title: identity,
  workout_type: type,
  sources,
  attempts: [],
  attempt_count: 1,
  last_at: "2026-10-20T08:00:00Z",
});

describe("vaultFolders", () => {
  it("files by source, then type, with untyped workouts last", () => {
    const folders = vaultFolders([
      group("fran", "for_time", [box, coach]),
      group("cindy", "amrap", [box]),
      group("run", null, [freeform]),
    ]);
    expect(folders.map((folder) => folder.id)).toEqual(["source:org-box", "source:org-coach", "source:freeform"]);
    expect(folders[0].count).toBe(2);
    expect(folders[0].folders.map((folder) => folder.id)).toEqual(["source:org-box/type:amrap", "source:org-box/type:for_time"]);
    expect(folders[1].folders[0].groups.map((item) => item.identity)).toEqual(["fran"]);
    expect(folders[2].folders[0].label).toEqual({ kind: "type", type: null });
  });

  it("skips the source level with a single source", () => {
    const folders = vaultFolders([group("fran", "for_time", [box]), group("x", null, [box])]);
    expect(folders.map((folder) => folder.id)).toEqual(["type:for_time", "type:other"]);
  });

  it("is empty without workouts", () => {
    expect(vaultFolders([])).toEqual([]);
  });
});

describe("folderTrail", () => {
  it("follows a path and stops at a folder that is gone", () => {
    const roots = vaultFolders([group("fran", "for_time", [box]), group("cindy", "amrap", [coach])]);
    expect(folderTrail(roots, ["source:org-box", "source:org-box/type:for_time"]).map((folder) => folder.id)).toEqual([
      "source:org-box",
      "source:org-box/type:for_time",
    ]);
    expect(folderTrail(roots, ["source:gone", "x"])).toEqual([]);
  });
});
