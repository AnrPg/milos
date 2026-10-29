import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import {
  GROUP_PROGRAMMING_LIMIT,
  classDay,
  groupOutcomeRows,
  outcomeCounts,
  toggleSelection,
  variationCandidates,
} from "@/lib/group-variations";

describe("variationCandidates", () => {
  it("lists approved and pending attendees once, without guests, by name", () => {
    const candidates = variationCandidates(
      [
        { user_id: "u2", user_nickname: "Zoe", status: "approved" },
        { user_id: "u1", user_nickname: "Anna", status: "pending" },
        { user_id: "u1", user_nickname: "Anna", status: "approved" },
        { user_id: "u2", user_nickname: "Zoe", status: "approved", guest_name: "Guest of Zoe" },
        { user_id: "u3", user_nickname: "Cancelled", status: "cancelled" },
        { user_id: "u4", user_nickname: "Waiting", status: "waitlisted" },
        { user_id: "u5", user_nickname: null, status: "approved" },
      ],
      [{ user_id: "u2" }],
    );

    expect(candidates).toEqual([
      { userId: "u1", nickname: "Anna", hasVersion: false },
      { userId: "u5", nickname: "u5", hasVersion: false },
      { userId: "u2", nickname: "Zoe", hasVersion: true },
    ]);
  });
});

describe("toggleSelection", () => {
  it("adds, removes and stops at the limit", () => {
    expect(toggleSelection([], "a")).toEqual(["a"]);
    expect(toggleSelection(["a", "b"], "a")).toEqual(["b"]);
    expect(toggleSelection(["a", "b"], "c", 2)).toEqual(["a", "b"]);
    expect(GROUP_PROGRAMMING_LIMIT).toBe(50);
  });
});

describe("classDay", () => {
  it("files a class under its UTC day", () => {
    expect(classDay("2026-10-26T23:30:00-02:00")).toBe("2026-10-27");
    expect(classDay("2026-10-26T07:00:00Z")).toBe("2026-10-26");
  });
});

describe("groupOutcomeRows", () => {
  it("keeps the API order and turns failures into localizable errors", () => {
    const rows = groupOutcomeRows(
      [
        { user_id: "u1", status: "ok", mode: "class_variant" },
        {
          user_id: "u2",
          status: "error",
          code: "programming_not_in_package",
          params: { nickname: "Zoe", reason: "finance_channel_not_included" },
        },
        { user_id: "u3", status: "error", code: "slot_not_booked_by_member" },
        { user_id: "u4", status: "error" },
      ],
      new Map([
        ["u1", "Anna"],
        ["u2", "Zoe"],
      ]),
    );

    expect(rows.map((row) => [row.userId, row.nickname, row.ok])).toEqual([
      ["u1", "Anna", true],
      ["u2", "Zoe", false],
      ["u3", "u3", false],
      ["u4", "u4", false],
    ]);
    expect(rows[1].error).toBeInstanceOf(ApiError);
    expect(rows[1].error?.status).toBe(403);
    expect(rows[1].error?.payload).toEqual({
      code: "programming_not_in_package",
      params: { nickname: "Zoe", reason: "finance_channel_not_included" },
    });
    expect(rows[2].error?.status).toBe(422);
    expect(rows[3].error?.payload.code).toBe("unexpected_server_error");
    expect(rows[3].error?.status).toBe(500);
    expect(outcomeCounts(rows)).toEqual({ succeeded: 1, failed: 3 });
  });
});
