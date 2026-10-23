import { ImageResponse } from "next/og";
import { getTranslations } from "next-intl/server";

import { BRAND_NAME } from "@/lib/seo/site-info";
import { APP_THEMES, DEFAULT_THEME_SLUG } from "@/lib/theme";

// The link-preview card (Open Graph / X): 1200x630 PNG, since most previews
// and answer engines ignore SVG images.
export const alt = BRAND_NAME;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpenGraphImage() {
  const { tokens } = APP_THEMES[DEFAULT_THEME_SLUG];
  const ui = await getTranslations("Ui");
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "80px",
          background: tokens.bg,
          color: tokens.text,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "36px" }}>
          <svg viewBox="20 20 160 160" width="160" height="160">
            <path d="M40 52 Q46 150 100 150 Q154 150 160 52" fill="none" stroke={tokens.text} strokeWidth="26" strokeLinecap="round" />
            <circle cx="100" cy="88" r="24" fill={tokens.primary} />
          </svg>
          <div style={{ fontSize: 128, fontWeight: 700, letterSpacing: "-0.03em" }}>{ui("brandName")}</div>
        </div>
        <div style={{ marginTop: 48, fontSize: 40, lineHeight: 1.35, maxWidth: 1000, color: tokens.muted }}>
          {ui("gymSchedulingAthleteProgrammingAndWorkoutExecution7f2b88a")}
        </div>
      </div>
    ),
    size,
  );
}
