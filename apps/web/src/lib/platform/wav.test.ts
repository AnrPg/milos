import { describe, expect, it } from "vitest";

import { encodeWav, toBase64, toMono16k } from "./wav";

describe("wav", () => {
  it("writes a 16-bit mono PCM header and clamps samples", () => {
    const bytes = encodeWav(new Float32Array([0, 1, -1, 2]), 16_000);
    const view = new DataView(bytes.buffer);
    expect(String.fromCharCode(...bytes.subarray(0, 4))).toBe("RIFF");
    expect(String.fromCharCode(...bytes.subarray(8, 12))).toBe("WAVE");
    expect(view.getUint16(22, true)).toBe(1);
    expect(view.getUint32(24, true)).toBe(16_000);
    expect(view.getUint32(40, true)).toBe(8);
    expect(view.getInt16(46, true)).toBe(0x7fff);
    expect(view.getInt16(48, true)).toBe(-0x8000);
    expect(view.getInt16(50, true)).toBe(0x7fff);
  });

  it("mixes to mono and resamples to 16 kHz", () => {
    const left = new Float32Array(48_000).fill(0.5);
    const right = new Float32Array(48_000).fill(-0.5);
    const mono = toMono16k([left, right], 48_000);
    expect(mono.length).toBe(16_000);
    expect(mono[100]).toBeCloseTo(0);
    expect(toMono16k([new Float32Array([0.25, 0.25])], 16_000)).toEqual(new Float32Array([0.25, 0.25]));
    expect(toMono16k([], 44_100).length).toBe(0);
  });

  it("base64-encodes large buffers in chunks", () => {
    const bytes = new Uint8Array(100_000).fill(65);
    expect(toBase64(bytes).startsWith("QUFB")).toBe(true);
    expect(atob(toBase64(new Uint8Array([1, 2, 3])))).toBe("\u0001\u0002\u0003");
  });
});
