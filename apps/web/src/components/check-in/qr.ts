import { create } from "qrcode";

/**
 * A QR code as one SVG path, drawn on the device (no QR service ever sees a
 * door code or a member code). Medium error correction survives a scuffed
 * print and a phone held at an angle; the 4-module quiet zone is part of the
 * view box so the code scans on any background.
 */
export function qrSvgPath(text: string, quietZone = 4) {
  const { modules } = create(text, { errorCorrectionLevel: "M" });
  const size = modules.size;
  let path = "";
  for (let row = 0; row < size; row += 1) {
    let run = 0;
    for (let col = 0; col <= size; col += 1) {
      const dark = col < size && modules.data[row * size + col] === 1;
      if (dark) {
        run += 1;
      } else if (run > 0) {
        path += `M${col - run + quietZone} ${row + quietZone}h${run}v1h-${run}z`;
        run = 0;
      }
    }
  }
  return { size: size + quietZone * 2, path };
}
