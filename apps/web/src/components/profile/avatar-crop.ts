export type AvatarCrop = {
  dx: number;
  dy: number;
  width: number;
  height: number;
};

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

export function calculateAvatarCrop(
  imageWidth: number,
  imageHeight: number,
  outputSize: number,
  zoom: number,
  horizontalPosition: number,
  verticalPosition: number,
  rotationDegrees = 0,
): AvatarCrop {
  const normalizedRotation = ((rotationDegrees % 360) + 360) % 360;
  const rotated = normalizedRotation === 90 || normalizedRotation === 270;
  const effectiveWidth = rotated ? imageHeight : imageWidth;
  const effectiveHeight = rotated ? imageWidth : imageHeight;
  const coverScale = Math.max(outputSize / effectiveWidth, outputSize / effectiveHeight);
  const scale = coverScale * Math.max(1, zoom);
  const width = effectiveWidth * scale;
  const height = effectiveHeight * scale;
  const overflowX = Math.max(0, width - outputSize);
  const overflowY = Math.max(0, height - outputSize);
  const clampedX = Math.max(-100, Math.min(100, horizontalPosition));
  const clampedY = Math.max(-100, Math.min(100, verticalPosition));

  return {
    dx: (outputSize - width) / 2 + (clampedX / 100) * (overflowX / 2),
    dy: (outputSize - height) / 2 + (clampedY / 100) * (overflowY / 2),
    width,
    height,
  };
}

export function drawAvatarCrop(
  canvas: HTMLCanvasElement,
  image: CanvasImageSource & { width: number; height: number },
  zoom: number,
  horizontalPosition: number,
  verticalPosition: number,
  rotationDegrees = 0,
) {
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas is not available in this browser.");
  const normalizedRotation = ((rotationDegrees % 360) + 360) % 360;
  const rotated = normalizedRotation === 90 || normalizedRotation === 270;
  const effectiveWidth = rotated ? image.height : image.width;
  const crop = calculateAvatarCrop(
    image.width,
    image.height,
    canvas.width,
    zoom,
    horizontalPosition,
    verticalPosition,
    normalizedRotation,
  );
  const scale = crop.width / effectiveWidth;
  const scaledImageWidth = image.width * scale;
  const scaledImageHeight = image.height * scale;
  const radians = (normalizedRotation * Math.PI) / 180;

  context.clearRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#111713";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.save();
  context.translate(crop.dx + crop.width / 2, crop.dy + crop.height / 2);
  context.rotate(radians);
  context.drawImage(
    image,
    -scaledImageWidth / 2,
    -scaledImageHeight / 2,
    scaledImageWidth,
    scaledImageHeight,
  );
  context.restore();
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
