import { describe, expect, it } from "vitest";

import { parseJoinInput } from "./join-input";

describe("parseJoinInput", () => {
  it("reads a gym's join link", () => {
    expect(parseJoinInput("https://palee.app/join/box-kypseli")).toEqual({ kind: "join", slug: "box-kypseli" });
    expect(parseJoinInput("palee.app/join/box%20one/")).toEqual({ kind: "join", slug: "box one" });
    expect(parseJoinInput("/join/box-kypseli")).toEqual({ kind: "join", slug: "box-kypseli" });
  });

  it("reads an invitation link or a bare code", () => {
    expect(parseJoinInput("https://palee.app/register?token=abc123")).toEqual({ kind: "invite", token: "abc123" });
    expect(parseJoinInput("  abc123  ")).toEqual({ kind: "invite", token: "abc123" });
  });

  it("rejects anything else", () => {
    expect(parseJoinInput("")).toBeNull();
    expect(parseJoinInput("two words")).toBeNull();
    expect(parseJoinInput("https://palee.app/register")).toBeNull();
  });
});
