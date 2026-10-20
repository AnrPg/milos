"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPoster, posterKey } from "@/api/check-in";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { QrCode } from "./QrCode";

/**
 * The printed poster (ADR-155 §5, board 10 Q1 extra) for a box without a
 * screen at the door: the box's name, the location's static QR and one line.
 * It prints on one A4 page; everything else on the screen stays off paper.
 */
export function PosterPage({ locationId }: { locationId: string }) {
  const t = useTranslations("CheckIn");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const { membership } = useSelectedMembershipRole();
  const poster = useQuery({ queryKey: posterKey(locationId), enabled: Boolean(token), queryFn: () => fetchPoster(token, locationId) });
  const boxName = membership?.settings?.brand_name?.trim() || membership?.organization.name || "";
  const logo = membership?.settings?.brand_logo_url ?? null;
  const back = adminHref(`/admin/settings/locations/${locationId}`, slug);

  return (
    <main className="checkin-print-root flex min-h-dvh flex-col items-center gap-6 px-6 py-8" style={{ background: "var(--bg)" }}>
      <nav className="checkin-print-hide flex w-full max-w-2xl items-center justify-between gap-3">
        <Link href={back} className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
          ‹ {t("backToLocation")}
        </Link>
        {poster.data?.enabled ? (
          <button
            type="button"
            onClick={() => window.print()}
            className="min-h-11 rounded-full px-5 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {t("posterPrint")}
          </button>
        ) : null}
      </nav>

      {poster.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {poster.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("errorGeneric")}</p> : null}
      {poster.data && !poster.data.enabled ? (
        <div className="checkin-print-hide flex max-w-md flex-col gap-3 text-center">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("posterOff")}</p>
          <Link href={back} className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>{t("posterTurnOnThere")}</Link>
        </div>
      ) : null}

      {poster.data?.enabled ? (
        <article
          className="flex w-full max-w-2xl flex-col items-center gap-6 rounded-[2rem] px-8 py-10 text-center"
          style={{ background: "#fff", color: "#000", border: "1px solid var(--border)" }}
          data-testid="poster-sheet"
        >
          {logo ? (
            // eslint-disable-next-line @next/next/no-img-element -- the box's uploaded logo
            <img src={logo} alt="" className="h-20 w-auto object-contain" />
          ) : null}
          <h1 className="text-4xl font-black">{boxName}</h1>
          <p className="text-lg font-semibold">{poster.data.location.name}</p>
          <QrCode value={poster.data.deep_link} label={t("posterQrLabel")} testId="poster-qr" className="h-auto w-[min(80vw,26rem)]" />
          <p className="text-2xl font-extrabold">{t("posterLine")}</p>
          <p className="text-sm">{t("posterHint")}</p>
        </article>
      ) : null}
    </main>
  );
}
