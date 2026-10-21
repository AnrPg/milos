"use client";

import { useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BODY_CONSENTS_KEY, fetchHealthConsents } from "@/api/body";
import { connectGarmin, DEVICES_KEY, type GarminRow } from "@/api/devices";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { deviceErrorCode, deviceErrorKey, PrefSwitches, SectionLabel } from "@/components/devices/DeviceBits";
import {
  backfillOptions,
  canContinue,
  connectRequest,
  DEFAULT_BACKFILL_DAYS,
  fullPrefs,
  showsConsentLine,
  togglePref,
  type FullSyncPrefs,
} from "@/components/devices/garmin-model";

/**
 * «Σύνδεση» (board 16 Q1 A, Q5 A): what to bring in, each on, how far back
 * (30 days preselected), the health-data consent when it is needed, then
 * Garmin's sign-in. «Επανασύνδεση» opens the same sheet with the row's choices.
 */
export function GarminConnectSheet({
  token,
  row,
  reconnect = false,
  onClose,
  navigate = (url: string) => window.location.assign(url),
}: {
  token: string;
  row: GarminRow;
  reconnect?: boolean;
  onClose: () => void;
  /** Where Garmin's sign-in opens; replaced in tests. */
  navigate?: (url: string) => void;
}) {
  const t = useTranslations("Devices");
  const labelId = useId();
  const pastId = useId();
  const queryClient = useQueryClient();
  const [prefs, setPrefs] = useState<FullSyncPrefs>(() => fullPrefs(row.connection?.sync_prefs ?? row.sync_prefs));
  const [days, setDays] = useState<number>(row.connection?.backfill_days ?? DEFAULT_BACKFILL_DAYS);
  const [consentTicked, setConsentTicked] = useState(false);
  const [serverAsked, setServerAsked] = useState(false);
  const consents = useQuery({ queryKey: BODY_CONSENTS_KEY, enabled: Boolean(token), queryFn: () => fetchHealthConsents(token) });
  const consented = Boolean(consents.data?.some((consent) => consent.scope === "health_data" && consent.active));
  const consentShown = showsConsentLine(prefs, consented, serverAsked);

  const connect = useMutation({
    mutationFn: () => connectGarmin(token, connectRequest(prefs, days, consentShown && consentTicked)),
    onSuccess: (result) => navigate(result.authorize_url),
    onError: (error) => {
      const code = deviceErrorCode(error);
      if (code === "health_data_consent_required") setServerAsked(true);
      if (code === "device_already_connected" || code === "garmin_not_configured") void queryClient.invalidateQueries({ queryKey: DEVICES_KEY });
    },
  });
  const redirecting = connect.isPending || connect.isSuccess;
  const ready = canContinue(prefs, consentShown, consentTicked) && !consents.isPending;

  return (
    <Sheet
      title={reconnect ? t("reconnectTitle") : t("connectTitle")}
      eyebrow={t("garminName")}
      labelId={labelId}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary disabled={!ready || redirecting} onClick={() => connect.mutate()}>
            {redirecting ? t("redirecting") : t("continue")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-5" data-testid="garmin-connect-sheet">
        <section className="flex flex-col gap-2">
          <SectionLabel>{t("bringTitle")}</SectionLabel>
          <PrefSwitches prefs={prefs} onToggle={(pref) => setPrefs((current) => togglePref(current, pref))} disabled={redirecting} />
        </section>

        <section className="flex flex-col gap-2">
          <SectionLabel id={pastId}>{t("pastTitle")}</SectionLabel>
          <div role="radiogroup" aria-labelledby={pastId} className="flex flex-col gap-2 sm:flex-row">
            {backfillOptions(row).map((option) => (
              <ChoicePill key={option} selected={days === option} onSelect={() => setDays(option)}>
                {t(["backfill", String(option)].join("_"))}
              </ChoicePill>
            ))}
          </div>
          <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("backfillHint")}</p>
        </section>

        {consentShown ? (
          <label className="flex items-start gap-3 rounded-2xl p-3 text-sm" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
            <input
              type="checkbox"
              checked={consentTicked}
              onChange={(event) => setConsentTicked(event.target.checked)}
              className="mt-0.5 h-5 w-5 shrink-0"
            />
            <span>{t("consent")}</span>
          </label>
        ) : null}

        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("privateNote")}</p>
        <ErrorLine message={connect.isError ? t(deviceErrorKey(connect.error)) : null} />
      </div>
    </Sheet>
  );
}
