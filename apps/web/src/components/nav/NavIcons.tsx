import type { SVGProps } from "react";

// Navigation icons: outline (stroke) SVGs in currentColor, so they take the
// theme's colours. Never emoji.

export type NavIconName = "feed" | "box" | "journal" | "bell" | "me" | "messages" | "search";

export function NavIcon({ name, size = 24, strokeWidth = 1.8, ...rest }: { name: NavIconName; size?: number; strokeWidth?: number } & SVGProps<SVGSVGElement>) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
    ...rest,
  };
  switch (name) {
    case "feed":
      return (
        <svg {...common}>
          <path d="M3 10.5 12 3l9 7.5" />
          <path d="M5 9.5V21h5v-6h4v6h5V9.5" />
        </svg>
      );
    case "box":
      return (
        <svg {...common}>
          <path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11" />
        </svg>
      );
    case "journal":
      return (
        <svg {...common}>
          <path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5v-15Z" />
          <path d="M5 19.5A1.5 1.5 0 0 0 6.5 21H19v-3" />
        </svg>
      );
    case "bell":
      // A classic bell: dome, flared rim and clapper.
      return (
        <svg {...common}>
          <path d="M6 9a6 6 0 0 1 12 0c0 4.5 1.2 6.6 2.2 7.6a.6.6 0 0 1-.4 1H4.2a.6.6 0 0 1-.4-1C4.8 15.6 6 13.5 6 9Z" />
          <path d="M10 20.5a2.2 2.2 0 0 0 4 0" />
          <path d="M12 3V2" />
        </svg>
      );
    case "me":
      return (
        <svg {...common}>
          <circle cx="12" cy="8" r="4" />
          <path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" />
        </svg>
      );
    case "messages":
      // Μηνύματα in the Feed header: a speech bubble, the sign people read as
      // "messages" everywhere (ANR 2026-10-24; replaced the paper plane).
      return (
        <svg {...common}>
          <path d="M21 14.5a2 2 0 0 1-2 2H8l-5 4v-14a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" />
        </svg>
      );
    case "search":
      // «Βρες» in the club bar: a magnifying glass (ANR 2026-10-24).
      return (
        <svg {...common}>
          <circle cx="11" cy="11" r="6.5" />
          <path d="m20 20-4.4-4.4" />
        </svg>
      );
  }
}
