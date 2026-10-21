import { describe, expect, it } from "vitest";

import { activeProfileTab, notesAbout, subjectKindsFor, visibleProfileTabs } from "./member-profile-tabs";

describe("member profile tabs", () => {
  it("shows only the tabs whose sections the viewer has, in order", () => {
    expect(visibleProfileTabs(["finance", "prs", "admin_actions"])).toEqual(["overview", "training", "finance", "account"]);
    expect(visibleProfileTabs([])).toEqual(["overview"]);
    expect(visibleProfileTabs(["health_incidents", "body", "coach_notes"])).toEqual(["overview", "wellbeing", "body", "coaching"]);
  });

  it("opens the URL's tab, falls back to the section's tab, then Επισκόπηση", () => {
    const visible = visibleProfileTabs(["prs", "finance"]);
    expect(activeProfileTab(visible, "finance")).toBe("finance");
    expect(activeProfileTab(visible, "account")).toBe("overview");
    expect(activeProfileTab(visible, null, "prs")).toBe("training");
    expect(activeProfileTab(visible, null, "coach_notes")).toBe("overview");
  });

  it("files subject notes under their tab and keeps every note in Coaching", () => {
    const notes = [{ subject_kind: "pr" as const }, { subject_kind: "injury" as const }, { subject_kind: null }];
    expect(subjectKindsFor("wellbeing")).toEqual(["injury"]);
    expect(notesAbout(notes, subjectKindsFor("training"))).toEqual([{ subject_kind: "pr" }]);
    expect(notesAbout(notes)).toHaveLength(3);
  });
});
