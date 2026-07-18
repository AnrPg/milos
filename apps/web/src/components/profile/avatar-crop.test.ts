import { describe, expect, it } from "vitest";

import { calculateAvatarCrop } from "@/components/profile/avatar-crop";

describe("calculateAvatarCrop", () => {
  it("cover-crops a landscape image around its center", () => {
    expect(calculateAvatarCrop(1200, 800, 512, 1, 0, 0)).toEqual({
      dx: -128,
      dy: 0,
      height: 512,
      width: 768,
    });
  });

  it("uses zoom and framing controls without exposing empty canvas", () => {
    expect(calculateAvatarCrop(800, 1200, 512, 1.5, 100, -100)).toEqual({
      dx: 0,
      dy: -640,
      height: 1152,
      width: 768,
    });
  });

  it("calculates the crop against rotated image bounds", () => {
    expect(calculateAvatarCrop(1200, 800, 512, 1, 0, 0, 90)).toEqual({
      dx: 0,
      dy: -128,
      height: 768,
      width: 512,
    });
  });
});
