/**
 * Pure rules for photos and videos in posts (ADR-157): what a compose may
 * hold (up to ten photos or one video, never both), the state machine of
 * one upload, the resize and crop arithmetic, the carousel's index helpers
 * and the `srcset` of a processed photo. No DOM here, so all of it is
 * unit-tested.
 */

export type MediaKind = "photo" | "video";

/** The limits compose reads from `GET /api/me/media/capabilities`. */
export type MediaLimits = {
  max_photos: number;
  max_videos: number;
  max_photo_bytes: number;
  max_video_bytes: number;
  max_video_seconds: number;
  photo_content_types: string[];
  video_content_types: string[];
  video: boolean;
};

/** Used until the capabilities load (the server's defaults). */
export const DEFAULT_MEDIA_LIMITS: MediaLimits = {
  max_photos: 10,
  max_videos: 1,
  max_photo_bytes: 25 * 1024 * 1024,
  max_video_bytes: 500 * 1024 * 1024,
  max_video_seconds: 120,
  photo_content_types: ["image/heic", "image/heif", "image/jpeg", "image/png", "image/webp"],
  video_content_types: ["video/mp4", "video/quicktime", "video/webm"],
  video: false,
};

const EXTENSION_TYPES: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heif",
  mp4: "video/mp4",
  m4v: "video/mp4",
  mov: "video/quicktime",
  webm: "video/webm",
};

/** The file's content type, from the browser or (when it has none, as for some HEIC) its extension. */
export function contentTypeOf(file: { type: string; name: string }): string {
  if (file.type) return file.type.toLowerCase();
  const extension = file.name.split(".").pop()?.toLowerCase() ?? "";
  return EXTENSION_TYPES[extension] ?? "";
}

/** Photo, video, or null when the server takes neither. */
export function mediaKindOf(file: { type: string; name: string }, limits: MediaLimits): MediaKind | null {
  const type = contentTypeOf(file);
  if (limits.photo_content_types.includes(type)) return "photo";
  if (limits.video && limits.video_content_types.includes(type)) return "video";
  return null;
}

export type CompositionRefusal = "mixed" | "tooManyPhotos" | "tooManyVideos" | "unsupported" | "videoUnavailable";

/**
 * Which of the newly picked files fit next to what compose already holds:
 * up to `max_photos` photos or `max_videos` videos, never mixed. Files past
 * the limit are refused (the first refusal reason is reported once).
 */
export function admitFiles<F extends { type: string; name: string }>(
  existing: MediaKind[],
  picked: F[],
  limits: MediaLimits,
): { accepted: Array<{ file: F; kind: MediaKind }>; refusal: CompositionRefusal | null } {
  const accepted: Array<{ file: F; kind: MediaKind }> = [];
  let refusal: CompositionRefusal | null = null;
  const kinds = [...existing];
  const refuse = (reason: CompositionRefusal) => {
    refusal ??= reason;
  };

  for (const file of picked) {
    const kind = mediaKindOf(file, limits);
    if (!kind) {
      refuse(contentTypeOf(file).startsWith("video/") && !limits.video ? "videoUnavailable" : "unsupported");
      continue;
    }
    const current = kinds[0];
    if (current && current !== kind) {
      refuse("mixed");
      continue;
    }
    const count = kinds.filter((value) => value === kind).length;
    const max = kind === "photo" ? limits.max_photos : limits.max_videos;
    if (count >= max) {
      refuse(kind === "photo" ? "tooManyPhotos" : "tooManyVideos");
      continue;
    }
    kinds.push(kind);
    accepted.push({ file, kind });
  }
  return { accepted, refusal };
}

/** Whether a list of media kinds is a valid post: ≤ max photos xor ≤ max videos. */
export function validComposition(kinds: MediaKind[], limits: MediaLimits): boolean {
  if (kinds.length === 0) return true;
  const photos = kinds.filter((kind) => kind === "photo").length;
  const videos = kinds.length - photos;
  if (photos > 0 && videos > 0) return false;
  return photos > 0 ? photos <= limits.max_photos : videos <= limits.max_videos;
}

// Upload state machine ---------------------------------------------------------

export type UploadPhase =
  | "preparing" // resizing a photo or reading a video's duration
  | "uploading" // PUT to storage, with progress
  | "completing" // POST /complete
  | "processing" // server is building renditions; compose may publish now
  | "ready"
  | "failed" // something went wrong on our side or the network; retry is offered
  | "rejected"; // the server refused the file; only remove is offered

export type UploadError =
  | "offline"
  | "network"
  | "quota"
  | "rateLimited"
  | "tooLarge"
  | "tooLong"
  | "unsupported"
  | "videoUnavailable"
  | "storage"
  | "processing"
  | "unknown";

export type UploadState = { phase: UploadPhase; progress: number; error: UploadError | null };

export type UploadEvent =
  | { type: "prepare" }
  | { type: "start" }
  | { type: "progress"; loaded: number; total: number }
  | { type: "uploaded" }
  | { type: "completed"; status: "pending" | "processing" | "ready" | "rejected" }
  | { type: "polled"; status: "pending" | "processing" | "ready" | "rejected" }
  | { type: "fail"; error: UploadError }
  | { type: "reject"; error: UploadError }
  | { type: "retry" };

export const INITIAL_UPLOAD: UploadState = { phase: "preparing", progress: 0, error: null };

const fromServer = (status: "pending" | "processing" | "ready" | "rejected", state: UploadState): UploadState => {
  if (status === "ready") return { phase: "ready", progress: 1, error: null };
  if (status === "rejected") return { phase: "rejected", progress: 1, error: "processing" };
  return { ...state, phase: "processing", progress: 1, error: null };
};

/** One upload's next state; events that do not apply in a phase leave it unchanged. */
export function uploadReducer(state: UploadState, event: UploadEvent): UploadState {
  switch (event.type) {
    case "prepare":
      return { phase: "preparing", progress: 0, error: null };
    case "start":
      return state.phase === "preparing" ? { phase: "uploading", progress: 0, error: null } : state;
    case "progress": {
      if (state.phase !== "uploading" || event.total <= 0) return state;
      const progress = Math.min(1, Math.max(state.progress, event.loaded / event.total));
      return { ...state, progress };
    }
    case "uploaded":
      return state.phase === "uploading" ? { phase: "completing", progress: 1, error: null } : state;
    case "completed":
      return state.phase === "completing" ? fromServer(event.status, state) : state;
    case "polled":
      return state.phase === "processing" ? fromServer(event.status, state) : state;
    case "fail":
      return state.phase === "ready" || state.phase === "rejected" ? state : { ...state, phase: "failed", error: event.error };
    case "reject":
      return { ...state, phase: "rejected", error: event.error };
    case "retry":
      return state.phase === "failed" ? { phase: "preparing", progress: 0, error: null } : state;
  }
}

/** The bytes have reached the server: the post may be published while it processes. */
export function isPublishable(state: UploadState) {
  return state.phase === "processing" || state.phase === "ready";
}

/** Still moving (no user action needed). */
export function isBusy(state: UploadState) {
  return state.phase === "preparing" || state.phase === "uploading" || state.phase === "completing";
}

/** The wait before poll number `attempt` (0-based): 1 s, growing ×1.5, at most 10 s. */
export function pollDelay(attempt: number): number {
  return Math.min(10_000, Math.round(1_000 * 1.5 ** Math.max(0, attempt)));
}

/** An API error code (or status) as an upload error compose can explain. */
export function uploadErrorOf(code: string | undefined, status: number | undefined): UploadError {
  switch (code) {
    case "media_quota_exceeded":
      return "quota";
    case "rate_limited":
      return "rateLimited";
    case "video_unavailable":
      return "videoUnavailable";
    case "media_too_large":
    case "invalid_media_size":
      return "tooLarge";
    case "video_too_long":
      return "tooLong";
    case "invalid_media_type":
    case "media_type_mismatch":
    case "media_unreadable":
      return "unsupported";
    case "media_storage_unavailable":
    case "media_upload_missing":
      return "storage";
  }
  if (status === 429) return "rateLimited";
  if (status === 413) return "tooLarge";
  if (status === 415) return "unsupported";
  if (status === 422) return "unsupported";
  if (status !== undefined && status >= 500) return "storage";
  return "unknown";
}

/** Errors that a retry will not fix (the file itself is the problem). */
export function isPermanent(error: UploadError) {
  return error === "tooLarge" || error === "tooLong" || error === "unsupported" || error === "videoUnavailable";
}

// Resize and crop ---------------------------------------------------------------

/** Upload size: photos are resized in the browser to this long side first. */
export const PHOTO_MAX_EDGE = 2560;

export type CropAspect = "original" | "4:5" | "1:1";
export const CROP_ASPECTS: CropAspect[] = ["original", "4:5", "1:1"];

/** Width and height scaled down (never up) so the long side is at most `maxEdge`. */
export function fitWithin(width: number, height: number, maxEdge = PHOTO_MAX_EDGE): { width: number; height: number } {
  if (width <= 0 || height <= 0) return { width: 0, height: 0 };
  const scale = Math.min(1, maxEdge / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/** The centred source rectangle of a crop to `aspect` (width / height). */
export function cropRect(width: number, height: number, aspect: CropAspect): { x: number; y: number; width: number; height: number } {
  if (aspect === "original" || width <= 0 || height <= 0) return { x: 0, y: 0, width, height };
  const ratio = aspect === "1:1" ? 1 : 4 / 5;
  if (width / height > ratio) {
    const cropped = Math.round(height * ratio);
    return { x: Math.round((width - cropped) / 2), y: 0, width: cropped, height };
  }
  const cropped = Math.round(width / ratio);
  return { x: 0, y: Math.round((height - cropped) / 2), width, height: cropped };
}

/** The source rectangle and output size of a photo after crop and resize. */
export function photoPlan(width: number, height: number, aspect: CropAspect, maxEdge = PHOTO_MAX_EDGE) {
  const source = cropRect(width, height, aspect);
  return { source, output: fitWithin(source.width, source.height, maxEdge) };
}

// Display ----------------------------------------------------------------------

/** The long side of each WebP rendition (ADR-157 §3). */
export const RENDITION_EDGES = { thumb: 320, feed: 1080, full: 2048 } as const;

/** The pixel width of a rendition of a `width`×`height` photo (renditions never upscale). */
export function renditionWidth(width: number, height: number, longEdge: number): number {
  return fitWithin(width, height, longEdge).width;
}

/**
 * The `srcset` of a processed photo from its thumb, feed and full renditions,
 * each with its real width; duplicates (a small photo) collapse to one.
 */
export function buildSrcSet(media: {
  width?: number | null;
  height?: number | null;
  thumb_url?: string | null;
  feed_url?: string | null;
  full_url?: string | null;
}): string {
  const width = media.width ?? 0;
  const height = media.height ?? 0;
  const entries: Array<[string, number]> = [];
  const add = (url: string | null | undefined, edge: number) => {
    if (!url) return;
    const w = width > 0 && height > 0 ? renditionWidth(width, height, edge) : edge;
    if (entries.some(([, existing]) => existing === w)) return;
    entries.push([url, w]);
  };
  add(media.thumb_url, RENDITION_EDGES.thumb);
  add(media.feed_url, RENDITION_EDGES.feed);
  add(media.full_url, RENDITION_EDGES.full);
  return entries.map(([url, w]) => `${url} ${w}w`).join(", ");
}

/** `sizes` for a photo in a feed card: the full card width up to the 28 rem column. */
export const FEED_IMAGE_SIZES = "(min-width: 640px) 448px, 100vw";

/**
 * The frame's aspect ratio (width / height) for a photo or a carousel's first
 * item, kept between 4:5 (tall) and 1.91:1 (wide) so no post takes the whole
 * screen; the photo is letterboxed inside over its blurred placeholder.
 */
export function frameAspect(width: number | null | undefined, height: number | null | undefined): number {
  if (!width || !height) return 1;
  return Math.min(1.91, Math.max(0.8, width / height));
}

// Carousel ---------------------------------------------------------------------

export function clampIndex(index: number, count: number): number {
  if (count <= 0) return 0;
  return Math.min(count - 1, Math.max(0, Math.round(index)));
}

/** The slide showing in a scroll-snap track (scrollLeft is negative in right-to-left layouts). */
export function indexFromScroll(scrollLeft: number, slideWidth: number, count: number): number {
  if (slideWidth <= 0) return 0;
  return clampIndex(Math.abs(scrollLeft) / slideWidth, count);
}

/** The slide after a step of `delta` (±1), stopping at the ends. */
export function stepIndex(index: number, delta: number, count: number): number {
  return clampIndex(index + delta, count);
}

/** The slide a key press moves to, or null when the key is not a carousel key. */
export function keyIndex(key: string, index: number, count: number, rtl = false): number | null {
  const forward = rtl ? "ArrowLeft" : "ArrowRight";
  const back = rtl ? "ArrowRight" : "ArrowLeft";
  if (key === forward) return stepIndex(index, 1, count);
  if (key === back) return stepIndex(index, -1, count);
  if (key === "Home") return 0;
  if (key === "End") return Math.max(0, count - 1);
  return null;
}

/** Moves one item of a list from one place to another (drag or the move buttons). */
export function moveItem<T>(items: T[], from: number, to: number): T[] {
  if (from === to || from < 0 || from >= items.length) return items;
  const target = clampIndex(to, items.length);
  const next = [...items];
  const [item] = next.splice(from, 1);
  next.splice(target, 0, item);
  return next;
}

/** «m:ss» for a video's length. */
export function formatDuration(ms: number | null | undefined): string {
  const total = Math.max(0, Math.round((ms ?? 0) / 1000));
  const minutes = Math.floor(total / 60);
  const seconds = String(total % 60).padStart(2, "0");
  return [String(minutes), seconds].join(":");
}
