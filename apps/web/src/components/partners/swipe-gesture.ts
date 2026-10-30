import type { SwipeDirection } from "@/api/partners";

/**
 * The deck card's drag (ADR-280, mockup decision 3 C), pure so it is tested:
 * past the threshold a release decides, short of it the card springs back.
 * Right is «ναι» and left is «όχι» in every language (the physical gesture,
 * as the ✕/✓ buttons below it), so RTL does not flip it.
 */
export const SWIPE_THRESHOLD = 90;
/** How far the stamps take to show fully. */
export const STAMP_DISTANCE = 80;
/** Degrees of tilt per pixel dragged, capped. */
const TILT_PER_PX = 1 / 15;
const MAX_TILT = 18;
/** Where a decided card flies to, in px (off any phone screen). */
export const FLY_DISTANCE = 640;
export const FLY_MS = 240;

/** The release: like past the threshold to the right, pass to the left, else nothing. */
export function swipeDecision(dx: number, threshold = SWIPE_THRESHOLD): SwipeDirection | null {
  if (dx >= threshold) return "like";
  if (dx <= -threshold) return "pass";
  return null;
}

/** The tilt while dragging, in degrees; none when motion is reduced. */
export function dragTilt(dx: number, reducedMotion = false): number {
  if (reducedMotion) return 0;
  const tilt = dx * TILT_PER_PX;
  return Math.max(-MAX_TILT, Math.min(MAX_TILT, tilt));
}

/** The card's transform at a drag offset. */
export function dragTransform(dx: number, reducedMotion = false): string | undefined {
  if (dx === 0) return undefined;
  return `translateX(${Math.round(dx)}px) rotate(${dragTilt(dx, reducedMotion).toFixed(2)}deg)`;
}

/** Where the card goes once decided (button, key or release). */
export function flyTransform(direction: SwipeDirection, reducedMotion = false): string {
  const sign = direction === "like" ? 1 : -1;
  return `translateX(${sign * FLY_DISTANCE}px) rotate(${reducedMotion ? 0 : sign * MAX_TILT}deg)`;
}

/** The «ΝΑΙ» and «ΟΧΙ» stamps' opacity at a drag offset (0–1). */
export function stampOpacity(dx: number): { like: number; pass: number } {
  const clamp = (value: number) => Math.max(0, Math.min(1, value));
  return { like: clamp(dx / STAMP_DISTANCE), pass: clamp(-dx / STAMP_DISTANCE) };
}

/** The decision a key press makes on the deck: → like, ← pass. */
export function keyDecision(key: string): SwipeDirection | null {
  if (key === "ArrowRight") return "like";
  if (key === "ArrowLeft") return "pass";
  return null;
}
