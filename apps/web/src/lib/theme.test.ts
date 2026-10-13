import { describe, expect, it } from "vitest";

import { APP_THEMES } from "./theme";

function luminance(hex: string) {
  const [r, g, b] = [1, 3, 5].map((offset) => {
    const channel = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255;
    return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
}

function contrast(foreground: string, background: string) {
  const [light, dark] = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
  return (light! + 0.05) / (dark! + 0.05);
}

describe("theme palettes", () => {
  it.each(Object.values(APP_THEMES).map((theme) => [theme.slug, theme] as const))(
    "%s primary buttons meet WCAG AA text contrast",
    (_slug, theme) => {
      expect(contrast(theme.colors.primaryContrast, theme.colors.primary)).toBeGreaterThanOrEqual(4.5);
    },
  );
});
