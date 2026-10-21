import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { ImageResponse } from "next/og";
import { getTranslations } from "next-intl/server";

import { BRAND_NAME } from "@/lib/public-box";
import { loadReferralInvite } from "@/lib/referral-invite";
import { SHARE_CARD_TOKENS as card } from "@/lib/theme";

export const alt = BRAND_NAME;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const fonts = Promise.all([
  readFile(join(process.cwd(), "public/fonts/DejaVuSans.ttf")),
  readFile(join(process.cwd(), "public/fonts/DejaVuSans-Bold.ttf")),
]);

/**
 * Link preview of an invite (ADR-156, board 11 extra): the box's cover (or
 * its logo and colour), its name, and who invites. The friend's gift stays
 * on the page, not in a preview anyone can forward.
 */
export default async function Image({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const [regular, bold] = await fonts;
  const invite = await loadReferralInvite(code);
  const t = await getTranslations("Referrals");
  const name = invite?.box.name ?? BRAND_NAME;
  const line = invite
    ? invite.inviter.nickname
      ? t("invite.title", { name: invite.inviter.nickname, box: name })
      : t("invite.titleNoName", { box: name })
    : "";
  const cover = invite?.box.cover?.url ?? null;
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();

  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", position: "relative", background: card.bg, color: card.text }}>
      {cover ? <img src={cover} alt="" width={1200} height={630} style={{ objectFit: "cover", width: "100%", height: "100%", opacity: 0.55 }} /> : null}
      <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", gap: 48, padding: 72 }}>
        {invite?.box.logo_url ? (
          <img src={invite.box.logo_url} alt="" width={200} height={200} style={{ borderRadius: 100, objectFit: "cover" }} />
        ) : (
          <div style={{ width: 200, height: 200, borderRadius: 100, background: card.primary, color: card.primaryContrast, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 80, fontWeight: 700 }}>
            {initials}
          </div>
        )}
        <div style={{ display: "flex", flexDirection: "column", gap: 18, flex: 1 }}>
          <div style={{ fontSize: 68, fontWeight: 700 }}>{name}</div>
          {line ? <div style={{ fontSize: 36, color: card.textSoft }}>{line}</div> : null}
        </div>
      </div>
      <div style={{ position: "absolute", right: 56, bottom: 44, fontSize: 28, fontWeight: 700, color: card.primary, letterSpacing: 4 }}>{BRAND_NAME.toUpperCase()}</div>
    </div>,
    {
      ...size,
      fonts: [
        { name: "DejaVu Sans", data: regular, weight: 400, style: "normal" },
        { name: "DejaVu Sans", data: bold, weight: 700, style: "normal" },
      ],
    },
  );
}
