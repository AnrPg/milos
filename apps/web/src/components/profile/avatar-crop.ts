export type AvatarCrop = {
  dx: number;
  dy: number;
  width: number;
  height: number;
};

export function calculateAvatarCrop(
  imageWidth: number,
  imageHeight: number,
  outputSize: number,
  zoom: number,
  horizontalPosition: number,
  verticalPosition: number,
): AvatarCrop {
  const coverScale = Math.max(outputSize / imageWidth, outputSize / imageHeight);
  const scale = coverScale * Math.max(1, zoom);
  const width = imageWidth * scale;
  const height = imageHeight * scale;
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
) {
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas is not available in this browser.");
  const crop = calculateAvatarCrop(
    image.width,
    image.height,
    canvas.width,
    zoom,
    horizontalPosition,
    verticalPosition,
  );

  context.clearRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#111713";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, crop.dx, crop.dy, crop.width, crop.height);
}

export function canvasToAvatarFile(canvas: HTMLCanvasElement) {
  return new Promise<File>((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error("The edited image could not be prepared."));
        return;
      }

      resolve(new File([blob], "avatar.jpg", { type: "image/jpeg" }));
    }, "image/jpeg", 0.9);
  });
}
