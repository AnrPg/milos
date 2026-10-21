import { completePhoto, requestPhotoUpload, type MediaItem } from "@/api/public-profile";
import { fitWithin } from "@/lib/post-media";
import { putPresigned } from "@/lib/presigned-upload";

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
  const size = fitWithin(bitmap.width, bitmap.height, MAX_EDGE);
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
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
  try {
    await putPresigned(upload.upload_url, body, upload.required_headers);
  } catch {
    throw new BoxPhotoUploadError("storageRejected");
  }
  return completePhoto(token, upload.media_id, organizationSlug);
}
