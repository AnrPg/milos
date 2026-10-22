"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchAdminSettings, updateTimeZone, type TimeZoneStatus } from "@/api/settings";
import { deviceTimeZone } from "@/hooks/useReportGymTimeZone";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

const QUERY_KEY = ["admin", "time-zone"];

/** Every IANA zone the browser knows, with the given ones kept even if it doesn't. */
function zoneOptions(...always: Array<string | null | undefined>) {
  let zones: string[] = [];
  try {
    zones = (Intl as unknown as { supportedValuesOf?: (key: string) => string[] }).supportedValuesOf?.("timeZone") ?? [];
  } catch {
    zones = [];
  }
  return Array.from(new Set([...always.filter((zone): zone is string => Boolean(zone)), ...zones])).sort();
}

/**
 * ADR-176: the gym's time zone. Class days, the 07:00 missing-WOD alert,
 * check-in days and event times follow it. A guess from a staff device shows
 * as such until an admin confirms it.
 */
export function GymTimeZoneSetting({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const query = useQuery({
    queryKey: QUERY_KEY,
    queryFn: async () => (await fetchAdminSettings(token)).time_zone ?? null,
  });
  const [draft, setDraft] = useState<string | null>(null);
  const current = query.data;
  const device = deviceTimeZone();
  const value = draft ?? current?.timezone ?? device ?? "";
  const options = useMemo(() => zoneOptions(current?.timezone, device), [current?.timezone, device]);

  const mutation = useMutation({
    mutationFn: (timezone: string) => updateTimeZone(token, { timezone, source: "confirmed" }),
    onSuccess: (status: TimeZoneStatus) => {
      queryClient.setQueryData(QUERY_KEY, status);
      void queryClient.invalidateQueries({ queryKey: ["admin-onboarding"] });
      setDraft(null);
    },
  });

  if (query.isError) {
    return <p className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(query.error, i18n)}</p>;
  }

  if (query.isLoading) {
    return <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>;
  }

  const status = !current?.source ? "unset" : current.confirmed ? "confirmed" : "inferred";
  const changed = value !== current?.timezone || !current?.confirmed;

  return (
    <div className="space-y-4">
      <p
        className="rounded-2xl px-4 py-3 text-sm"
        role="status"
        style={
          status === "confirmed"
            ? { background: "var(--panel-muted)", color: "var(--text-soft)" }
            : {
                background: "color-mix(in srgb, var(--warning) 12%, transparent)",
                border: "1px solid color-mix(in srgb, var(--warning) 35%, transparent)",
                color: "var(--text)",
              }
        }
      >
        {status === "confirmed"
          ? i18n("gymTimeZoneConfirmed", { zone: current?.timezone ?? "" })
          : status === "inferred"
            ? i18n("gymTimeZoneInferred", { zone: current?.timezone ?? "" })
            : i18n("gymTimeZoneUnset", { zone: current?.timezone ?? "" })}
      </p>

      <label className="block space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
        <span>{i18n("gymTimeZoneLabel")}</span>
        <select
          className="w-full rounded-2xl px-4 py-3 outline-none"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={value}
          onChange={(event) => setDraft(event.target.value)}
        >
          {options.map((zone) => (
            <option key={zone} value={zone}>
              {zone}
            </option>
          ))}
        </select>
        <span className="block text-xs font-normal" style={{ color: "var(--dim)" }}>{i18n("gymTimeZoneHint")}</span>
      </label>

      {mutation.isError ? (
        <p className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(mutation.error, i18n)}</p>
      ) : null}

      <div className="flex justify-end">
        <button
          type="button"
          disabled={!value || !changed || mutation.isPending}
          className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          onClick={() => mutation.mutate(value)}
        >
          {mutation.isPending ? i18n("gymTimeZoneSaving") : i18n("gymTimeZoneConfirm")}
        </button>
      </div>
    </div>
  );
}
