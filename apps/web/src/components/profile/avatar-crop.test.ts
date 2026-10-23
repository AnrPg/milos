import { describe, expect, it } from "vitest";

import { isSupportedAvatarSource } from "@/components/profile/avatar-crop";

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
