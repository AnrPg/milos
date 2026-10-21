"use client";

import { useId, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BODY_CONSENTS_KEY, fetchHealthConsents } from "@/api/body";
import { connectPhoneHealth, type PhoneHealthRow } from "@/api/phone-health";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { deviceErrorCode, deviceErrorKey, PrefSwitches, SectionLabel } from "@/components/devices/DeviceBits";
import {
  bringsPhoneHealthData,
  enabledPhonePrefs,
  fullPhonePrefs,
  PHONE_PREFS,
  togglePhonePref,
  type FullPhonePrefs,
} from "@/components/devices/phone-health-model";
import { grantedPrefs, healthPlugin } from "@/lib/platform/health";

/** The person refused every kind in the phone's own permission sheet. */
class AccessRefused extends Error {}

/**
 * «Σύνδεση» for Apple Health or Health Connect (ADR-172), the Garmin sheet's
 * pattern: what to bring in (each on), the health-data consent when it is
 * needed, then the phone's own permission sheet. The last 30 days come in
 * right after, then whatever is new each time the app opens.
 */
export function PhoneHealthConnectSheet({
  token,
  row,
  onClose,
  onConnected,
}: {
  token: string;
  row: PhoneHealthRow;
  onClose: () => void;
  onConnected: (row: PhoneHealthRow) => void;
}) {
  const t = useTranslations("Devices");
  const provider = t(["provider", row.provider].join("_"));
  const labelId = useId();
  const [prefs, setPrefs] = useState<FullPhonePrefs>(() => fullPhonePrefs(row.sync_prefs));
  const [consentTicked, setConsentTicked] = useState(false);
  const [serverAsked, setServerAsked] = useState(false);
  const consents = useQuery({ queryKey: BODY_CONSENTS_KEY, enabled: Boolean(token), queryFn: () => fetchHealthConsents(token) });
  const consented = Boolean(consents.data?.some((consent) => consent.scope === "health_data" && consent.active));
  const consentShown = !consented && (serverAsked || bringsPhoneHealthData(prefs));

  const connect = useMutation({
    mutationFn: async () => {
      const plugin = await healthPlugin();
      const authorization = await plugin.requestAuthorization({ kinds: enabledPhonePrefs(prefs) });
      const chosen = grantedPrefs(prefs, authorization);
      if (!enabledPhonePrefs(chosen).length) throw new AccessRefused();
      return connectPhoneHealth(token, row.provider, chosen, consentShown && consentTicked);
    },
    onSuccess: onConnected,
    onError: (error) => {
      if (deviceErrorCode(error) === "health_data_consent_required") setServerAsked(true);
    },
  });
  const ready = enabledPhonePrefs(prefs).length > 0 && (!consentShown || consentTicked) && !consents.isPending;
  const error = connect.isError ? (connect.error instanceof AccessRefused ? t("phoneDenied") : t(deviceErrorKey(connect.error))) : null;

  return (
    <Sheet
      title={t("phoneConnectTitle", { provider })}
      eyebrow={provider}
      labelId={labelId}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary disabled={!ready || connect.isPending} onClick={() => connect.mutate()}>
            {connect.isPending ? t("phoneAsking") : t("phoneContinue")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-5" data-testid="phone-health-connect-sheet">
        <section className="flex flex-col gap-2">
          <SectionLabel>{t("bringTitle")}</SectionLabel>
          <PrefSwitches keys={PHONE_PREFS} prefs={prefs} onToggle={(pref) => setPrefs((current) => togglePhonePref(current, pref))} disabled={connect.isPending} />
          <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("phoneHistoryHint", { days: row.history_days ?? 30 })}</p>
        </section>

        {consentShown ? (
          <label className="flex items-start gap-3 rounded-2xl p-3 text-sm" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
            <input type="checkbox" checked={consentTicked} onChange={(event) => setConsentTicked(event.target.checked)} className="mt-0.5 h-5 w-5 shrink-0" />
            <span>{t("phoneConsent")}</span>
          </label>
        ) : null}

        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("phonePrivateNote")}</p>
        <ErrorLine message={error} />
      </div>
    </Sheet>
  );
}
