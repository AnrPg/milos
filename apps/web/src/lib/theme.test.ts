import { describe, expect, it } from "vitest";

import { APP_THEMES, cssVariablesForTheme, rgbChannels, themeStylesheet, tokenVariable, workoutTypeColor, type ThemeTokens } from "./theme";

function luminance(hex: string) {
  const [r, g, b] = rgbChannels(hex).map((value) => {
    const channel = value / 255;
    return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
}

function contrast(foreground: string, background: string) {
  const [light, dark] = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
  return (light! + 0.05) / (dark! + 0.05);
}

const themes = Object.values(APP_THEMES).map((theme) => [theme.slug, theme] as const);

// Text on its surface: WCAG AA (4.5:1).
const TEXT_PAIRS: [keyof ThemeTokens, keyof ThemeTokens][] = [
  ["text", "bg"],
  ["text", "panel"],
  ["textSoft", "panel"],
  ["muted", "bg"],
  ["muted", "panel"],
  ["primaryContrast", "primary"],
  ["sparkContrast", "spark"],
  ["heatContrast", "heat"],
  ["deepContrast", "deep"],
  ["successContrast", "success"],
  ["warningContrast", "warning"],
  ["dangerContrast", "danger"],
  ["infoContrast", "info"],
  ["selectionText", "selection"],
  ["highlightText", "highlight"],
  ["onPaper", "paper"],
  ["onSeries", "series1"],
];

// Large text, icons and status colours on the page: 3:1.
const GRAPHIC_PAIRS: [keyof ThemeTokens, keyof ThemeTokens][] = [
  ["dim", "bg"],
  ["primary", "bg"],
  ["danger", "bg"],
  ["success", "bg"],
  ["warning", "bg"],
  ["info", "bg"],
  ["heat", "bg"],
  ["focusRing", "bg"],
  ["mapLabel", "mapLand"],
];

describe("theme palettes", () => {
  it.each(themes)("%s text meets WCAG AA contrast", (_slug, theme) => {
    for (const [foreground, background] of TEXT_PAIRS) {
      expect(contrast(theme.tokens[foreground], theme.tokens[background]), `${foreground} on ${background}`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it.each(themes)("%s graphics meet 3:1 contrast", (_slug, theme) => {
    for (const [foreground, background] of GRAPHIC_PAIRS) {
      expect(contrast(theme.tokens[foreground], theme.tokens[background]), `${foreground} on ${background}`).toBeGreaterThanOrEqual(3);
    }
  });

  it("defines the same tokens in every theme", () => {
    const [first, ...rest] = Object.values(APP_THEMES).map((theme) => Object.keys(theme.tokens).sort());
    for (const keys of rest) expect(keys).toEqual(first);
  });

  it("generates one CSS variable per token, plus the fonts", () => {
    const variables = cssVariablesForTheme(APP_THEMES.frost);
    expect(variables["--panel-raised"]).toBe(APP_THEMES.frost.tokens.panelRaised);
    expect(variables["--series-1"]).toBe(APP_THEMES.frost.tokens.series1);
    expect(variables["--font-brand"]).toContain("Commissioner");
    expect(tokenVariable("mapRoadCasing")).toBe("--map-road-casing");
  });

  it("puts the default theme on :root and each theme on its data-theme", () => {
    const css = themeStylesheet();
    expect(css).toMatch(/^:root\{color-scheme:light;--bg:#F4F5F7;/);
    expect(css).toContain('html[data-theme="graphite"]{color-scheme:dark;--bg:#17181C;');
  });

  it("colours workout types with theme variables", () => {
    expect(workoutTypeColor("CrossFit")).toBe("var(--workout-crossfit)");
    expect(workoutTypeColor("unknown")).toBe("var(--primary)");
  });
});
