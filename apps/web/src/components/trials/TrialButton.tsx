"use client";

import Link from "next/link";
import { useEffect, useState, useSyncExternalStore } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchBoxSchedule, type PublicBoxPage } from "@/api/social";
import { subscribeNever } from "@/lib/maps";
import type { TrialOffer } from "@/api/trials";

import { TrialSheet } from "./TrialSheet";

const readSearch = () => window.location.search;
const serverSearch = () => "";

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
 * won't take sees why; nothing shows when the box hasn't opened trials. An
 * event's trial offer opens the sheet straight away (ADR-153).
 */
export function TrialButton({ page, token }: { page: PublicBoxPage; token: string | null }) {
  const t = useTranslations("Trials");
  const offer = useTrialOffer(page.box.slug, token);
  const [open, setOpen] = useState(false);
  const [referralEventId, setReferralEventId] = useState<string | null>(null);
  const offered = offer.data && !offer.data.mine && !offer.data.blocked_reason;
  const search = useSyncExternalStore(subscribeNever, readSearch, serverSearch);

  // An event's trial offer links here with ?trial=1&referral_event_id= (ADR-153):
  // open the sheet once and keep the event on the request. The page renders
  // this button twice (side card, phone bar); the first to run takes the link.
  useEffect(() => {
    if (!offered) return;
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams(window.location.search);
      if (params.get("trial") !== "1") return;
      const referral = params.get("referral_event_id");
      params.delete("trial");
      params.delete("referral_event_id");
      const query = params.toString();
      window.history.replaceState(null, "", window.location.pathname + (query ? `?${query}` : "") + window.location.hash);
      setReferralEventId(referral);
      setOpen(true);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [offered]);
  const base = "flex min-h-11 flex-1 flex-col items-center justify-center rounded-2xl px-3 text-sm font-bold leading-tight";
  const outlined = { border: "1px solid var(--border)", color: "var(--text)" };

  if (!token)
    return (
      <Link href={`/login?next=${encodeURIComponent(`/b/${page.box.slug}${search}`)}`} className={base} style={outlined}>
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
      {open ? <TrialSheet page={page} token={token} offer={data} referralEventId={referralEventId} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
