"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchBoxSchedule, type PublicBoxPage } from "@/api/social";
import type { TrialOffer } from "@/api/trials";

import { TrialSheet } from "./TrialSheet";

/** What the box offers this visitor (null for members or when trials are off). */
export function useTrialOffer(slug: string, token: string | null) {
  return useQuery({
    queryKey: ["social", "box-schedule", slug, "offer"],
    enabled: Boolean(token),
    queryFn: () => fetchBoxSchedule(token!, slug),
    select: (data) => (data.trial_offer ?? null) as TrialOffer | null,
  });
}

/**
 * «Ζήτα δοκιμαστικό» on the box page (board 6 Q1). Signed-out visitors sign
 * in first; a visitor with an open trial sees it instead; a visitor the box
 * won't take sees why; nothing shows when the box hasn't opened trials.
 */
export function TrialButton({ page, token }: { page: PublicBoxPage; token: string | null }) {
  const t = useTranslations("Trials");
  const offer = useTrialOffer(page.box.slug, token);
  const [open, setOpen] = useState(false);
  const base = "flex min-h-11 flex-1 flex-col items-center justify-center rounded-2xl px-3 text-sm font-bold leading-tight";
  const outlined = { border: "1px solid var(--border)", color: "var(--text)" };

  if (!token)
    return (
      <Link href={`/login?next=${encodeURIComponent(`/b/${page.box.slug}`)}`} className={base} style={outlined}>
        {t("ask")}
      </Link>
    );
  if (offer.isPending) return <div className="h-11 flex-1 animate-pulse rounded-2xl" style={{ background: "var(--panel-raised)" }} />;
  const data = offer.data;
  if (!data) return null;
  if (data.mine)
    return (
      <Link href={`/trials/${data.mine.id}`} className={base} style={{ ...outlined, borderColor: "var(--success)" }}>
        {t("yourTrial")}
        <span className="text-[11px] font-semibold" style={{ color: "var(--success)" }}>{t(`status_${data.mine.status}`)}</span>
      </Link>
    );
  if (data.blocked_reason)
    return (
      <button type="button" disabled className={base} style={{ border: "1px solid var(--border)", color: "var(--dim)" }}>
        {t("ask")}
        <span className="text-[11px] font-semibold">{t(`blocked_${data.blocked_reason}`)}</span>
      </button>
    );
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={base} style={outlined}>
        {t("ask")}
        {data.approval === "auto" ? <span className="text-[11px] font-semibold" style={{ color: "var(--success)" }}>{t("free")}</span> : null}
      </button>
      {open ? <TrialSheet page={page} token={token} offer={data} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
