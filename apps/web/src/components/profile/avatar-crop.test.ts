import { describe, expect, it } from "vitest";

import { calculateAvatarCrop, isSupportedAvatarSource } from "@/components/profile/avatar-crop";

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

describe("isSupportedAvatarSource", () => {
  it("accepts browser-decodable avatar source image types", () => {
    expect(isSupportedAvatarSource({ name: "avatar.avif", type: "image/avif" })).toBe(true);
    expect(isSupportedAvatarSource({ name: "avatar.gif", type: "image/gif" })).toBe(true);
    expect(isSupportedAvatarSource({ name: "avatar.bmp", type: "image/bmp" })).toBe(true);
  });

  it("falls back to file extension when the browser omits the MIME type", () => {
    expect(isSupportedAvatarSource({ name: "avatar.JPEG", type: "" })).toBe(true);
    expect(isSupportedAvatarSource({ name: "avatar.webp", type: "" })).toBe(true);
  });

  it("rejects unsupported or unsafe source formats", () => {
    expect(isSupportedAvatarSource({ name: "avatar.svg", type: "image/svg+xml" })).toBe(false);
    expect(isSupportedAvatarSource({ name: "avatar.txt", type: "text/plain" })).toBe(false);
  });
});
