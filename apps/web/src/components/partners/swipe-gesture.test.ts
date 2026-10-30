import { describe, expect, it } from "vitest";

import { SWIPE_THRESHOLD, dragTilt, dragTransform, flyTransform, keyDecision, stampOpacity, swipeDecision } from "./swipe-gesture";

describe("the deck card's drag (ADR-280)", () => {
  it("decides only past the threshold: right is like, left is pass", () => {
    expect(swipeDecision(SWIPE_THRESHOLD)).toBe("like");
    expect(swipeDecision(SWIPE_THRESHOLD + 40)).toBe("like");
    expect(swipeDecision(-SWIPE_THRESHOLD)).toBe("pass");
    expect(swipeDecision(SWIPE_THRESHOLD - 1)).toBeNull();
    expect(swipeDecision(-(SWIPE_THRESHOLD - 1))).toBeNull();
    expect(swipeDecision(0)).toBeNull();
  });

  it("tilts with the drag, capped, and not at all with reduced motion", () => {
    expect(dragTilt(150)).toBeCloseTo(10);
    expect(dragTilt(-150)).toBeCloseTo(-10);
    expect(dragTilt(1000)).toBe(18);
    expect(dragTilt(-1000)).toBe(-18);
    expect(dragTilt(150, true)).toBe(0);
  });

  it("moves the card with the finger and rests without a transform", () => {
    expect(dragTransform(0)).toBeUndefined();
    expect(dragTransform(60)).toBe("translateX(60px) rotate(4.00deg)");
    expect(dragTransform(-60, true)).toBe("translateX(-60px) rotate(0.00deg)");
  });

  it("flies a decided card off the side it was sent to", () => {
    expect(flyTransform("like")).toMatch(/^translateX\(640px\) rotate\(18deg\)$/);
    expect(flyTransform("pass")).toMatch(/^translateX\(-640px\) rotate\(-18deg\)$/);
    expect(flyTransform("like", true)).toBe("translateX(640px) rotate(0deg)");
  });

  it("fades the «ΝΑΙ» stamp in to the right and «ΟΧΙ» to the left", () => {
    expect(stampOpacity(0)).toEqual({ like: 0, pass: 0 });
    expect(stampOpacity(40)).toEqual({ like: 0.5, pass: 0 });
    expect(stampOpacity(-200)).toEqual({ like: 0, pass: 1 });
  });

  it("swipes with the arrow keys", () => {
    expect(keyDecision("ArrowRight")).toBe("like");
    expect(keyDecision("ArrowLeft")).toBe("pass");
    expect(keyDecision("Enter")).toBeNull();
  });
});
