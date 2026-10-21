import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { ImageResponse } from "next/og";
import { getTranslations } from "next-intl/server";

import { BRAND_NAME, loadPublicBox, previewLine } from "@/lib/public-box";

export const alt = BRAND_NAME;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const fonts = Promise.all([
  readFile(join(process.cwd(), "public/fonts/DejaVuSans.ttf")),
  readFile(join(process.cwd(), "public/fonts/DejaVuSans-Bold.ttf")),
]);

/**
 * Link preview (board 4 Q14): the published cover with the name and
 * «discipline · neighbourhood»; gyms without a cover get a card with their
 * logo, name, disciplines and brand colour.
 */
export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const [regular, bold] = await fonts;
  const page = await loadPublicBox(slug);
  const tags = await getTranslations("BoxTags");
  const name = page?.box.name ?? BRAND_NAME;
  const line = page ? previewLine(page, (key) => tags(`discipline.${key}`)) : "";
  const cover = page?.profile.cover?.url ?? null;
  const brand = page?.box.primary_color ?? "#D9743D";
  const disciplines = (page?.profile.disciplines ?? []).slice(0, 3).map((key) => tags(`discipline.${key}`));
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();

  return new ImageResponse(
    cover ? (
      <div style={{ width: "100%", height: "100%", display: "flex", position: "relative", background: "#150F0D" }}>
        <img src={cover} alt="" width={1200} height={630} style={{ objectFit: "cover", width: "100%", height: "100%" }} />
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 0,
            padding: "48px 56px",
            display: "flex",
            flexDirection: "column",
            background: "linear-gradient(transparent, rgba(0,0,0,0.85))",
            color: "#FBF3EE",
          }}
        >
          <div style={{ fontSize: 64, fontWeight: 700 }}>{name}</div>
          {line ? <div style={{ fontSize: 34, opacity: 0.9 }}>{line}</div> : null}
        </div>
      </div>
    ) : (
      <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", gap: 48, padding: 72, background: "#150F0D", color: "#FBF3EE" }}>
        {page?.box.logo_url ? (
          <img src={page.box.logo_url} alt="" width={220} height={220} style={{ borderRadius: 110, objectFit: "cover" }} />
        ) : (
          <div style={{ width: 220, height: 220, borderRadius: 110, background: brand, color: "#0B0807", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 88, fontWeight: 700 }}>
            {initials}
          </div>
        )}
        <div style={{ display: "flex", flexDirection: "column", gap: 16, flex: 1 }}>
          <div style={{ fontSize: 72, fontWeight: 700 }}>{name}</div>
          {disciplines.length > 0 ? <div style={{ fontSize: 34, color: "#E0CFC5" }}>{disciplines.join(" · ")}</div> : null}
          {line ? <div style={{ fontSize: 30, color: "#C9B4A7" }}>{line.split(" · ").slice(-1)[0]}</div> : null}
        </div>
        <div style={{ position: "absolute", right: 56, bottom: 44, fontSize: 28, fontWeight: 700, color: brand, letterSpacing: 4 }}>{BRAND_NAME.toUpperCase()}</div>
      </div>
    ),
    {
      ...size,
      fonts: [
        { name: "DejaVu Sans", data: regular, weight: 400, style: "normal" },
        { name: "DejaVu Sans", data: bold, weight: 700, style: "normal" },
      ],
    },
  );
}
