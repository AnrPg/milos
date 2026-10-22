"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { ConnectedDevices } from "@/api/check-in";
import { DEVICES_KEY } from "@/api/devices";
import { disconnectPhoneHealth, updatePhoneHealth, type PhoneHealthRow } from "@/api/phone-health";
import { refreshAfterImport } from "@/components/devices/device-queries";
import { DeviceDisconnectSheet } from "@/components/devices/DeviceDisconnectSheet";
import { deviceErrorCode, deviceErrorKey, PrefSwitches } from "@/components/devices/DeviceBits";
import { agoFrom } from "@/components/devices/garmin-model";
import { PhoneHealthConnectSheet } from "@/components/devices/PhoneHealthConnectSheet";
import {
  canInstall,
  enabledPhonePrefs,
  fullPhonePrefs,
  PHONE_PREFS,
  phoneRowState,
  togglePhonePref,
  unavailableKey,
  withPhoneRow,
  type FullPhonePrefs,
} from "@/components/devices/phone-health-model";
import { grantedPrefs, healthPlugin, newCount, syncPhoneHealth } from "@/lib/platform/health";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

const PILL = {
  connected: SPARK_ACTIVE_STYLE,
  unavailable: { color: "var(--dim)", background: "var(--panel)" },
} as const;

const SECONDARY = { border: "1px solid var(--border)", color: "var(--text)" } as const;

export const HEALTH_AVAILABILITY_KEY = ["platform", "health-availability"] as const;

/**
 * Apple Health or Health Connect on Συνδεδεμένες συσκευές (ADR-172). In the
 * app on this phone: «Σύνδεση» (or why it can't), then the last sync, what
 * syncs, «Συγχρονισμός τώρα» and «Αποσύνδεση». Anywhere else, a connected
 * row says it syncs from the app and can still change choices or disconnect.
 */
export function PhoneHealthRowItem({
  row,
  token,
  inApp,
  onMessage,
}: {
  row: PhoneHealthRow;
  token: string;
  inApp: boolean;
  onMessage: (message: string) => void;
}) {
  const t = useTranslations("Devices");
  const queryClient = useQueryClient();
  const provider = t(["provider", row.provider].join("_"));
  const [sheet, setSheet] = useState<"connect" | "disconnect" | null>(null);
  const [editing, setEditing] = useState<FullPhonePrefs | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [askConsent, setAskConsent] = useState(false);
  const [consentTicked, setConsentTicked] = useState(false);
  const availability = useQuery({
    queryKey: HEALTH_AVAILABILITY_KEY,
    enabled: inApp,
    queryFn: async () => (await healthPlugin()).availability(),
    staleTime: Infinity,
    retry: false,
  });
  const state = phoneRowState(row, inApp, availability.data);
  const prefs = fullPhonePrefs(row.connection?.sync_prefs ?? row.sync_prefs);
  const syncing = enabledPhonePrefs(prefs);
  const lastSync = row.connection?.last_synced_at ? agoFrom(row.connection.last_synced_at) : null;

  function store(next: PhoneHealthRow) {
    queryClient.setQueryData<ConnectedDevices>(DEVICES_KEY, (current) => withPhoneRow(current, next));
  }

  const sync = useMutation({
    mutationFn: () => syncPhoneHealth(token, row),
    onSuccess: (result) => {
      if (result.row) store(result.row);
      const count = newCount(result.counts);
      if (count) refreshAfterImport(queryClient);
      setNotice(t("phoneSynced", { count }));
    },
    onError: () => setNotice(t("phoneSyncFailed")),
  });

  const save = useMutation({
    mutationFn: async (next: FullPhonePrefs) => {
      let chosen = next;
      // Newly chosen kinds need the phone's permission first.
      const added = enabledPhonePrefs(next).filter((pref) => !prefs[pref]);
      if (inApp && added.length) chosen = grantedPrefs(next, await (await healthPlugin()).requestAuthorization({ kinds: enabledPhonePrefs(next) }));
      return updatePhoneHealth(token, row.provider, chosen, askConsent && consentTicked);
    },
    onSuccess: (next) => {
      store(next);
      setEditing(null);
      setAskConsent(false);
      setConsentTicked(false);
      setNotice(t("phonePrefsSaved"));
    },
    onError: (error) => {
      if (deviceErrorCode(error) === "health_data_consent_required") setAskConsent(true);
      setNotice(t(deviceErrorKey(error)));
    },
  });

  const install = useMutation({ mutationFn: async () => (await healthPlugin()).openInstaller?.() });

  const hint =
    state === "connect"
      ? t("phoneConnectHint")
      : state === "unavailable"
        ? t(unavailableKey(availability.data))
        : syncing.length
          ? syncing.map((pref) => t(["pref", pref].join("_"))).join(", ")
          : t("nothingSyncs");

  return (
    <li className="flex flex-col gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }} data-testid={`phone-health-row-${row.provider}`}>
      <div className="flex items-center justify-between gap-3">
        <span className="flex min-w-0 flex-col">
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{provider}</span>
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>{hint}</span>
        </span>
        {state === "connect" ? (
          <button
            type="button"
            disabled={availability.isPending}
            onClick={() => setSheet("connect")}
            className="min-h-11 shrink-0 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("connect")}
          </button>
        ) : state === "unavailable" ? (
          canInstall(availability.data) ? (
            <button type="button" onClick={() => install.mutate()} className="min-h-11 shrink-0 rounded-2xl px-4 text-sm font-bold" style={SECONDARY}>
              {t("phoneInstall")}
            </button>
          ) : (
            <span className="shrink-0 rounded-full px-3 py-1 text-xs font-bold" style={PILL.unavailable}>{t("phoneUnavailable")}</span>
          )
        ) : (
          <span className="shrink-0 rounded-full px-3 py-1 text-xs font-bold" style={PILL.connected}>{t("state_connected")}</span>
        )}
      </div>

      {state === "connected" || state === "remote" ? (
        <>
          <p className="text-xs" style={{ color: "var(--text-soft)" }} data-testid="phone-health-last-sync">
            {lastSync ? t(["lastSync", lastSync.unit].join("_"), { count: lastSync.count }) : t("lastSync_never")}
            {state === "remote" ? ` · ${t("phoneSyncsInApp")}` : null}
          </p>

          {editing ? (
            <div className="flex flex-col gap-2" data-testid="phone-health-prefs">
              <PrefSwitches keys={PHONE_PREFS} prefs={editing} onToggle={(pref) => setEditing((current) => (current ? togglePhonePref(current, pref) : current))} disabled={save.isPending} />
              {askConsent ? (
                <label className="flex items-start gap-3 rounded-2xl p-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
                  <input type="checkbox" checked={consentTicked} onChange={(event) => setConsentTicked(event.target.checked)} className="mt-0.5 h-5 w-5 shrink-0" />
                  <span>{t("phoneConsent")}</span>
                </label>
              ) : null}
              <div className="flex flex-wrap gap-2">
                <button type="button" onClick={() => { setEditing(null); setAskConsent(false); }} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={SECONDARY}>
                  {t("cancel")}
                </button>
                <button
                  type="button"
                  disabled={save.isPending || (askConsent && !consentTicked)}
                  onClick={() => save.mutate(editing)}
                  className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {t("save")}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap gap-2">
              {state === "connected" ? (
                <button type="button" disabled={sync.isPending} onClick={() => sync.mutate()} className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50" style={SECONDARY}>
                  {sync.isPending ? t("syncing") : t("syncNow")}
                </button>
              ) : null}
              <button type="button" onClick={() => setEditing(prefs)} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={SECONDARY}>
                {t("editPrefs")}
              </button>
              <button type="button" onClick={() => setSheet("disconnect")} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--danger)" }}>
                {t("disconnect")}
              </button>
            </div>
          )}
        </>
      ) : null}

      {notice ? <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>{notice}</p> : null}

      {sheet === "connect" ? (
        <PhoneHealthConnectSheet
          token={token}
          row={row}
          onClose={() => setSheet(null)}
          onConnected={(next) => {
            setSheet(null);
            store(next);
            onMessage(t("phoneConnected", { provider }));
            // The last 30 days come in right away.
            void syncPhoneHealth(token, next)
              .then((result) => {
                if (result.row) store(result.row);
                if (newCount(result.counts)) refreshAfterImport(queryClient);
              })
              .catch(() => setNotice(t("phoneSyncFailed")));
          }}
        />
      ) : null}
      {sheet === "disconnect" ? (
        <DeviceDisconnectSheet
          copy={{
            eyebrow: provider,
            title: t("phoneDisconnectTitle", { provider }),
            deleteLabel: t("phoneDisconnectDelete", { provider }),
            deleteHint: t("phoneDisconnectDeleteHint", { provider }),
            confirmKeep: t("phoneDisconnectConfirmKeep", { provider }),
            confirmDelete: t("phoneDisconnectConfirmDelete", { provider }),
          }}
          disconnect={(deleteData) => disconnectPhoneHealth(token, row.provider, deleteData)}
          onClose={() => setSheet(null)}
          onDone={(_result, deleted) => {
            setSheet(null);
            onMessage(deleted ? t("phoneDisconnectedDeleted", { provider }) : t("phoneDisconnected", { provider }));
            void queryClient.invalidateQueries({ queryKey: DEVICES_KEY });
            if (deleted) refreshAfterImport(queryClient);
          }}
          testId="phone-health-disconnect-sheet"
          confirmTestId="phone-health-disconnect-confirm"
        />
      ) : null}
    </li>
  );
}
