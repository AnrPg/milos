/**
 * The Palee theme: the single source of every colour, shadow and font in the
 * app (docs/brand/THEME.md lists which token dresses which UI part).
 *
 * Gyms and members all wear the same brand palette (Frost Graphite, see
 * docs/brand/BRAND.md) in a light ("frost", the default) and a dark
 * ("graphite") variant. Components never use colour literals: they read the
 * CSS variables generated from these tokens (`--bg`, `--primary`, ...), and
 * the few places that cannot read CSS (share images, document exports, the
 * PWA manifest, QR codes) import the token values from here. Re-dressing the
 * app means editing this file only; `theme-guard.test.ts` fails on any colour
 * literal elsewhere.
 */

import { workoutTypeFamily, type WorkoutTypeFamily } from "@/lib/workout-types";

export const THEME_SLUGS = ["frost", "graphite"] as const;

export type ThemeSlug = (typeof THEME_SLUGS)[number];

export const DEFAULT_THEME_SLUG: ThemeSlug = "frost";

export type ThemeTokens = {
  // Surfaces
  bg: string;
  panel: string;
  panelRaised: string;
  panelMuted: string;
  card: string;
  border: string;
  borderStrong: string;
  // Text
  text: string;
  textSoft: string;
  muted: string;
  dim: string;
  placeholder: string;
  // Brand roles (BRAND.md): Dojo primary for actions and navigation, Spark for
  // what is alive now (LIVE, new, WOD tags, challenges), Heat for emotion
  // (kudos, PRs, comebacks, support), Deep for the one hero surface per screen.
  primary: string;
  primaryStrong: string;
  primaryContrast: string;
  spark: string;
  sparkContrast: string;
  heat: string;
  heatContrast: string;
  deep: string;
  deepContrast: string;
  // Status
  success: string;
  successContrast: string;
  warning: string;
  warningContrast: string;
  danger: string;
  dangerContrast: string;
  // Error messages and boxes (ui/ErrorNotice): a red-tinted surface, its
  // border, and the red text that reads on it.
  dangerSurface: string;
  dangerBorder: string;
  dangerStrong: string;
  info: string;
  infoContrast: string;
  // Interaction
  focusRing: string;
  selection: string;
  selectionText: string;
  highlight: string;
  highlightText: string;
  // Form controls (inputs, selects, date and time pickers, switches, sliders)
  controlBg: string;
  controlBorder: string;
  controlKnob: string;
  // Scrollbars
  scrollbarTrack: string;
  scrollbarThumb: string;
  scrollbarThumbHover: string;
  // Overlays and media: dialog backdrops, photo and video stages, controls
  // drawn over media, and white "paper" (QR codes, receipts, print).
  scrim: string;
  scrimStrong: string;
  media: string;
  onMedia: string;
  onMediaSoft: string;
  mediaControl: string;
  mediaControlBorder: string;
  mediaControlInverse: string;
  paper: string;
  onPaper: string;
  // Elevation
  shadowSm: string;
  shadowMd: string;
  shadowLg: string;
  // Scale levels
  scaleBase: string;
  scaleScaled: string;
  scaleRx: string;
  scaleAdvanced: string;
  // Workout types
  workoutCrossfit: string;
  workoutStrength: string;
  workoutGymnastics: string;
  workoutAerobics: string;
  workoutFlexibility: string;
  workoutRecovery: string;
  workoutCombat: string;
  workoutDance: string;
  workoutOutdoor: string;
  // Chart and data series (sources, wellness, analytics)
  series1: string;
  series2: string;
  series3: string;
  series4: string;
  series5: string;
  series6: string;
  series7: string;
  series8: string;
  seriesNeutral: string;
  onSeries: string;
  // Anatomy figure (ADR-164)
  anatomyPrimary: string;
  anatomySecondary: string;
  anatomyStabilizer: string;
  anatomyFelt: string;
  anatomyHeatLow: string;
  anatomyHeatMedium: string;
  anatomyHeatHigh: string;
  anatomyBase: string;
  anatomyBone: string;
  // Street maps (MapLibre style colours)
  mapLand: string;
  mapWater: string;
  mapPark: string;
  mapBuilding: string;
  mapRoad: string;
  mapRoadMajor: string;
  mapRoadCasing: string;
  mapBoundary: string;
  mapLabel: string;
  mapLabelHalo: string;
};

export type AppTheme = {
  slug: ThemeSlug;
  label: string;
  description: string;
  scheme: "light" | "dark";
  tokens: ThemeTokens;
};

export const THEME_FONTS = {
  // Self-hosted (@fontsource-variable/commissioner, imported by the root
  // layout): Latin, Greek and Cyrillic; Arabic and Hebrew fall back.
  sans: '"Commissioner Variable", "Commissioner", "Avenir Next", "Segoe UI", system-ui, sans-serif',
  mono: '"SFMono-Regular", "Menlo", ui-monospace, monospace',
} as const;

// The brand palette's named colours (BRAND.md).
const FROST = "#F4F5F7";
const GRAPHITE = "#17181C";
const WHITE = "#FFFFFF";
const BLACK = "#000000";
const DOJO = "#2F5BFF";
const DOJO_GLOW = "#5B7CFF";
const SPARK = "#E4FF6E";
// Spark's deeper tone for light pages: Sun Lime fades to cream next to Frost
// and on lower-gamut laptop panels, so Frost uses a greener, denser lime
// (still 15:1 with Graphite text). Graphite keeps Sun Lime, which glows there.
const SPARK_DEEP = "#C8FF4D";
const HEAT = "#E0203F";
const HEAT_GLOW = "#FF4D6A";

export const APP_THEMES: Record<ThemeSlug, AppTheme> = {
  frost: {
    slug: "frost",
    label: "theme_frost_label",
    description: "theme_frost_description",
    scheme: "light",
    tokens: {
      bg: FROST,
      panel: WHITE,
      panelRaised: WHITE,
      panelMuted: "#ECEEF2",
      card: WHITE,
      border: "#DFE2E8",
      borderStrong: "#A2A8B3",
      text: GRAPHITE,
      textSoft: "#3A3D45",
      muted: "#5E6470",
      dim: "#646A75",
      placeholder: "#8A909B",
      primary: DOJO,
      primaryStrong: "#1F45E0",
      primaryContrast: WHITE,
      spark: SPARK_DEEP,
      sparkContrast: GRAPHITE,
      heat: HEAT,
      heatContrast: WHITE,
      deep: GRAPHITE,
      deepContrast: FROST,
      success: "#1B7A43",
      successContrast: WHITE,
      warning: "#9A5C00",
      warningContrast: WHITE,
      danger: HEAT,
      dangerContrast: WHITE,
      dangerSurface: "#FDECEF",
      dangerBorder: "#F09AAA",
      dangerStrong: "#B0102C",
      info: "#0B7FA8",
      infoContrast: WHITE,
      focusRing: DOJO,
      selection: "#C9D5FF",
      selectionText: GRAPHITE,
      highlight: SPARK_DEEP,
      highlightText: GRAPHITE,
      controlBg: "#ECEEF2",
      controlBorder: "#A2A8B3",
      controlKnob: WHITE,
      scrollbarTrack: "#ECEEF2",
      scrollbarThumb: "#A2A8B3",
      scrollbarThumbHover: "#6B717C",
      scrim: "rgb(23 24 28 / 0.5)",
      scrimStrong: "rgb(14 15 18 / 0.94)",
      media: BLACK,
      onMedia: WHITE,
      onMediaSoft: "rgb(255 255 255 / 0.75)",
      mediaControl: "rgb(14 15 18 / 0.55)",
      mediaControlBorder: "rgb(255 255 255 / 0.35)",
      mediaControlInverse: "rgb(255 255 255 / 0.16)",
      paper: WHITE,
      onPaper: BLACK,
      shadowSm: "0 1px 3px rgb(23 24 28 / 0.12)",
      shadowMd: "0 12px 32px rgb(23 24 28 / 0.16)",
      shadowLg: "0 30px 90px rgb(23 24 28 / 0.24)",
      scaleBase: GRAPHITE,
      scaleScaled: "#1B7A43",
      scaleRx: "#9A5C00",
      scaleAdvanced: HEAT,
      workoutCrossfit: HEAT,
      workoutStrength: DOJO,
      workoutGymnastics: "#9A5C00",
      workoutAerobics: "#7A5AF8",
      workoutFlexibility: "#1F8A4C",
      workoutRecovery: "#0B7FA8",
      workoutCombat: "#9C4A1A",
      workoutDance: "#B0186A",
      workoutOutdoor: "#4F7A12",
      series1: DOJO,
      series2: "#E0203F",
      series3: "#1F8A4C",
      series4: "#7A5AF8",
      series5: "#9A5C00",
      series6: "#0B7FA8",
      series7: "#C2187A",
      series8: "#5E7A00",
      seriesNeutral: "#8A909B",
      onSeries: WHITE,
      anatomyPrimary: DOJO,
      anatomySecondary: "#8FA4FF",
      anatomyStabilizer: "#C9D5FF",
      anatomyFelt: HEAT,
      anatomyHeatLow: "#C9D5FF",
      anatomyHeatMedium: "#5B7CFF",
      anatomyHeatHigh: "#1F45E0",
      anatomyBase: "#A2A8B3",
      anatomyBone: "#DFE2E8",
      mapLand: FROST,
      mapWater: "#C9D5FF",
      mapPark: "#E3EBDD",
      mapBuilding: "#E4E6EB",
      mapRoad: WHITE,
      mapRoadMajor: WHITE,
      mapRoadCasing: "#DFE2E8",
      mapBoundary: "#A2A8B3",
      mapLabel: "#3A3D45",
      mapLabelHalo: FROST,
    },
  },
  // The brand's dark variant, "Graphite Night": Graphite page, glow tones.
  graphite: {
    slug: "graphite",
    label: "theme_graphite_label",
    description: "theme_graphite_description",
    scheme: "dark",
    tokens: {
      bg: GRAPHITE,
      panel: "#1D1F24",
      panelRaised: "#22242A",
      panelMuted: "#131418",
      card: "#22242A",
      border: "#2C2F37",
      borderStrong: "#4A4F5A",
      text: FROST,
      textSoft: "#D2D5DB",
      muted: "#A2A8B3",
      dim: "#8A909B",
      placeholder: "#6B717C",
      primary: DOJO_GLOW,
      primaryStrong: "#8FA4FF",
      primaryContrast: "#0E0F12",
      spark: SPARK,
      sparkContrast: GRAPHITE,
      heat: HEAT_GLOW,
      heatContrast: "#0E0F12",
      deep: "#2C2F37",
      deepContrast: FROST,
      success: "#4CC27E",
      successContrast: "#0E0F12",
      warning: "#F0A63A",
      warningContrast: "#0E0F12",
      danger: HEAT_GLOW,
      dangerContrast: "#0E0F12",
      dangerSurface: "#3A1820",
      dangerBorder: "#8C2E42",
      dangerStrong: "#FF8E9F",
      info: "#6FB8FF",
      infoContrast: "#0E0F12",
      focusRing: "#8FA4FF",
      selection: "#2F3F80",
      selectionText: FROST,
      highlight: SPARK,
      highlightText: GRAPHITE,
      controlBg: "#131418",
      controlBorder: "#4A4F5A",
      controlKnob: FROST,
      scrollbarTrack: "#131418",
      scrollbarThumb: "#4A4F5A",
      scrollbarThumbHover: "#8A909B",
      scrim: "rgb(0 0 0 / 0.6)",
      scrimStrong: "rgb(0 0 0 / 0.94)",
      media: BLACK,
      onMedia: WHITE,
      onMediaSoft: "rgb(255 255 255 / 0.75)",
      mediaControl: "rgb(0 0 0 / 0.55)",
      mediaControlBorder: "rgb(255 255 255 / 0.35)",
      mediaControlInverse: "rgb(255 255 255 / 0.16)",
      paper: WHITE,
      onPaper: BLACK,
      shadowSm: "0 1px 3px rgb(0 0 0 / 0.4)",
      shadowMd: "0 12px 32px rgb(0 0 0 / 0.5)",
      shadowLg: "0 30px 90px rgb(0 0 0 / 0.6)",
      scaleBase: FROST,
      scaleScaled: "#4CC27E",
      scaleRx: "#F0A63A",
      scaleAdvanced: HEAT_GLOW,
      workoutCrossfit: HEAT_GLOW,
      workoutStrength: DOJO_GLOW,
      workoutGymnastics: "#F0A63A",
      workoutAerobics: "#A894FF",
      workoutFlexibility: "#4CC27E",
      workoutRecovery: "#6FB8FF",
      workoutCombat: "#F2925A",
      workoutDance: "#FF7AC0",
      workoutOutdoor: "#A6D35C",
      series1: DOJO_GLOW,
      series2: HEAT_GLOW,
      series3: "#4CC27E",
      series4: "#A894FF",
      series5: "#F0A63A",
      series6: "#6FB8FF",
      series7: "#FF7AC6",
      series8: SPARK,
      seriesNeutral: "#8A909B",
      onSeries: "#0E0F12",
      anatomyPrimary: DOJO_GLOW,
      anatomySecondary: "#8FA4FF",
      anatomyStabilizer: "#3A4A8C",
      anatomyFelt: HEAT_GLOW,
      anatomyHeatLow: "#3A4A8C",
      anatomyHeatMedium: DOJO_GLOW,
      anatomyHeatHigh: "#C9D5FF",
      anatomyBase: "#4A4F5A",
      anatomyBone: "#2C2F37",
      mapLand: GRAPHITE,
      mapWater: "#1E2A4D",
      mapPark: "#1C2620",
      mapBuilding: "#22242A",
      mapRoad: "#2C2F37",
      mapRoadMajor: "#3A3D45",
      mapRoadCasing: "#131418",
      mapBoundary: "#4A4F5A",
      mapLabel: "#D2D5DB",
      mapLabelHalo: GRAPHITE,
    },
  },
};

/**
 * Colours for surfaces drawn outside the page (link previews and share
 * images): the dark variant, so a card reads as Palee in any feed.
 */
export const SHARE_CARD_TOKENS: ThemeTokens = APP_THEMES.graphite.tokens;

/** Colours for printed and exported documents (PDF, ODT, invoices): paper is light. */
export const PRINT_TOKENS: ThemeTokens = APP_THEMES[DEFAULT_THEME_SLUG].tokens;

/** `#2F5BFF` → `[47, 91, 255]`, for libraries that take RGB channels (jsPDF). */
export function rgbChannels(hex: string): [number, number, number] {
  const value = Number.parseInt(hex.replace("#", ""), 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

export const THEME_STORAGE_KEY = "palee:theme-slug";

export function themeBySlug(slug: string | null | undefined): AppTheme {
  return APP_THEMES[normalizeThemeSlug(slug)];
}

export function normalizeThemeSlug(slug: string | null | undefined): ThemeSlug {
  return THEME_SLUGS.includes(slug as ThemeSlug) ? (slug as ThemeSlug) : DEFAULT_THEME_SLUG;
}

/** `panelRaised` → `--panel-raised`. */
export function tokenVariable(name: keyof ThemeTokens): string {
  return `--${name.replace(/([a-z])([A-Z0-9])/g, "$1-$2").toLowerCase()}`;
}

/** `var(--panel-raised)`, for code that builds styles from token names. */
export function tokenVar(name: keyof ThemeTokens): string {
  return `var(${tokenVariable(name)})`;
}

export function cssVariablesForTheme(theme: AppTheme): Record<string, string> {
  const variables: Record<string, string> = {};
  for (const [name, value] of Object.entries(theme.tokens)) {
    variables[tokenVariable(name as keyof ThemeTokens)] = value;
  }
  variables["--font-brand"] = THEME_FONTS.sans;
  variables["--font-code"] = THEME_FONTS.mono;
  return variables;
}

/**
 * The stylesheet that defines every theme variable: the default theme on
 * `:root`, each theme on `html[data-theme=…]`. The root layout inlines it,
 * so the page paints in the right colours before any script runs.
 */
export function themeStylesheet(): string {
  const block = (selector: string, theme: AppTheme) =>
    `${selector}{color-scheme:${theme.scheme};${Object.entries(cssVariablesForTheme(theme))
      .map(([name, value]) => `${name}:${value}`)
      .join(";")}}`;
  return [
    block(":root", APP_THEMES[DEFAULT_THEME_SLUG]),
    ...THEME_SLUGS.map((slug) => block(`html[data-theme="${slug}"]`, APP_THEMES[slug])),
  ].join("\n");
}

export function applyTheme(slug: string | null | undefined) {
  if (typeof document === "undefined") return;
  const theme = themeBySlug(slug);
  document.documentElement.dataset.theme = theme.slug;
  // The browser chrome and the phone's status bar follow the page.
  document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]').forEach((meta) => {
    meta.content = theme.tokens.bg;
  });
}

/** The current value of a theme token on the page (for canvas and map code). */
export function readToken(name: keyof ThemeTokens): string {
  if (typeof document === "undefined") return APP_THEMES[DEFAULT_THEME_SLUG].tokens[name];
  const value = getComputedStyle(document.documentElement).getPropertyValue(tokenVariable(name)).trim();
  return value || themeBySlug(document.documentElement.dataset.theme).tokens[name];
}

/** ADR-275: one colour per workout family; the first six keep the original kinds' colours. */
const WORKOUT_FAMILY_TOKENS: Record<WorkoutTypeFamily, keyof ThemeTokens> = {
  functional: "workoutCrossfit",
  strength: "workoutStrength",
  gymnastics: "workoutGymnastics",
  endurance: "workoutAerobics",
  mind_body: "workoutFlexibility",
  recovery: "workoutRecovery",
  combat: "workoutCombat",
  dance: "workoutDance",
  outdoor: "workoutOutdoor",
};

export function workoutTypeColor(type: string): string {
  const family = workoutTypeFamily(type.toLowerCase().replace(/[^a-z0-9]+/g, "_"));
  return family ? tokenVar(WORKOUT_FAMILY_TOKENS[family]) : tokenVar("primary");
}

export const SERIES_TOKENS: readonly (keyof ThemeTokens)[] = [
  "series1",
  "series2",
  "series3",
  "series4",
  "series5",
  "series6",
  "series7",
  "series8",
];

export function scaleLevelTone(value: string | null | undefined): "base" | "scaled" | "rx" | "advanced" {
  const normalized = (value ?? "")
    .toLowerCase()
    .replace(/\+/g, "plus")
    .replace(/[^a-z0-9]+/g, "_");

  if (!normalized || normalized === "base") return "base";
  if (["scaled", "beginner", "foundational", "foundation"].includes(normalized)) return "scaled";
  if (["rx", "intermediate", "prescribed"].includes(normalized)) return "rx";
  if (["rxplus", "rx_plus", "advanced", "elite"].includes(normalized)) return "advanced";
  return "scaled";
}

export function scaleLevelVar(value: string | null | undefined): string {
  return `var(--scale-${scaleLevelTone(value)})`;
}

export function translucent(color: string, amountPercent: number): string {
  return `color-mix(in srgb, ${color} ${amountPercent}%, transparent)`;
}
