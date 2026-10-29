import { describe, expect, it } from "vitest";

import { createDraftHistory, editDraft } from "@/lib/draft-history";

import {
  changedRenewals,
  membershipChangeCount,
  membershipDraftFrom,
  membershipSaveRequests,
  statusOptions,
} from "./membership-draft";

const membership = { status: "trial", starts_on: "2026-10-29T00:00:00Z", expires_on: null };
const subscriptions = [
  { id: "s-1", status: "active", auto_renew: true },
  { id: "s-2", status: "active", auto_renew: false },
  { id: "s-3", status: "expired", auto_renew: true },
  { id: "s-4", status: "active" },
];

describe("membership draft (ADR-276)", () => {
  it("reads the editable fields and only the renewable packages", () => {
    expect(membershipDraftFrom(membership, subscriptions)).toEqual({
      status: "trial",
      starts_on: "2026-10-29",
      expires_on: "",
      auto_renew: { "s-1": true, "s-2": false },
    });
    expect(membershipDraftFrom(null, []).status).toBe("active");
  });

  it("keeps a status set elsewhere visible in the picker", () => {
    expect(statusOptions("trial")).toEqual(["trial", "active", "paused", "cancelled"]);
    expect(statusOptions("paused")).toEqual(["active", "paused", "cancelled"]);
  });

  it("sends only what changed, an emptied date as null, and one call per renewal switch", () => {
    let history = createDraftHistory(membershipDraftFrom({ ...membership, expires_on: "2026-11-28" }, subscriptions));
    expect(membershipSaveRequests(history)).toEqual({ patch: null, renewals: [] });
    history = editDraft(history, { expires_on: "", status: "active" });
    history = editDraft(history, { auto_renew: { ...history.draft.auto_renew, "s-2": true } });
    expect(membershipSaveRequests(history)).toEqual({
      patch: { status: "active", expires_on: null },
      renewals: [{ id: "s-2", autoRenew: true }],
    });
    expect([...changedRenewals(history)]).toEqual(["s-2"]);
    expect(membershipChangeCount(history)).toBe(3);
  });
});
