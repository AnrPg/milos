import { describe, expect, it } from "vitest";

import { invitationSignUpPath, invitationTokenFromLocation, parseInviteAddresses } from "./organizations";

describe("ADR-209 invitation helpers", () => {
  it("parses pasted text and CSV into unique addresses and keeps what it skipped", () => {
    expect(parseInviteAddresses('name,email\n"Nikos@Example.com";maria@example.com, nikos@example.com nope')).toEqual({
      emails: ["nikos@example.com", "maria@example.com"],
      skipped: ["name", "email", "nope"],
    });
    expect(parseInviteAddresses("   ")).toEqual({ emails: [], skipped: [] });
  });

  it("reads the token from the fragment first, then from the query", () => {
    expect(invitationTokenFromLocation({ hash: "#token=frag", search: "?token=query" })).toBe("frag");
    expect(invitationTokenFromLocation({ hash: "", search: "?token=query" })).toBe("query");
    expect(invitationTokenFromLocation({ hash: "", search: "" })).toBe("");
  });

  it("sends owners and admins to the admin sign-up", () => {
    expect(invitationSignUpPath({ role: "admin" })).toBe("/set-admin");
    expect(invitationSignUpPath({ role: "coach", roles: ["coach", "owner"] })).toBe("/set-admin");
    expect(invitationSignUpPath({ role: "member" })).toBe("/register");
  });
});
