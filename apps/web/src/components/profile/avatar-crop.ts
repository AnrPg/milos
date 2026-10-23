import { avatarDrawRect, type AvatarTransform, type ImageSize } from "@/lib/avatar-crop";
import { readToken } from "@/lib/theme";

export const MAX_AVATAR_BYTES = 5 * 1_024 * 1_024;
const SUPPORTED_AVATAR_SOURCE_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/bmp",
  "image/avif",
]);
const SUPPORTED_AVATAR_SOURCE_EXTENSIONS = new Set([
  "jpg",
  "jpeg",
  "png",
  "webp",
  "gif",
  "bmp",
  "avif",
]);

export function isSupportedAvatarSource(file: Pick<File, "name" | "type">) {
  if (SUPPORTED_AVATAR_SOURCE_TYPES.has(file.type.toLowerCase())) return true;

  const extension = file.name.split(".").pop()?.toLowerCase();
  return extension ? SUPPORTED_AVATAR_SOURCE_EXTENSIONS.has(extension) : false;
}

export type AvatarImage = CanvasImageSource & ImageSize;

/** Draws the edited photo onto a square canvas, rotation included. */
export function drawAvatar(canvas: HTMLCanvasElement, image: AvatarImage, transform: AvatarTransform) {
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas is not available in this browser.");
  const rect = avatarDrawRect(image, transform, canvas.width);

  context.setTransform(1, 0, 0, 1, 0, 0);
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = readToken("deep");
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.imageSmoothingQuality = "high";
  context.translate(rect.centerX, rect.centerY);
  context.rotate(rect.radians);
  context.drawImage(image, -rect.width / 2, -rect.height / 2, rect.width, rect.height);
  context.setTransform(1, 0, 0, 1, 0, 0);
}

async function decode(blob: Blob): Promise<AvatarImage> {
  if (typeof createImageBitmap === "function") {
    try {
      // Applies the EXIF orientation, so phone photos load upright.
      return await createImageBitmap(blob, { imageOrientation: "from-image" });
    } catch {
      // Some browsers cannot decode every format into a bitmap; an <img> can.
    }
  }
  const url = URL.createObjectURL(blob);
  try {
    const image = new Image();
    image.decoding = "async";
    image.src = url;
    await image.decode();
    return image;
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * Loads a picked file, or the current avatar by URL, into something a canvas
 * can draw and export. Avatars live on the public media host (another
 * origin, CORS open for reads), so the URL is fetched as a blob: the canvas
 * then stays untainted and `toBlob` works. Credentials go only to our own
 * origin; the public bucket needs none and rejects them with a wildcard CORS.
 */
export async function loadAvatarImage(source: Blob | string, signal?: AbortSignal): Promise<AvatarImage> {
  if (typeof source !== "string") return decode(source);
  let blob: Blob;
  try {
    // `reload` skips a copy the page's <img> cached without CORS headers.
    const response = await fetch(source, { mode: "cors", credentials: "same-origin", cache: "reload", signal });
    if (!response.ok) throw new Error(`avatar_fetch_failed_${response.status}`);
    blob = await response.blob();
  } catch (error) {
    if (signal?.aborted) throw error;
    // A media host missing from connect-src can still load as a CORS image.
    return loadCorsImage(source);
  }
  return decode(blob);
}

async function loadCorsImage(url: string): Promise<AvatarImage> {
  const image = new Image();
  image.crossOrigin = "anonymous";
  image.decoding = "async";
  image.src = url;
  await image.decode();
  return image;
}

function canvasToBlob(canvas: HTMLCanvasElement, quality: number) {
  return new Promise<File>((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error("The edited image could not be prepared."));
        return;
      }

      resolve(new File([blob], "avatar.jpg", { type: "image/jpeg" }));
    }, "image/jpeg", quality);
  });
}

export async function canvasToAvatarFile(canvas: HTMLCanvasElement, maxBytes = MAX_AVATAR_BYTES) {
  for (const quality of [0.9, 0.82, 0.74, 0.66, 0.58, 0.5]) {
    const file = await canvasToBlob(canvas, quality);
    if (file.size <= maxBytes) return file;
  }

  return canvasToBlob(canvas, 0.42);
}
