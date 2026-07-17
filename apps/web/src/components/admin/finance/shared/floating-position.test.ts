import { describe, expect, it } from "vitest";

import { floatingPosition } from "@/components/admin/finance/shared/floating-position";

describe("floatingPosition", () => {
  it("places a ledger overlay above its trigger when the table bottom has no room", () => {
    expect(
      floatingPosition(
        { left: 200, right: 320, top: 680, bottom: 712, width: 120, height: 32 },
        { width: 260, height: 300 },
        { width: 1365, height: 768 },
      ),
    ).toMatchObject({ left: 200, top: 372, placement: "top" });
  });

  it("keeps the overlay inside the viewport while preserving its requested width", () => {
    expect(
      floatingPosition(
        { left: 1280, right: 1340, top: 80, bottom: 112, width: 60, height: 32 },
        { width: 240, height: 180 },
        { width: 1365, height: 768 },
      ),
    ).toMatchObject({ left: 1109, top: 120, placement: "bottom" });
  });
});
