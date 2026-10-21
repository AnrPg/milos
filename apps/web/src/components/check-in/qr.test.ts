import { describe, expect, it } from "vitest";
import jsQR from "jsqr";

import { qrSvgPath } from "./qr";

/** Rasterises the path back into RGBA pixels and reads it with the desk's fallback decoder. */
function decode(text: string) {
  const { size, path } = qrSvgPath(text);
  const scale = 4;
  const width = size * scale;
  const pixels = new Uint8ClampedArray(width * width * 4).fill(255);
  for (const [, x, y, run] of path.matchAll(/M(\d+) (\d+)h(\d+)/g)) {
    for (let dx = 0; dx < Number(run) * scale; dx += 1) {
      for (let dy = 0; dy < scale; dy += 1) {
        const offset = ((Number(y) * scale + dy) * width + Number(x) * scale + dx) * 4;
        pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 0;
      }
    }
  }
  return jsQR(pixels, width, width)?.data ?? null;
}

describe("qrSvgPath", () => {
  it("draws a door deep link that scans back to the same link", () => {
    const link = "https://palee.app/c/7d0f6a5e-1c2b-4d3e-9f80-0a1b2c3d4e5f/AbCdEf0123456789";
    expect(decode(link)).toBe(link);
  });

  it("draws a personal code that scans back, with the quiet zone in the view box", () => {
    const code = "S1AAAAAAAAAAAAAAAqdQ7f3n0b1cZ8kX";
    const { size, path } = qrSvgPath(code);
    expect(size).toBeGreaterThanOrEqual(21 + 8);
    expect(path.startsWith("M4 4h7")).toBe(true); // the top-left finder pattern
    expect(decode(code)).toBe(code);
  });
});
