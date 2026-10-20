import { completePhoto, requestPhotoUpload, type MediaItem } from "@/api/public-profile";

// ADR-148: photos are re-encoded in the browser before upload, which drops
// EXIF and GPS; the server refuses any file that still carries metadata.
const MAX_EDGE = 2400;
const QUALITY = 0.86;

export class BoxPhotoUploadError extends Error {
  constructor(public readonly reason: "unsupported" | "storageRejected") {
    super(reason);
    this.name = "BoxPhotoUploadError";
  }
}

async function encode(canvas: HTMLCanvasElement, type: string) {
  return new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, type, QUALITY));
}

/** A WebP (or JPEG where WebP encoding is missing) at most 2400 px on its long edge. */
export async function reencodeImage(file: Blob): Promise<Blob> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    throw new BoxPhotoUploadError("unsupported");
  }
  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const webp = await encode(canvas, "image/webp");
  if (webp?.type === "image/webp") return webp;
  const jpeg = await encode(canvas, "image/jpeg");
  if (!jpeg) throw new BoxPhotoUploadError("unsupported");
  return jpeg;
}

/** Re-encode, reserve, PUT to storage, then let the API verify it. */
export async function uploadBoxPhoto(token: string, file: File, organizationSlug?: string | null): Promise<MediaItem> {
  const body = await reencodeImage(file);
  const upload = await requestPhotoUpload(token, body.type, body.size, organizationSlug);
  const response = await fetch(upload.upload_url, { method: "PUT", body, headers: upload.required_headers });
  if (!response.ok) throw new BoxPhotoUploadError("storageRejected");
  return completePhoto(token, upload.media_id, organizationSlug);
}
