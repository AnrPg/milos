export const THEME_SLUGS = [
  "ember",
  "sage",
  "steel",
  "aurora",
  "royal",
  "volt",
  "noir",
  "daybreak",
  "paper",
  "lagoon",
  "sunset",
] as const;

export type ThemeSlug = (typeof THEME_SLUGS)[number];

type ThemeColors = {
  background: string;
  panel: string;
  panelRaised: string;
  panelMuted: string;
  card: string;
  border: string;
  borderStrong: string;
  text: string;
  textSoft: string;
  muted: string;
  dim: string;
  primary: string;
  primaryStrong: string;
  primaryContrast: string;
  success: string;
  warning: string;
  danger: string;
  info: string;
  scaleBase: string;
  scaleScaled: string;
  scaleRx: string;
  scaleAdvanced: string;
};

export type AppTheme = {
  slug: ThemeSlug;
  label: string;
  description: string;
  colors: ThemeColors;
  workoutTypes: Record<string, string>;
};

export const APP_THEMES: Record<ThemeSlug, AppTheme> = {
  ember: {
    slug: "ember",
    label: "Ember",
    description: "Warm charcoal, clay accents, and high-contrast workout tones.",
    colors: {
      background: "var(--bg)",
      panel: "var(--panel)",
      panelRaised: "var(--panel-raised)",
      panelMuted: "var(--panel-muted)",
      card: "var(--card)",
      border: "var(--border)",
      borderStrong: "var(--border-strong)",
      text: "var(--text)",
      textSoft: "var(--text-soft)",
      muted: "var(--muted)",
      dim: "var(--dim)",
      primary: "var(--primary)",
      primaryStrong: "var(--primary-strong)",
      primaryContrast: "var(--bg)",
      success: "var(--success)",
      warning: "var(--warning)",
      danger: "var(--danger)",
      info: "#6EC6D9",
      scaleBase: "var(--text)",
      scaleScaled: "var(--success)",
      scaleRx: "var(--warning)",
      scaleAdvanced: "var(--danger)",
    },
    workoutTypes: {
      crossfit: "#D94D3D",
      strength: "var(--primary)",
      gymnastics: "#E08A4B",
      aerobics: "#D9A441",
      flexibility: "#78BFA6",
      recovery: "#9C8CC8",
    },
  },
  sage: {
    slug: "sage",
    label: "Sage",
    description: "Deep green base with brass and coral accents.",
    colors: {
      background: "#07100D",
      panel: "#0F1A16",
      panelRaised: "#16231E",
      panelMuted: "#0A1511",
      card: "#14201C",
      border: "#20332C",
      borderStrong: "#315044",
      text: "#F1F6EF",
      textSoft: "#C8D8CF",
      muted: "#86A095",
      dim: "#536B61",
      primary: "#D89A3D",
      primaryStrong: "#F0B35C",
      primaryContrast: "#07100D",
      success: "#68D391",
      warning: "#F2C94C",
      danger: "#EE6C4D",
      info: "#69B3A2",
      scaleBase: "#F1F6EF",
      scaleScaled: "#68D391",
      scaleRx: "#F2C94C",
      scaleAdvanced: "#EE6C4D",
    },
    workoutTypes: {
      crossfit: "#EE6C4D",
      strength: "#D89A3D",
      gymnastics: "#C77D46",
      aerobics: "#F2C94C",
      flexibility: "#69B3A2",
      recovery: "#9AAE7A",
    },
  },
  steel: {
    slug: "steel",
    label: "Steel",
    description: "Neutral graphite with cyan, amber, and signal red accents.",
    colors: {
      background: "#080B0E",
      panel: "#10151A",
      panelRaised: "#171D23",
      panelMuted: "#0C1116",
      card: "#151A20",
      border: "#202A33",
      borderStrong: "#33414D",
      text: "#F2F5F7",
      textSoft: "#C7D0D7",
      muted: "#8795A0",
      dim: "#596772",
      primary: "#E26D3D",
      primaryStrong: "#F2895A",
      primaryContrast: "#080B0E",
      success: "#4FD1A5",
      warning: "#F5B84B",
      danger: "#F25F5C",
      info: "#58C7D8",
      scaleBase: "#F2F5F7",
      scaleScaled: "#4FD1A5",
      scaleRx: "#F5B84B",
      scaleAdvanced: "#F25F5C",
    },
    workoutTypes: {
      crossfit: "#F25F5C",
      strength: "#E26D3D",
      gymnastics: "#C88C4A",
      aerobics: "#F5B84B",
      flexibility: "#58C7D8",
      recovery: "#8FA3B8",
    },
  },
  aurora: {
    slug: "aurora",
    label: "Aurora",
    description: "Deep navy with electric mint, violet, and hot-coral energy.",
    colors: {
      background: "#050814",
      panel: "#0B1024",
      panelRaised: "#121A35",
      panelMuted: "#080C1B",
      card: "#111833",
      border: "#202B4E",
      borderStrong: "#374572",
      text: "#F4F7FF",
      textSoft: "#C9D3F2",
      muted: "#8C9AC8",
      dim: "#566384",
      primary: "#8B5CF6",
      primaryStrong: "#A78BFA",
      primaryContrast: "#050814",
      success: "#2DD4BF",
      warning: "#FBBF24",
      danger: "#FB7185",
      info: "#38BDF8",
      scaleBase: "#F4F7FF",
      scaleScaled: "#2DD4BF",
      scaleRx: "#FBBF24",
      scaleAdvanced: "#FB7185",
    },
    workoutTypes: {
      crossfit: "#FB7185",
      strength: "#A78BFA",
      gymnastics: "#F472B6",
      aerobics: "#FBBF24",
      flexibility: "#2DD4BF",
      recovery: "#38BDF8",
    },
  },
  royal: {
    slug: "royal",
    label: "Royal",
    description: "Midnight indigo, regal purple, gold highlights, and ruby warnings.",
    colors: {
      background: "#0A0618",
      panel: "#130D26",
      panelRaised: "#1C1435",
      panelMuted: "#0E0A1E",
      card: "#1A1230",
      border: "#2B2147",
      borderStrong: "#493A73",
      text: "#FAF7FF",
      textSoft: "#D7CDEF",
      muted: "#9C8EBF",
      dim: "#62577F",
      primary: "#C084FC",
      primaryStrong: "#E9D5FF",
      primaryContrast: "#130D26",
      success: "#A3E635",
      warning: "#F4C95D",
      danger: "#F43F5E",
      info: "#7DD3FC",
      scaleBase: "#FAF7FF",
      scaleScaled: "#A3E635",
      scaleRx: "#F4C95D",
      scaleAdvanced: "#F43F5E",
    },
    workoutTypes: {
      crossfit: "#F43F5E",
      strength: "#F4C95D",
      gymnastics: "#C084FC",
      aerobics: "#FB923C",
      flexibility: "#A3E635",
      recovery: "#7DD3FC",
    },
  },
  volt: {
    slug: "volt",
    label: "Volt",
    description: "Blackout surfaces with acid lime, cyan, and magenta contrast.",
    colors: {
      background: "#030504",
      panel: "#0A0F0D",
      panelRaised: "#101915",
      panelMuted: "#050907",
      card: "#0D1512",
      border: "#1C2A24",
      borderStrong: "#355044",
      text: "#F5FFF8",
      textSoft: "#C8EAD2",
      muted: "#8AB79A",
      dim: "#557263",
      primary: "#BEF264",
      primaryStrong: "#D9F99D",
      primaryContrast: "#030504",
      success: "#22C55E",
      warning: "#FDE047",
      danger: "#F43F5E",
      info: "#22D3EE",
      scaleBase: "#F5FFF8",
      scaleScaled: "#22C55E",
      scaleRx: "#FDE047",
      scaleAdvanced: "#F43F5E",
    },
    workoutTypes: {
      crossfit: "#F43F5E",
      strength: "#BEF264",
      gymnastics: "#E879F9",
      aerobics: "#FDE047",
      flexibility: "#22C55E",
      recovery: "#22D3EE",
    },
  },
  noir: {
    slug: "noir",
    label: "Noir",
    description: "Monochrome training floor with champagne, teal, and crimson accents.",
    colors: {
      background: "#050505",
      panel: "#101010",
      panelRaised: "#181818",
      panelMuted: "#0A0A0A",
      card: "#151515",
      border: "#262626",
      borderStrong: "#3F3F3F",
      text: "#F8F5EF",
      textSoft: "#D9D2C7",
      muted: "#A59D92",
      dim: "#6E675F",
      primary: "#EBCB8B",
      primaryStrong: "#F7E0A3",
      primaryContrast: "#050505",
      success: "#5EEAD4",
      warning: "#FACC15",
      danger: "#E11D48",
      info: "#93C5FD",
      scaleBase: "#F8F5EF",
      scaleScaled: "#5EEAD4",
      scaleRx: "#FACC15",
      scaleAdvanced: "#E11D48",
    },
    workoutTypes: {
      crossfit: "#E11D48",
      strength: "#EBCB8B",
      gymnastics: "#D8B4FE",
      aerobics: "#FACC15",
      flexibility: "#5EEAD4",
      recovery: "#93C5FD",
    },
  },
  daybreak: {
    slug: "daybreak",
    label: "Daybreak",
    description: "Warm light theme with cream panels, ink text, and sunrise orange.",
    colors: {
      background: "#FFF7ED",
      panel: "#FFFFFF",
      panelRaised: "#FFF1DF",
      panelMuted: "#F9EAD8",
      card: "#FFFDF8",
      border: "#E8D4BD",
      borderStrong: "#CFAF8D",
      text: "#24160D",
      textSoft: "#5B4635",
      muted: "#846B55",
      dim: "#A98D73",
      primary: "#EA580C",
      primaryStrong: "#C2410C",
      primaryContrast: "#FFF7ED",
      success: "#15803D",
      warning: "#B45309",
      danger: "#DC2626",
      info: "#0369A1",
      scaleBase: "#24160D",
      scaleScaled: "#15803D",
      scaleRx: "#B45309",
      scaleAdvanced: "#DC2626",
    },
    workoutTypes: {
      crossfit: "#DC2626",
      strength: "#EA580C",
      gymnastics: "#B45309",
      aerobics: "#D97706",
      flexibility: "#15803D",
      recovery: "#0369A1",
    },
  },
  paper: {
    slug: "paper",
    label: "Paper",
    description: "Clean editorial light mode with graphite text and blue-violet action.",
    colors: {
      background: "#F7F7F4",
      panel: "#FFFFFF",
      panelRaised: "#F0F0EA",
      panelMuted: "#ECECE4",
      card: "#FFFFFF",
      border: "#D8D8CE",
      borderStrong: "#B8B8AA",
      text: "#18181B",
      textSoft: "#3F3F46",
      muted: "#71717A",
      dim: "#A1A1AA",
      primary: "#4F46E5",
      primaryStrong: "#3730A3",
      primaryContrast: "#FFFFFF",
      success: "#047857",
      warning: "#B45309",
      danger: "#BE123C",
      info: "#0284C7",
      scaleBase: "#18181B",
      scaleScaled: "#047857",
      scaleRx: "#B45309",
      scaleAdvanced: "#BE123C",
    },
    workoutTypes: {
      crossfit: "#BE123C",
      strength: "#4F46E5",
      gymnastics: "#7C3AED",
      aerobics: "#D97706",
      flexibility: "#047857",
      recovery: "#0284C7",
    },
  },
  lagoon: {
    slug: "lagoon",
    label: "Lagoon",
    description: "Fresh light aqua palette with deep teal, coral, and lemon accents.",
    colors: {
      background: "#ECFEFF",
      panel: "#F8FFFF",
      panelRaised: "#DDF7F6",
      panelMuted: "#D1F0EE",
      card: "#FFFFFF",
      border: "#A7D8D5",
      borderStrong: "#69B8B2",
      text: "#083D3D",
      textSoft: "#245B59",
      muted: "#4A807C",
      dim: "#77A8A4",
      primary: "#0F766E",
      primaryStrong: "#115E59",
      primaryContrast: "#ECFEFF",
      success: "#16A34A",
      warning: "#CA8A04",
      danger: "#E11D48",
      info: "#0284C7",
      scaleBase: "#083D3D",
      scaleScaled: "#16A34A",
      scaleRx: "#CA8A04",
      scaleAdvanced: "#E11D48",
    },
    workoutTypes: {
      crossfit: "#E11D48",
      strength: "#0F766E",
      gymnastics: "#8B5CF6",
      aerobics: "#CA8A04",
      flexibility: "#16A34A",
      recovery: "#0284C7",
    },
  },
  sunset: {
    slug: "sunset",
    label: "Sunset",
    description: "Bold light mode with peach surfaces, plum text, and punchy coral.",
    colors: {
      background: "#FFF1F2",
      panel: "#FFFFFF",
      panelRaised: "#FFE4E6",
      panelMuted: "#FFECEF",
      card: "#FFFBFB",
      border: "#F5C2C8",
      borderStrong: "#E99AA6",
      text: "#3B1020",
      textSoft: "#683047",
      muted: "#92566B",
      dim: "#B98191",
      primary: "#E11D48",
      primaryStrong: "#BE123C",
      primaryContrast: "#FFFFFF",
      success: "#0F766E",
      warning: "#B45309",
      danger: "#B91C1C",
      info: "#2563EB",
      scaleBase: "#3B1020",
      scaleScaled: "#0F766E",
      scaleRx: "#B45309",
      scaleAdvanced: "#B91C1C",
    },
    workoutTypes: {
      crossfit: "#B91C1C",
      strength: "#E11D48",
      gymnastics: "#9333EA",
      aerobics: "#F97316",
      flexibility: "#0F766E",
      recovery: "#2563EB",
    },
  },
};

export const DEFAULT_THEME_SLUG: ThemeSlug = "ember";
export const THEME_STORAGE_KEY = "milos:theme-slug";

export function themeBySlug(slug: string | null | undefined): AppTheme {
  return APP_THEMES[normalizeThemeSlug(slug)];
}

export function normalizeThemeSlug(slug: string | null | undefined): ThemeSlug {
  return THEME_SLUGS.includes(slug as ThemeSlug) ? (slug as ThemeSlug) : DEFAULT_THEME_SLUG;
}

export function cssVariablesForTheme(theme: AppTheme): Record<string, string> {
  const { colors } = theme;

  return {
    "--background": colors.background,
    "--foreground": colors.text,
    "--surface": colors.panel,
    "--accent": colors.primary,
    "--accent-strong": colors.primaryStrong,
    "--bg": colors.background,
    "--panel": colors.panel,
    "--panel-raised": colors.panelRaised,
    "--panel-muted": colors.panelMuted,
    "--card": colors.card,
    "--border": colors.border,
    "--border-strong": colors.borderStrong,
    "--text": colors.text,
    "--text-soft": colors.textSoft,
    "--muted": colors.muted,
    "--dim": colors.dim,
    "--primary": colors.primary,
    "--primary-strong": colors.primaryStrong,
    "--primary-contrast": colors.primaryContrast,
    "--success": colors.success,
    "--warning": colors.warning,
    "--danger": colors.danger,
    "--info": colors.info,
    "--scale-base": colors.scaleBase,
    "--scale-scaled": colors.scaleScaled,
    "--scale-rx": colors.scaleRx,
    "--scale-advanced": colors.scaleAdvanced,
    "--workout-crossfit": theme.workoutTypes.crossfit,
    "--workout-strength": theme.workoutTypes.strength,
    "--workout-gymnastics": theme.workoutTypes.gymnastics,
    "--workout-aerobics": theme.workoutTypes.aerobics,
    "--workout-flexibility": theme.workoutTypes.flexibility,
    "--workout-recovery": theme.workoutTypes.recovery,
  };
}

export function applyTheme(slug: string | null | undefined) {
  if (typeof document === "undefined") return;

  const theme = themeBySlug(slug);
  const root = document.documentElement;
  root.dataset.theme = theme.slug;

  Object.entries(cssVariablesForTheme(theme)).forEach(([name, value]) => {
    root.style.setProperty(name, value);
  });
}

export function workoutTypeColor(type: string, slug?: string | null): string {
  if (!slug) {
    const normalized = type.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    return `var(--workout-${normalized}, var(--primary))`;
  }

  const theme = themeBySlug(slug);
  return theme.workoutTypes[type] ?? theme.colors.primary;
}

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
