import { describe, expect, it } from "vitest";

import {
  IDENTITY_TRANSFORM,
  avatarDrawRect,
  axisMovability,
  clampTransform,
  coverScale,
  cropCornersInImage,
  normalizeRotation,
  panBy,
  panRange,
  panToSlider,
  rotateTo,
  sliderToPan,
  zoomTo,
  type AvatarTransform,
} from "@/lib/avatar-crop";

const square = { width: 1000, height: 1000 };
const landscape = { width: 1200, height: 800 };
const portrait = { width: 800, height: 1200 };

function t(partial: Partial<AvatarTransform>): AvatarTransform {
  return { ...IDENTITY_TRANSFORM, ...partial };
}

/** Every window corner must land inside the image (with float tolerance). */
function expectCovered(image: { width: number; height: number }, transform: AvatarTransform) {
  for (const corner of cropCornersInImage(image, transform)) {
    expect(corner.x).toBeGreaterThanOrEqual(-1e-6);
    expect(corner.y).toBeGreaterThanOrEqual(-1e-6);
    expect(corner.x).toBeLessThanOrEqual(image.width + 1e-6);
    expect(corner.y).toBeLessThanOrEqual(image.height + 1e-6);
  }
}

describe("normalizeRotation", () => {
  it("wraps into 0–360 and keeps right angles exact", () => {
    expect(normalizeRotation(360)).toBe(0);
    expect(normalizeRotation(-90)).toBe(270);
    expect(normalizeRotation(450)).toBe(90);
    expect(normalizeRotation(Number.NaN)).toBe(0);
  });
});

describe("coverScale", () => {
  it("fits the short side to the window without rotation", () => {
    expect(coverScale(landscape, 0)).toBeCloseTo(1 / 800);
    expect(coverScale(landscape, 90)).toBeCloseTo(1 / 800);
  });

  it("grows by √2 at 45° so the window's corners stay on the photo", () => {
    expect(coverScale(square, 45)).toBeCloseTo(Math.SQRT2 / 1000);
  });
});

describe("axis movability", () => {
  it("cannot move a square photo at zoom 1 on either axis", () => {
    expect(axisMovability(square, t({}))).toEqual({ x: false, y: false });
  });

  it("moves a landscape photo only horizontally at zoom 1, and vertically after a quarter turn", () => {
    expect(axisMovability(landscape, t({}))).toEqual({ x: true, y: false });
    expect(axisMovability(landscape, t({ rotation: 90 }))).toEqual({ x: false, y: true });
    expect(axisMovability(portrait, t({}))).toEqual({ x: false, y: true });
  });

  it("re-enables both axes as soon as zoom allows movement", () => {
    expect(axisMovability(square, t({ zoom: 1.01 }))).toEqual({ x: true, y: true });
  });

  it("keeps a square photo locked at 45° and zoom 1, since it just covers the window", () => {
    expect(axisMovability(square, t({ rotation: 45 }))).toEqual({ x: false, y: false });
  });

  it("gives the exact range for an axis-aligned zoom", () => {
    const range = panRange(square, t({ zoom: 2 }));
    expect(range.x).toBeCloseTo(0.5);
    expect(range.y).toBeCloseTo(0.5);
  });
});

describe("clampTransform", () => {
  it("pulls an out-of-range pan back to the photo's edge", () => {
    const clamped = clampTransform(landscape, t({ panX: 5, panY: 5 }));
    // 1200×800 at scale 1/800 is 1.5 wide: 0.25 slack on x, none on y.
    expect(clamped.panX).toBeCloseTo(0.25);
    expect(clamped.panY).toBe(0);
    expectCovered(landscape, clamped);
  });

  it("clamps zoom and rotation into range", () => {
    expect(clampTransform(square, t({ zoom: 0.2, rotation: -30 }))).toMatchObject({ zoom: 1, rotation: 330 });
    expect(clampTransform(square, t({ zoom: 99 })).zoom).toBe(4);
    expect(clampTransform(square, t({ rotation: 360 })).rotation).toBe(360);
    expect(clampTransform(square, t({ rotation: 450 })).rotation).toBe(90);
  });

  it("keeps the window covered for any rotation, zoom and pan", () => {
    for (const image of [square, landscape, portrait]) {
      for (let rotation = 0; rotation < 360; rotation += 15) {
        for (const zoom of [1, 1.3, 2.5]) {
          for (const [panX, panY] of [
            [3, 3],
            [-3, 1],
            [0.2, -0.4],
          ]) {
            expectCovered(image, clampTransform(image, t({ rotation, zoom, panX, panY })));
          }
        }
      }
    }
  });

  it("leaves an already valid pan untouched", () => {
    const transform = t({ zoom: 2, rotation: 30, panX: 0.05, panY: -0.05 });
    const clamped = clampTransform(square, transform);
    expect(clamped.panX).toBeCloseTo(transform.panX, 10);
    expect(clamped.panY).toBeCloseTo(transform.panY, 10);
  });
});

describe("sliders", () => {
  it("maps the slider to the full range of the axis and back", () => {
    const zoomed = t({ zoom: 2 });
    const right = sliderToPan(square, zoomed, "x", 100);
    expect(right.panX).toBeCloseTo(0.5);
    expect(panToSlider(square, right, "x")).toBe(100);
    const up = sliderToPan(square, right, "y", -50);
    expect(up.panY).toBeCloseTo(-0.25);
    expect(panToSlider(square, up, "y")).toBe(-50);
  });

  it("does nothing on an axis that cannot move", () => {
    const moved = sliderToPan(square, t({}), "x", 100);
    expect(moved.panX).toBe(0);
    expect(panToSlider(square, moved, "x")).toBe(0);
  });
});

describe("gestures", () => {
  it("drags within the covering bounds", () => {
    const dragged = panBy(square, t({ zoom: 2 }), 0.3, 10);
    expect(dragged.panX).toBeCloseTo(0.3);
    expect(dragged.panY).toBeCloseTo(0.5);
  });

  it("keeps the centred point when zooming and re-clamps when zooming out", () => {
    const zoomed = zoomTo(square, t({ zoom: 2, panX: 0.2 }), 3);
    expect(zoomed.panX).toBeCloseTo(0.3);
    const out = zoomTo(square, zoomed, 1);
    expect(out.panX).toBe(0);
  });

  it("re-clamps the pan when a rotation shrinks the slack", () => {
    const panned = clampTransform(landscape, t({ panX: 1 }));
    expect(panned.panX).toBeCloseTo(0.25);
    const rotated = rotateTo(landscape, panned, 90);
    expectCovered(landscape, rotated);
    expect(rotated.panX).toBe(0);
    expectCovered(landscape, rotateTo(landscape, panned, 37));
  });
});

describe("avatarDrawRect", () => {
  it("centres a landscape photo at its cover size", () => {
    expect(avatarDrawRect(landscape, t({}), 512)).toEqual({
      centerX: 256,
      centerY: 256,
      radians: 0,
      width: 768,
      height: 512,
    });
  });

  it("includes rotation, zoom and pan", () => {
    const rect = avatarDrawRect(square, t({ zoom: 2, rotation: 90, panX: 0.25, panY: -0.5 }), 400);
    expect(rect.centerX).toBeCloseTo(300);
    expect(rect.centerY).toBeCloseTo(0);
    expect(rect.radians).toBeCloseTo(Math.PI / 2);
    expect(rect.width).toBeCloseTo(800);
    expect(rect.height).toBeCloseTo(800);
  });

  it("clamps before exporting so the output never shows empty canvas", () => {
    const rect = avatarDrawRect(portrait, t({ panX: 1, panY: 1 }), 512);
    expect(rect.centerX).toBe(256);
    expect(rect.centerY).toBeCloseTo(256 + 128);
  });
});
