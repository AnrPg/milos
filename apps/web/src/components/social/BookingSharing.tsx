"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { setBookingSharing, SOCIAL_KEY, SUMMARY_KEY, type SocialSummary } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useSocialSummary } from "@/components/social/use-social";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

function useSetBookingSharing() {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const tUi = useUiTranslations();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function set(enabled: boolean) {
    if (!tokens?.access_token || busy) return;
    setBusy(true);
    setError(null);
    try {
      const booking_sharing = await setBookingSharing(tokens.access_token, enabled);
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (summary) => (summary ? { ...summary, booking_sharing } : summary));
      await queryClient.invalidateQueries({ queryKey: SOCIAL_KEY });
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    } finally {
      setBusy(false);
    }
  }

  return { set, busy, error };
}

/**
 * The one-time offer (board 5 Q6): once the member has a follower, ask
 * whether followers may see the classes they book. Bookings stay private
 * until they say yes (vision §4.5); either answer hides the card for good.
 */
export function BookingSharingOffer() {
  const t = useTranslations("Social");
  const summary = useSocialSummary();
  const { set, busy, error } = useSetBookingSharing();
  const data = summary.data;
  if (!data || data.booking_sharing.offered || data.followers_count === 0) return null;

  return (
    <section className="flex flex-col gap-3 rounded-3xl p-4" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <h2 className="font-bold" style={{ color: "var(--text)" }}>{t("bookingSharingTitle")}</h2>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("bookingSharingBody")}</p>
      <div className="flex gap-2">
        <button
          type="button"
          disabled={busy}
          onClick={() => void set(true)}
          className="min-h-11 flex-1 rounded-2xl text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("bookingSharingYes")}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => void set(false)}
          className="min-h-11 flex-1 rounded-2xl text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("bookingSharingNo")}
        </button>
      </div>
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </section>
  );
}

/** Κοινοποίηση & ορατότητα: the same choice, any time. */
export function BookingSharingSetting() {
  const t = useTranslations("Social");
  const summary = useSocialSummary();
  const { set, busy, error } = useSetBookingSharing();
  const enabled = summary.data?.booking_sharing.enabled ?? false;
  if (summary.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;

  return (
    <div className="space-y-4">
      <p className="text-sm" style={{ color: "var(--muted)" }}>{enabled ? t("bookingSharingOn") : t("bookingSharingOff")}</p>
      <button
        type="button"
        aria-pressed={enabled}
        disabled={busy || !summary.data}
        onClick={() => void set(!enabled)}
        className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
        style={enabled ? { border: "1px solid var(--border)", color: "var(--text)" } : { background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {enabled ? t("bookingSharingTurnOff") : t("bookingSharingTurnOn")}
      </button>
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </div>
  );
}
