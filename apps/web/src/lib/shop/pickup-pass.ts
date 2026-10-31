import { qrSvgPath } from "@/components/check-in/qr";

/*
 * «Αποθήκευση» (ADR-291, mockup 2B): the order's QR and pickup code as one
 * image the person keeps in their photos, so they can show it at the desk
 * without the app or a connection. Drawn on the device: no service sees the
 * code. Colours come from the theme, read at the moment of saving.
 */

export type PickupPass = {
  code: string;
  /** «K-1042» */
  reference: string;
  box: string | null;
  place: string | null;
  total: string;
  /** Translated labels. */
  labels: { code: string; showAtDesk: string };
};

export type PassColors = { paper: string; ink: string; soft: string };

/** «K7MQ4X» → «K7M Q4X»: easier to read aloud at the desk. */
export function spacedCode(code: string): string {
  return code.length === 6 ? `${code.slice(0, 3)} ${code.slice(3)}` : code;
}

/** The text lines under the QR, top to bottom (none empty). */
export function passLines(pass: PickupPass): string[] {
  return [pass.reference, [pass.box, pass.place].filter(Boolean).join(" · "), pass.total, pass.labels.showAtDesk].filter(
    (line) => line.trim() !== "",
  );
}

export function passFileName(pass: PickupPass): string {
  return `palee-${pass.reference.toLowerCase().replace(/[^a-z0-9-]+/g, "")}-${pass.code.toLowerCase()}.png`;
}

/** The theme's paper, ink and soft text, so the image matches the app. */
export function themeColors(element: Element = document.documentElement): PassColors {
  const style = getComputedStyle(element);
  const read = (name: string) => style.getPropertyValue(name).trim();
  return { paper: read("--paper"), ink: read("--on-paper"), soft: read("--text-soft") || read("--on-paper") };
}

const WIDTH = 720;
const QR_SIZE = 480;

/** Draws the pass on `canvas` and returns it. */
export function drawPickupPass(canvas: HTMLCanvasElement, pass: PickupPass, colors: PassColors): HTMLCanvasElement {
  const lines = passLines(pass);
  const height = 120 + QR_SIZE + 180 + lines.length * 44;
  canvas.width = WIDTH;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) return canvas;

  context.fillStyle = colors.paper;
  context.fillRect(0, 0, WIDTH, height);

  const { size, path } = qrSvgPath(pass.code);
  const scale = QR_SIZE / size;
  context.save();
  context.translate((WIDTH - QR_SIZE) / 2, 60);
  context.scale(scale, scale);
  context.fillStyle = colors.ink;
  context.fill(new Path2D(path));
  context.restore();

  context.textAlign = "center";
  context.fillStyle = colors.soft;
  context.font = "600 26px system-ui, sans-serif";
  let y = 60 + QR_SIZE + 60;
  context.fillText(pass.labels.code, WIDTH / 2, y);
  y += 72;
  context.fillStyle = colors.ink;
  context.font = "800 64px ui-monospace, Menlo, monospace";
  context.fillText(spacedCode(pass.code), WIDTH / 2, y);
  y += 64;
  context.font = "500 28px system-ui, sans-serif";
  for (const line of lines) {
    context.fillStyle = line === pass.labels.showAtDesk ? colors.soft : colors.ink;
    context.fillText(line, WIDTH / 2, y);
    y += 44;
  }
  return canvas;
}

/** Saves the pass as a PNG through the browser's download. */
export async function downloadPickupPass(pass: PickupPass): Promise<void> {
  const canvas = drawPickupPass(document.createElement("canvas"), pass, themeColors());
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
  if (!blob) throw new Error("pickup_pass_failed");
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = passFileName(pass);
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
