import { describe, expect, it } from "vitest";

import { INBOX_SOURCES } from "./inbox-sections";

describe("INBOX_SOURCES", () => {
  it("files check-in buddy chats under «Άτομα» and keeps «Συναθλητές» for training partners (ontology §5.1)", () => {
    const segmentsOf = (id: string) => INBOX_SOURCES.find((source) => source.id === id)?.segments;

    expect(segmentsOf("buddies")).toEqual(["people"]);
    expect(segmentsOf("partners")).toEqual(["partners"]);
    expect(segmentsOf("box-conversations")).toEqual(["clubs"]);
  });
});
