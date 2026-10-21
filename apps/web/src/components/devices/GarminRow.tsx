"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import type { ConnectedDevices } from "@/api/check-in";
import { DEVICE_SUMMARY_KEY, DEVICES_KEY, syncGarmin, updateGarmin, type GarminRow } from "@/api/devices";
import { JOURNAL_FEED_KEY } from "@/api/journal";
import { deviceErrorCode, deviceErrorKey, PrefSwitches, ProgressBar } from "@/components/devices/DeviceBits";
import { GarminConnectSheet } from "@/components/devices/GarminConnectSheet";
import { GarminDisconnectSheet } from "@/components/devices/GarminDisconnectSheet";
import {
  agoFrom,
  backfillPercent,
  enabledPrefs,
  formatPercent,
  fullPrefs,
  garminRowState,
  togglePref,
  type FullSyncPrefs,
} from "@/components/devices/garmin-model";

const PILL = {
  soon: { color: "var(--dim)", background: "var(--panel)" },
  disconnected: { color: "var(--text-soft)", background: "var(--panel)" },
  connected: { color: "var(--success)", background: "color-mix(in srgb, var(--success) 16%, transparent)" },
  reconnect: { color: "var(--danger)", background: "color-mix(in srgb, var(--danger) 16%, transparent)" },
} as const;

/** Swap the Garmin row inside the cached devices page. */
export function withGarminRow(current: ConnectedDevices | undefined, row: GarminRow): ConnectedDevices | undefined {
  if (!current) return current;
  return {
    ...current,
    integrations: current.integrations.map((integration) => (integration.provider === "garmin" ? { ...integration, ...row } : integration)),
  };
}

/**
 * Garmin's row on Συνδεδεμένες συσκευές (board 16 Q1, Q5, Q6 A): «Σύντομα»
 * without server credentials; «Σύνδεση» otherwise; once connected the last
 * sync, what syncs (editable), the history import, «Συγχρονισμός τώρα»,
 * the reconnect warning and «Αποσύνδεση».
 */
export function GarminRowItem({ row, token, onMessage }: { row: GarminRow; token: string; onMessage: (message: string) => void }) {
  const t = useTranslations("Devices");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [sheet, setSheet] = useState<"connect" | "reconnect" | "disconnect" | null>(null);
  const [editing, setEditing] = useState<FullSyncPrefs | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  // The server asks for the health-data consent when a change turns on sleep, weight or resting HR.
  const [askConsent, setAskConsent] = useState(false);
  const [consentTicked, setConsentTicked] = useState(false);
  const state = garminRowState(row);
  const connection = row.connection ?? null;

  function store(next: GarminRow) {
    queryClient.setQueryData<ConnectedDevices>(DEVICES_KEY, (current) => withGarminRow(current, next));
  }

  const sync = useMutation({
    mutationFn: () => syncGarmin(token),
    onSuccess: (next) => {
      store(next);
      setNotice(t("synced"));
    },
    onError: (error) => setNotice(t(deviceErrorKey(error))),
  });
  const save = useMutation({
    mutationFn: (prefs: FullSyncPrefs) => updateGarmin(token, prefs, askConsent && consentTicked),
    onSuccess: (next) => {
      store(next);
      setEditing(null);
      setAskConsent(false);
      setConsentTicked(false);
      setNotice(t("prefsSaved"));
    },
    onError: (error) => {
      if (deviceErrorCode(error) === "health_data_consent_required") setAskConsent(true);
      setNotice(t(deviceErrorKey(error)));
    },
  });

  const percent = backfillPercent(connection);
  const syncing = enabledPrefs(connection?.sync_prefs ?? row.sync_prefs);
  const lastSync = connection?.last_synced_at ? agoFrom(connection.last_synced_at) : null;

  return (
    <li className="flex flex-col gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }} data-testid="garmin-row">
      <div className="flex items-center justify-between gap-3">
        <span className="flex min-w-0 flex-col">
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("garminName")}</span>
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>
            {state === "soon" ? t("soonHint") : state === "disconnected" ? t("connectHint") : syncing.length ? syncing.map((pref) => t(["pref", pref].join("_"))).join(", ") : t("nothingSyncs")}
          </span>
        </span>
        {state === "disconnected" ? (
          <button
            type="button"
            onClick={() => setSheet("connect")}
            className="min-h-11 shrink-0 rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {t("connect")}
          </button>
        ) : (
          <span className="shrink-0 rounded-full px-3 py-1 text-xs font-bold" style={PILL[state]}>
            {t(["state", state].join("_"))}
          </span>
        )}
      </div>

      {state === "connected" || state === "reconnect" ? (
        <>
          <p className="text-xs" style={{ color: "var(--text-soft)" }} data-testid="garmin-last-sync">
            {lastSync ? t(["lastSync", lastSync.unit].join("_"), { count: lastSync.count }) : t("lastSync_never")}
          </p>
          {percent !== null ? <ProgressBar percent={percent} label={t("importing", { percent: formatPercent(percent, locale) })} /> : null}

          {state === "reconnect" ? (
            <div role="alert" className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "color-mix(in srgb, var(--danger) 10%, var(--panel))", border: "1px solid var(--danger)" }}>
              <p className="text-sm" style={{ color: "var(--text)" }}>{t("reconnectWarning")}</p>
              <button
                type="button"
                onClick={() => setSheet("reconnect")}
                className="min-h-11 self-start rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--primary)", color: "var(--bg)" }}
              >
                {t("reconnect")}
              </button>
            </div>
          ) : null}

          {editing ? (
            <div className="flex flex-col gap-2" data-testid="garmin-prefs">
              <PrefSwitches prefs={editing} onToggle={(pref) => setEditing((current) => (current ? togglePref(current, pref) : current))} disabled={save.isPending} />
              {askConsent ? (
                <label className="flex items-start gap-3 rounded-2xl p-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
                  <input type="checkbox" checked={consentTicked} onChange={(event) => setConsentTicked(event.target.checked)} className="mt-0.5 h-5 w-5 shrink-0" />
                  <span>{t("consent")}</span>
                </label>
              ) : null}
              <div className="flex flex-wrap gap-2">
                <button type="button" onClick={() => { setEditing(null); setAskConsent(false); }} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                  {t("cancel")}
                </button>
                <button
                  type="button"
                  disabled={save.isPending || (askConsent && !consentTicked)}
                  onClick={() => save.mutate(editing)}
                  className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
                  style={{ background: "var(--primary)", color: "var(--bg)" }}
                >
                  {t("save")}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap gap-2">
              {state === "connected" ? (
                <button
                  type="button"
                  disabled={sync.isPending}
                  onClick={() => sync.mutate()}
                  className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
                  style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {sync.isPending ? t("syncing") : t("syncNow")}
                </button>
              ) : null}
              <button
                type="button"
                onClick={() => setEditing(fullPrefs(connection?.sync_prefs ?? row.sync_prefs))}
                className="min-h-11 rounded-2xl px-4 text-sm font-bold"
                style={{ border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {t("editPrefs")}
              </button>
              <button
                type="button"
                onClick={() => setSheet("disconnect")}
                className="min-h-11 rounded-2xl px-4 text-sm font-bold"
                style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
              >
                {t("disconnect")}
              </button>
            </div>
          )}
        </>
      ) : null}

      {notice ? <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>{notice}</p> : null}

      {sheet === "connect" || sheet === "reconnect" ? (
        <GarminConnectSheet token={token} row={row} reconnect={sheet === "reconnect"} onClose={() => setSheet(null)} />
      ) : null}
      {sheet === "disconnect" ? (
        <GarminDisconnectSheet
          token={token}
          onClose={() => setSheet(null)}
          onDone={(_result, deleted) => {
            setSheet(null);
            onMessage(deleted ? t("disconnectedDeleted") : t("disconnected"));
            void queryClient.invalidateQueries({ queryKey: DEVICES_KEY });
            void queryClient.invalidateQueries({ queryKey: DEVICE_SUMMARY_KEY });
            if (deleted) void queryClient.invalidateQueries({ queryKey: JOURNAL_FEED_KEY });
          }}
        />
      ) : null}
    </li>
  );
}
