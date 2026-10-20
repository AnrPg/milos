import { contentTypeOf, photoPlan, type CropAspect } from "@/lib/post-media";

/**
 * Browser-side preparation of a picked file before its upload (ADR-157):
 * photos are turned upright, cropped and resized to 2560 px on the long side
 * so uploads stay quick on mobile data; videos are only measured. The server
 * strips metadata and re-encodes either way.
 */
const QUALITY = 0.9;

export type PreparedPhoto = { blob: Blob; contentType: string; width: number; height: number };

function encode(canvas: HTMLCanvasElement, type: string) {
  return new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, type, QUALITY));
}

/**
 * The photo to upload. A file the browser cannot decode (HEIC on most
 * browsers) goes as picked, uncropped: the server reads it.
 */
export async function preparePhoto(file: File, aspect: CropAspect): Promise<PreparedPhoto & { cropped: boolean }> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    return { blob: file, contentType: contentTypeOf(file), width: 0, height: 0, cropped: false };
  }
  try {
    const { source, output } = photoPlan(bitmap.width, bitmap.height, aspect);
    const canvas = document.createElement("canvas");
    canvas.width = output.width;
    canvas.height = output.height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("canvas");
    context.imageSmoothingQuality = "high";
    context.drawImage(bitmap, source.x, source.y, source.width, source.height, 0, 0, output.width, output.height);
    const blob = await encode(canvas, "image/jpeg");
    if (!blob) throw new Error("encode");
    // Release the canvas memory right away (large photos on phones).
    canvas.width = 0;
    canvas.height = 0;
    return { blob, contentType: "image/jpeg", width: output.width, height: output.height, cropped: aspect !== "original" };
  } catch {
    return { blob: file, contentType: contentTypeOf(file), width: 0, height: 0, cropped: false };
  } finally {
    bitmap.close();
  }
}

/** A video's length in ms, or null when the browser cannot read it (the server checks then). */
export function readVideoDuration(file: Blob, timeoutMs = 8_000): Promise<number | null> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement("video");
    let settled = false;
    const finish = (value: number | null) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      video.removeAttribute("src");
      video.load();
      URL.revokeObjectURL(url);
      resolve(value);
    };
    const timer = window.setTimeout(() => finish(null), timeoutMs);
    video.preload = "metadata";
    video.muted = true;
    video.onloadedmetadata = () => finish(Number.isFinite(video.duration) ? Math.round(video.duration * 1000) : null);
    video.onerror = () => finish(null);
    video.src = url;
  });
}
