"use client";

import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import type { FullSyncPrefs, SyncPref } from "@/components/devices/garmin-model";
import { PREF_DESTINATION, SYNC_PREFS } from "@/components/devices/garmin-model";

/** API error codes of ADR-161 with their own wording in the Devices namespace. */
const CODES = [
  "health_data_consent_required",
  "device_already_connected",
  "garmin_not_configured",
  "garmin_unavailable",
  "device_not_connected",
  "device_reconnect_required",
  "sync_too_soon",
  "invalid_sync_prefs",
  "import_already_settled",
  "unknown_device_candidate",
  "device_confirmation_required",
] as const;

export function deviceErrorCode(error: unknown): string | null {
  return error instanceof ApiError ? (error.payload.code ?? null) : null;
}

/** The message key for an error: its own wording, «offline», or a generic line. */
export function deviceErrorKey(error: unknown): string {
  const code = deviceErrorCode(error);
  if (code && (CODES as readonly string[]).includes(code)) return ["error", code].join("_");
  if (error instanceof ApiError && error.status === 429) return "error_sync_too_soon";
  if (error instanceof TypeError) return "error_offline";
  return "error_generic";
}

/** One on/off row: «Προπονήσεις · Στο Ημερολόγιο». */
export function PrefSwitch({ pref, on, onToggle, disabled }: { pref: SyncPref; on: boolean; onToggle: () => void; disabled?: boolean }) {
  const t = useTranslations("Devices");
  const label = t(["pref", pref].join("_"));
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={onToggle}
      className="flex min-h-12 w-full items-center justify-between gap-3 rounded-2xl px-4 py-2 text-left disabled:opacity-50"
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
    >
      <span className="flex min-w-0 flex-col">
        <span className="text-sm font-bold">{label}</span>
        <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t(["dest", PREF_DESTINATION[pref]].join("_"))}</span>
      </span>
      <span
        aria-hidden="true"
        className="relative h-6 w-11 shrink-0 rounded-full transition-colors"
        style={{ background: on ? "var(--primary)" : "var(--border)" }}
      >
        <span
          className="absolute top-0.5 h-5 w-5 rounded-full transition-all"
          style={{ background: "var(--bg)", left: on ? "1.375rem" : "0.125rem" }}
        />
      </span>
    </button>
  );
}

export function PrefSwitches({ prefs, onToggle, disabled }: { prefs: FullSyncPrefs; onToggle: (pref: SyncPref) => void; disabled?: boolean }) {
  return (
    <div className="flex flex-col gap-2">
      {SYNC_PREFS.map((pref) => (
        <PrefSwitch key={pref} pref={pref} on={prefs[pref]} disabled={disabled} onToggle={() => onToggle(pref)} />
      ))}
    </div>
  );
}

export function SectionLabel({ children, id }: { children: ReactNode; id?: string }) {
  return (
    <p id={id} className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
      {children}
    </p>
  );
}

/** A thin bar with the history import's progress. */
export function ProgressBar({ percent, label }: { percent: number; label: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{label}</span>
      <div
        role="progressbar"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={percent}
        className="h-1.5 w-full overflow-hidden rounded-full"
        style={{ background: "var(--border)" }}
      >
        <div className="h-full rounded-full" style={{ width: `${percent}%`, background: "var(--primary)" }} />
      </div>
    </div>
  );
}
