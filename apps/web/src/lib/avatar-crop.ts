/**
 * Pure maths of the avatar editor: zoom, pan and free rotation of a photo
 * behind a square (or circular) crop window, with the window always fully
 * covered by the photo.
 *
 * Units: the crop window is 1 × 1, centred on the origin, with x to the right
 * and y downwards (canvas axes). `pan` is where the photo's centre sits
 * relative to the window's centre, in window units. `scale` turns image
 * pixels into window units.
 */

export type AvatarTransform = {
  /** Zoom on top of the smallest covering scale; 1 = just covers. */
  zoom: number;
  /** Clockwise rotation in degrees, 0–360 (360 is kept as a full turn). */
  rotation: number;
  panX: number;
  panY: number;
};

export type ImageSize = { width: number; height: number };

export const AVATAR_MIN_ZOOM = 1;
export const AVATAR_MAX_ZOOM = 4;
/** Below this (in window units) an axis counts as unable to move. */
const MOVABLE_EPSILON = 1e-4;

export const IDENTITY_TRANSFORM: AvatarTransform = { zoom: 1, rotation: 0, panX: 0, panY: 0 };

export function normalizeRotation(degrees: number) {
  if (!Number.isFinite(degrees)) return 0;
  const value = ((degrees % 360) + 360) % 360;
  // Snap float noise so 89.9999999 still counts as a right angle.
  return Math.abs(value - Math.round(value)) < 1e-9 ? Math.round(value) % 360 : value;
}

export function clampZoom(zoom: number) {
  if (!Number.isFinite(zoom)) return AVATAR_MIN_ZOOM;
  return Math.min(AVATAR_MAX_ZOOM, Math.max(AVATAR_MIN_ZOOM, zoom));
}

function trig(rotation: number) {
  const radians = (normalizeRotation(rotation) * Math.PI) / 180;
  // Round away float noise so 90° gives an exact 0 cosine.
  const round = (value: number) => (Math.abs(value) < 1e-12 ? 0 : value);
  return { cos: round(Math.cos(radians)), sin: round(Math.sin(radians)) };
}

/**
 * Half the extent of the (rotated) crop window along the image's own axes:
 * the window's corners reach ±reach on both image axes.
 */
function windowReach(rotation: number) {
  const { cos, sin } = trig(rotation);
  return (Math.abs(cos) + Math.abs(sin)) / 2;
}

/** The smallest scale at which the rotated image still covers the window. */
export function coverScale(image: ImageSize, rotation: number) {
  return (2 * windowReach(rotation)) / Math.min(image.width, image.height);
}

export function avatarScale(image: ImageSize, transform: Pick<AvatarTransform, "zoom" | "rotation">) {
  return coverScale(image, transform.rotation) * clampZoom(transform.zoom);
}

/**
 * How far the photo's centre may move from the window's centre along the
 * image's own (rotated) axes before the window would show empty space.
 */
function slack(image: ImageSize, transform: Pick<AvatarTransform, "zoom" | "rotation">) {
  const scale = avatarScale(image, transform);
  const reach = windowReach(transform.rotation);
  return {
    u: Math.max(0, (image.width * scale) / 2 - reach),
    v: Math.max(0, (image.height * scale) / 2 - reach),
  };
}

/**
 * The largest pan on each screen axis at this zoom and rotation. An axis
 * whose range is 0 cannot move: the photo already fits it exactly.
 */
export function panRange(image: ImageSize, transform: Pick<AvatarTransform, "zoom" | "rotation">) {
  const { u, v } = slack(image, transform);
  const { cos, sin } = trig(transform.rotation);
  return {
    x: u * Math.abs(cos) + v * Math.abs(sin),
    y: u * Math.abs(sin) + v * Math.abs(cos),
  };
}

export function axisMovability(image: ImageSize, transform: Pick<AvatarTransform, "zoom" | "rotation">) {
  const range = panRange(image, transform);
  return { x: range.x > MOVABLE_EPSILON, y: range.y > MOVABLE_EPSILON };
}

/**
 * Returns the transform with zoom and rotation normalised and the pan moved
 * to the nearest position where the window is fully covered by the photo.
 */
export function clampTransform(image: ImageSize, transform: AvatarTransform): AvatarTransform {
  const zoom = clampZoom(transform.zoom);
  // A full turn stays 360 so a slider dragged to its end does not jump to 0.
  const rotation = transform.rotation === 360 ? 360 : normalizeRotation(transform.rotation);
  const { u, v } = slack(image, { zoom, rotation });
  const { cos, sin } = trig(rotation);
  const panX = Number.isFinite(transform.panX) ? transform.panX : 0;
  const panY = Number.isFinite(transform.panY) ? transform.panY : 0;
  // Into the image's frame (rotate by -θ), clamp there, then back. The
  // feasible area is a rectangle in that frame, so this is the nearest point.
  const localU = Math.min(u, Math.max(-u, panX * cos + panY * sin));
  const localV = Math.min(v, Math.max(-v, -panX * sin + panY * cos));
  const clean = (value: number) => (Math.abs(value) < 1e-12 ? 0 : value);
  return {
    zoom,
    rotation,
    panX: clean(localU * cos - localV * sin),
    panY: clean(localU * sin + localV * cos),
  };
}

/** Slider position (-100…100) of the pan on one axis; 0 when it cannot move. */
export function panToSlider(image: ImageSize, transform: AvatarTransform, axis: "x" | "y") {
  const range = panRange(image, transform)[axis];
  if (range <= MOVABLE_EPSILON) return 0;
  const pan = axis === "x" ? transform.panX : transform.panY;
  return Math.max(-100, Math.min(100, Math.round((pan / range) * 100)));
}

/** Applies a slider position (-100…100) to one axis and re-clamps. */
export function sliderToPan(image: ImageSize, transform: AvatarTransform, axis: "x" | "y", value: number) {
  const range = panRange(image, transform)[axis];
  const pan = (Math.max(-100, Math.min(100, value)) / 100) * range;
  return clampTransform(image, axis === "x" ? { ...transform, panX: pan } : { ...transform, panY: pan });
}

/** Moves the photo by a drag delta given in window units. */
export function panBy(image: ImageSize, transform: AvatarTransform, dx: number, dy: number) {
  return clampTransform(image, { ...transform, panX: transform.panX + dx, panY: transform.panY + dy });
}

/**
 * Zooms by a factor while keeping the photo point under the window's centre
 * in place (the pan scales with the zoom), then re-clamps.
 */
export function zoomTo(image: ImageSize, transform: AvatarTransform, zoom: number) {
  const next = clampZoom(zoom);
  const ratio = next / clampZoom(transform.zoom);
  return clampTransform(image, { ...transform, zoom: next, panX: transform.panX * ratio, panY: transform.panY * ratio });
}

export function rotateTo(image: ImageSize, transform: AvatarTransform, rotation: number) {
  return clampTransform(image, { ...transform, rotation });
}

/**
 * Where to draw the photo on a square output canvas of `outputSize` pixels:
 * translate to (centerX, centerY), rotate by `radians`, then draw the image
 * centred at the origin with `width` × `height`.
 */
export function avatarDrawRect(image: ImageSize, transform: AvatarTransform, outputSize: number) {
  const clamped = clampTransform(image, transform);
  const scale = avatarScale(image, clamped) * outputSize;
  return {
    centerX: outputSize / 2 + clamped.panX * outputSize,
    centerY: outputSize / 2 + clamped.panY * outputSize,
    radians: (clamped.rotation * Math.PI) / 180,
    width: image.width * scale,
    height: image.height * scale,
  };
}

/**
 * The window's four corners in image pixels (useful to check coverage, or to
 * crop the source on the server). Order: top-left, top-right, bottom-right,
 * bottom-left of the window.
 */
export function cropCornersInImage(image: ImageSize, transform: AvatarTransform) {
  const clamped = clampTransform(image, transform);
  const scale = avatarScale(image, clamped);
  const { cos, sin } = trig(clamped.rotation);
  return [
    [-0.5, -0.5],
    [0.5, -0.5],
    [0.5, 0.5],
    [-0.5, 0.5],
  ].map(([x, y]) => {
    const dx = x - clamped.panX;
    const dy = y - clamped.panY;
    return {
      x: image.width / 2 + (dx * cos + dy * sin) / scale,
      y: image.height / 2 + (-dx * sin + dy * cos) / scale,
    };
  });
}
