import { describe, expect, it } from "vitest";

import {
  DEFAULT_MEDIA_LIMITS,
  INITIAL_UPLOAD,
  admitFiles,
  buildSrcSet,
  clampIndex,
  contentTypeOf,
  cropRect,
  fitWithin,
  formatDuration,
  frameAspect,
  indexFromScroll,
  isPublishable,
  keyIndex,
  moveItem,
  photoPlan,
  pollDelay,
  renditionWidth,
  stepIndex,
  uploadErrorOf,
  uploadReducer,
  validComposition,
  type MediaLimits,
  type UploadEvent,
  type UploadState,
} from "@/lib/post-media";

const limits: MediaLimits = { ...DEFAULT_MEDIA_LIMITS, video: true };
const photo = (name = "a.jpg") => ({ name, type: "image/jpeg" });
const video = (name = "clip.mp4") => ({ name, type: "video/mp4" });

describe("composition: up to ten photos or one video, never both", () => {
  it("accepts up to ten photos and refuses the eleventh", () => {
    const picked = Array.from({ length: 11 }, (_, index) => photo(`p${index}.jpg`));
    const { accepted, refusal } = admitFiles([], picked, limits);
    expect(accepted).toHaveLength(10);
    expect(refusal).toBe("tooManyPhotos");
  });

  it("counts what compose already holds", () => {
    const { accepted, refusal } = admitFiles(Array(8).fill("photo"), [photo(), photo(), photo()], limits);
    expect(accepted).toHaveLength(2);
    expect(refusal).toBe("tooManyPhotos");
  });

  it("takes one video and refuses a second", () => {
    const { accepted, refusal } = admitFiles([], [video(), video("b.mov")], limits);
    expect(accepted.map((entry) => entry.kind)).toEqual(["video"]);
    expect(refusal).toBe("tooManyVideos");
  });

  it("never mixes photos and a video", () => {
    expect(admitFiles(["photo"], [video()], limits).refusal).toBe("mixed");
    expect(admitFiles(["video"], [photo()], limits).refusal).toBe("mixed");
    const first = admitFiles([], [photo(), video()], limits);
    expect(first.accepted.map((entry) => entry.kind)).toEqual(["photo"]);
    expect(first.refusal).toBe("mixed");
  });

  it("refuses videos where the server has no video support, and unknown files", () => {
    const noVideo = { ...limits, video: false };
    expect(admitFiles([], [video()], noVideo)).toEqual({ accepted: [], refusal: "videoUnavailable" });
    expect(admitFiles([], [{ name: "notes.pdf", type: "application/pdf" }], limits).refusal).toBe("unsupported");
  });

  it("reads HEIC by extension when the browser gives no type", () => {
    expect(contentTypeOf({ name: "IMG_0001.HEIC", type: "" })).toBe("image/heic");
    expect(admitFiles([], [{ name: "IMG_0001.HEIC", type: "" }], limits).accepted).toHaveLength(1);
  });

  it("validates a whole list", () => {
    expect(validComposition([], limits)).toBe(true);
    expect(validComposition(Array(10).fill("photo"), limits)).toBe(true);
    expect(validComposition(Array(11).fill("photo"), limits)).toBe(false);
    expect(validComposition(["video"], limits)).toBe(true);
    expect(validComposition(["video", "video"], limits)).toBe(false);
    expect(validComposition(["photo", "video"], limits)).toBe(false);
  });
});

describe("upload state machine", () => {
  const run = (events: UploadEvent[], from: UploadState = INITIAL_UPLOAD) => events.reduce(uploadReducer, from);

  it("goes preparing → uploading → completing → processing → ready", () => {
    const uploading = run([{ type: "start" }, { type: "progress", loaded: 50, total: 100 }]);
    expect(uploading).toEqual({ phase: "uploading", progress: 0.5, error: null });
    const processing = run([{ type: "uploaded" }, { type: "completed", status: "processing" }], uploading);
    expect(processing.phase).toBe("processing");
    expect(isPublishable(processing)).toBe(true);
    expect(run([{ type: "polled", status: "ready" }], processing)).toEqual({ phase: "ready", progress: 1, error: null });
  });

  it("never moves progress backwards and ignores progress outside uploading", () => {
    const state = run([{ type: "start" }, { type: "progress", loaded: 80, total: 100 }, { type: "progress", loaded: 20, total: 100 }]);
    expect(state.progress).toBe(0.8);
    expect(uploadReducer(INITIAL_UPLOAD, { type: "progress", loaded: 1, total: 2 })).toBe(INITIAL_UPLOAD);
  });

  it("is not publishable before the bytes are complete", () => {
    expect(isPublishable(run([{ type: "start" }]))).toBe(false);
    expect(isPublishable(run([{ type: "start" }, { type: "uploaded" }]))).toBe(false);
  });

  it("fails, retries from the start, and ends rejected when the server refuses", () => {
    const failed = run([{ type: "start" }, { type: "fail", error: "network" }]);
    expect(failed).toMatchObject({ phase: "failed", error: "network" });
    expect(uploadReducer(failed, { type: "retry" })).toEqual(INITIAL_UPLOAD);
    const rejected = run([{ type: "start" }, { type: "uploaded" }, { type: "completed", status: "processing" }, { type: "polled", status: "rejected" }]);
    expect(rejected).toMatchObject({ phase: "rejected", error: "processing" });
    expect(uploadReducer(rejected, { type: "retry" })).toBe(rejected);
    expect(uploadReducer(rejected, { type: "fail", error: "network" })).toBe(rejected);
  });

  it("explains API errors", () => {
    expect(uploadErrorOf("media_quota_exceeded", 422)).toBe("quota");
    expect(uploadErrorOf("rate_limited", 429)).toBe("rateLimited");
    expect(uploadErrorOf(undefined, 429)).toBe("rateLimited");
    expect(uploadErrorOf("video_unavailable", 503)).toBe("videoUnavailable");
    expect(uploadErrorOf("media_too_large", 422)).toBe("tooLarge");
    expect(uploadErrorOf("invalid_media_type", 422)).toBe("unsupported");
    expect(uploadErrorOf(undefined, 500)).toBe("storage");
  });

  it("polls with a growing delay capped at ten seconds", () => {
    expect([0, 1, 2].map(pollDelay)).toEqual([1000, 1500, 2250]);
    expect(pollDelay(30)).toBe(10_000);
  });
});

describe("resize and crop math", () => {
  it("fits the long side within 2560 px and never upscales", () => {
    expect(fitWithin(4032, 3024)).toEqual({ width: 2560, height: 1920 });
    expect(fitWithin(3024, 4032)).toEqual({ width: 1920, height: 2560 });
    expect(fitWithin(800, 600)).toEqual({ width: 800, height: 600 });
    expect(fitWithin(0, 600)).toEqual({ width: 0, height: 0 });
  });

  it("crops centred to 1:1 and 4:5, or keeps the original", () => {
    expect(cropRect(4000, 3000, "1:1")).toEqual({ x: 500, y: 0, width: 3000, height: 3000 });
    expect(cropRect(3000, 4500, "4:5")).toEqual({ x: 0, y: 375, width: 3000, height: 3750 });
    expect(cropRect(4000, 3000, "4:5")).toEqual({ x: 800, y: 0, width: 2400, height: 3000 });
    expect(cropRect(1200, 900, "original")).toEqual({ x: 0, y: 0, width: 1200, height: 900 });
  });

  it("plans crop then resize", () => {
    expect(photoPlan(4000, 3000, "1:1").output).toEqual({ width: 2560, height: 2560 });
    expect(photoPlan(4000, 3000, "4:5").output).toEqual({ width: 2048, height: 2560 });
  });
});

describe("srcset", () => {
  const urls = { thumb_url: "/t.webp", feed_url: "/f.webp", full_url: "/x.webp" };

  it("lists each rendition with its real width", () => {
    expect(buildSrcSet({ width: 4000, height: 3000, ...urls })).toBe("/t.webp 320w, /f.webp 1080w, /x.webp 2048w");
    expect(buildSrcSet({ width: 3000, height: 4000, ...urls })).toBe("/t.webp 240w, /f.webp 810w, /x.webp 1536w");
  });

  it("collapses renditions of a small photo and skips missing ones", () => {
    expect(buildSrcSet({ width: 900, height: 600, ...urls })).toBe("/t.webp 320w, /f.webp 900w");
    expect(buildSrcSet({ width: 4000, height: 3000, feed_url: "/f.webp" })).toBe("/f.webp 1080w");
    expect(renditionWidth(1000, 2000, 320)).toBe(160);
  });

  it("keeps the frame between 4:5 and 1.91:1", () => {
    expect(frameAspect(1000, 2000)).toBe(0.8);
    expect(frameAspect(4000, 1000)).toBe(1.91);
    expect(frameAspect(1200, 1000)).toBe(1.2);
    expect(frameAspect(null, 100)).toBe(1);
  });
});

describe("carousel index helpers", () => {
  it("clamps and steps", () => {
    expect(clampIndex(-1, 3)).toBe(0);
    expect(clampIndex(7, 3)).toBe(2);
    expect(clampIndex(1, 0)).toBe(0);
    expect(stepIndex(2, 1, 3)).toBe(2);
    expect(stepIndex(1, -1, 3)).toBe(0);
  });

  it("reads the slide from the scroll position, also right to left", () => {
    expect(indexFromScroll(0, 400, 3)).toBe(0);
    expect(indexFromScroll(390, 400, 3)).toBe(1);
    expect(indexFromScroll(-800, 400, 3)).toBe(2);
    expect(indexFromScroll(5000, 400, 3)).toBe(2);
    expect(indexFromScroll(100, 0, 3)).toBe(0);
  });

  it("maps keys, mirrored for right-to-left", () => {
    expect(keyIndex("ArrowRight", 0, 3)).toBe(1);
    expect(keyIndex("ArrowLeft", 0, 3)).toBe(0);
    expect(keyIndex("ArrowLeft", 0, 3, true)).toBe(1);
    expect(keyIndex("End", 0, 3)).toBe(2);
    expect(keyIndex("Home", 2, 3)).toBe(0);
    expect(keyIndex("Enter", 1, 3)).toBeNull();
  });

  it("moves an item in a list", () => {
    expect(moveItem(["a", "b", "c"], 0, 2)).toEqual(["b", "c", "a"]);
    expect(moveItem(["a", "b", "c"], 2, 1)).toEqual(["a", "c", "b"]);
    expect(moveItem(["a", "b"], 0, 9)).toEqual(["b", "a"]);
  });

  it("formats a video's length", () => {
    expect(formatDuration(83_400)).toBe("1:23");
    expect(formatDuration(null)).toBe("0:00");
  });
});
