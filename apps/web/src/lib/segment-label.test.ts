import { describe, expect, it } from "vitest";

import en from "../../messages/en.json";
import { SEGMENT_LABEL_KEYS, segmentLabel } from "./segment-label";

const translate = (key: string, params: Record<string, string | number | Date> = {}) =>
  `${key}:${JSON.stringify(params)}`;

describe("segmentLabel", () => {
  it("localizes keyed labels with their parameters", () => {
    expect(segmentLabel({ label: "Work 1/8", label_key: "work", label_params: { round: 1, total: 8 } }, translate))
      .toBe('timerLabelWork:{"round":1,"total":8}');
  });

  it("falls back to the English label for unknown or missing keys", () => {
    expect(segmentLabel({ label: "AMRAP 12", label_key: null }, translate)).toBe("AMRAP 12");
    expect(segmentLabel({ label: "Brand new", label_key: "from_the_future" }, translate)).toBe("Brand new");
  });

  it("has an English message for every label key the API sends", () => {
    const messages = Object.values(en).flatMap((namespace) => Object.keys(namespace as object));
    for (const key of SEGMENT_LABEL_KEYS) {
      const message = `timerLabel${key.replace(/(^|_)(\w)/g, (_m, _s, c: string) => c.toUpperCase())}`;
      expect(messages).toContain(message);
    }
  });
});
