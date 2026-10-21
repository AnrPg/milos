"use client";

import type { QRCodeToStringOptions } from "qrcode";
import { useEffect, useState } from "react";
import { APP_THEMES, DEFAULT_THEME_SLUG } from "@/lib/theme";

// Medium error correction: readable from a cracked screen, still a small code.
const QR_OPTIONS: QRCodeToStringOptions = {
  type: "svg",
  errorCorrectionLevel: "medium",
  margin: 1,
  color: { dark: APP_THEMES[DEFAULT_THEME_SLUG].tokens.onPaper, light: APP_THEMES[DEFAULT_THEME_SLUG].tokens.paper },
};

/**
 * A QR code drawn as SVG on the device (the link never leaves it). Dark on
 * white whatever the theme, so every camera reads it.
 */
export function QrCode({ value, size, label }: { value: string; size: number; label: string }) {
  const [svg, setSvg] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void import("qrcode")
      .then((qrcode) => qrcode.toString(value, QR_OPTIONS))
      .then((markup) => {
        if (!cancelled) setSvg(markup);
      })
      .catch(() => {
        if (!cancelled) setSvg(null);
      });
    return () => {
      cancelled = true;
    };
  }, [value]);

  const src = svg ? `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}` : null;
  return src ? (
    // eslint-disable-next-line @next/next/no-img-element -- generated on the device
    <img src={src} alt={label} width={size} height={size} data-testid="referral-qr" />
  ) : (
    <span aria-hidden="true" className="block" style={{ width: size, height: size }} />
  );
}
