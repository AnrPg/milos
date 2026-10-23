import { beforeEach, describe, expect, it } from "vitest";

import { stashClassDraft, takeClassDraft } from "./class-draft-handoff";

describe("class draft handoff", () => {
  beforeEach(() => window.sessionStorage.clear());

  it("gives the stashed form back once", () => {
    stashClassDraft({ kind: "slot", name: "CrossFit" }, 1_000);
    expect(takeClassDraft(2_000)).toEqual({ kind: "slot", name: "CrossFit" });
    expect(takeClassDraft(2_000)).toBeNull();
  });

  it("drops a form left hours ago", () => {
    stashClassDraft({ kind: "series" }, 0);
    expect(takeClassDraft(7 * 60 * 60 * 1000)).toBeNull();
  });
});
