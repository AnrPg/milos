"use client";

import { useUiTranslations } from "@/i18n/ui";
import Link from "next/link";
import React, { useMemo, useState } from "react";

import type { ClassTimerCommand } from "@/api/class-timers";
import { FreeTextTimerFields } from "@/components/workouts/creation/FreeTextTimerFields";
import { useSession } from "@/components/session-provider";
import { formatClock } from "@/components/workouts/execution/TimerDisplay";
import { useClassTimer } from "@/hooks/useClassTimer";
import { useClassTimerCues } from "@/hooks/useClassTimerCues";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { type FreeTextTimerPreset, QUICK_PRESETS } from "@/lib/free-text-timer";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { segmentLabel } from "@/lib/segment-label";
import { type CueMode, primeCueAudio, readCueMode, storeCueMode } from "@/lib/timer-cues";
import { getFormatLabels } from "@/types/workout";

import { ClassTimerFace } from "./ClassTimerFace";

const COUNTDOWN_CHOICES = [0, 5, 10, 15];

/** The coach's remote: drives the class timer every screen in the room follows. */
export function ClassTimerControl({ slotId }: { slotId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const organizationSlug = useOrganizationSlug();
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);
  const timer = useClassTimer(tokens?.access_token, slotId);
  const [countdown, setCountdown] = useState(10);
  const [cueMode, setCueMode] = useState<CueMode>(() => readCueMode());
  const [presetDraft, setPresetDraft] = useState<FreeTextTimerPreset | null>(null);
  const [copied, setCopied] = useState(false);

  useScreenWakeLock(timer.position?.status === "running");
  useClassTimerCues(timer.position, cueMode);

  const displayHref = adminHref(`/class-timer/${slotId}/display`, organizationSlug);

  function run(command: ClassTimerCommand) {
    primeCueAudio();
    void timer.send(command);
  }

  async function copyDisplayLink() {
    try {
      await navigator.clipboard.writeText(new URL(displayHref, window.location.origin).toString());
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2_000);
    } catch {
      setCopied(false);
    }
  }

  if (!timer.payload) {
    return (
      <div className="flex min-h-dvh items-center justify-center px-6 text-center" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        {timer.loadError ? i18n("classTimerUnavailable") : i18n("kpiLoading")}
      </div>
    );
  }

  const { payload, position } = timer;
  const status = position?.status ?? payload.timer.status;
  const between = status === "ready" || status === "finished";
  const current = position?.segment ?? null;
  const adjustable =
    current && typeof current.duration_seconds === "number" && (current.kind === "countdown" || current.kind === "countup");
  const problemText =
    timer.problem === "conflict"
      ? i18n("classTimerConflict")
      : timer.problem === "forbidden"
        ? i18n("classTimerForbidden")
        : timer.problem === "rejected"
          ? i18n("classTimerRejected")
          : timer.problem === "offline"
            ? i18n("classTimerOffline")
            : null;

  return (
    <main className="min-h-dvh px-4 py-6" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <div className="mx-auto max-w-3xl space-y-5">
        <header className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-bold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
              {i18n("classTimerRemoteTitle")}
            </p>
            <h1 className="truncate text-2xl font-black">{payload.workout?.title ?? payload.class.name}</h1>
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              {payload.class.name} · {timer.connected ? i18n("classTimerLive") : i18n("classTimerReconnecting")}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Link
              href={displayHref}
              target="_blank"
              className="min-h-11 rounded-xl px-3 py-2.5 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {i18n("classTimerDisplayLink")}
            </Link>
            <button type="button" onClick={() => void copyDisplayLink()} className="min-h-11 rounded-xl px-3 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>
              {copied ? i18n("classTimerLinkCopied") : i18n("classTimerCopyLink")}
            </button>
            <button
              type="button"
              onClick={() => {
                const next: CueMode = cueMode === "off" ? "sound" : "off";
                setCueMode(next);
                storeCueMode(next);
                primeCueAudio();
              }}
              className="min-h-11 rounded-xl px-3 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              {cueMode === "off" ? i18n("classTimerSoundOff") : i18n("classTimerSoundOn")}
            </button>
          </div>
        </header>

        <section className="rounded-3xl border p-5" style={{ borderColor: "var(--border)", background: "var(--panel)" }}>
          <ClassTimerFace payload={payload} position={position} size="panel" />
        </section>

        {problemText ? (
          <p role="alert" className="rounded-2xl px-4 py-3 text-sm" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", color: "var(--text)" }}>
            {problemText}
          </p>
        ) : null}

        {payload.segments.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("classTimerChoosePreset")}</p>
        ) : null}

        <section className="grid grid-cols-2 gap-3 sm:grid-cols-4" aria-label={i18n("classTimerControlsLabel")}>
          {between ? (
            <button
              type="button"
              disabled={timer.sending || payload.segments.length === 0}
              onClick={() => run({ command: "start", countdown_seconds: countdown })}
              className="col-span-2 min-h-16 rounded-2xl text-xl font-black disabled:opacity-40 sm:col-span-4"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {status === "finished" ? i18n("classTimerStartAgain") : i18n("start952f375")}
            </button>
          ) : status === "running" ? (
            <button type="button" disabled={timer.sending} onClick={() => run({ command: "pause" })} className="col-span-2 min-h-16 rounded-2xl text-xl font-black disabled:opacity-40 sm:col-span-4" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {i18n("pausecd21a1b")}
            </button>
          ) : (
            <button type="button" disabled={timer.sending} onClick={() => run({ command: "resume" })} className="col-span-2 min-h-16 rounded-2xl text-xl font-black disabled:opacity-40 sm:col-span-4" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {i18n("resumeb3bd0b5")}
            </button>
          )}

          <ControlButton label={i18n("backc32ae9f")} disabled={timer.sending || between} onClick={() => run({ command: "previous" })} />
          <ControlButton label={i18n("nextbc98198")} disabled={timer.sending || between} onClick={() => run({ command: "next" })} />
          <ControlButton label={i18n("minusThirtySecondsLabel")} disabled={timer.sending || between || !adjustable} onClick={() => run({ command: "adjust", delta_seconds: -30 })} />
          <ControlButton label={i18n("plusThirtySecondsLabel")} disabled={timer.sending || between || !adjustable} onClick={() => run({ command: "adjust", delta_seconds: 30 })} />
          <ControlButton label={i18n("classTimerFinish")} disabled={timer.sending || between} onClick={() => run({ command: "finish" })} />
          <ControlButton label={i18n("classTimerReset")} disabled={timer.sending || status === "ready"} onClick={() => run({ command: "reset" })} />
        </section>

        {between ? (
          <section className="rounded-3xl border p-5" style={{ borderColor: "var(--border)", background: "var(--panel)" }}>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-base font-black">{i18n("classTimerGetReadyLabel")}</h2>
              <div role="group" aria-label={i18n("classTimerGetReadyLabel")} className="flex gap-1">
                {COUNTDOWN_CHOICES.map((seconds) => (
                  <button
                    key={seconds}
                    type="button"
                    aria-pressed={countdown === seconds}
                    onClick={() => setCountdown(seconds)}
                    className="min-h-10 rounded-full px-3 text-sm font-semibold tabular-nums"
                    style={
                      countdown === seconds
                        ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                        : { border: "1px solid var(--border)", color: "var(--text-soft)" }
                    }
                  >
                    {formatClock(seconds)}
                  </button>
                ))}
              </div>
            </div>

            <h2 className="mt-5 text-base font-black">{i18n("classTimerPresetTitle")}</h2>
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{i18n("classTimerPresetHint")}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              {QUICK_PRESETS.map((quick) => (
                <button
                  key={quick.id}
                  type="button"
                  onClick={() => setPresetDraft(quick.preset)}
                  className="min-h-10 rounded-full px-3 text-sm font-semibold"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                >
                  {i18n(`timerPreset_${quick.id}`)}
                </button>
              ))}
            </div>
            {presetDraft ? (
              <>
                <FreeTextTimerFields preset={presetDraft} formatLabels={formatLabels} onChange={setPresetDraft} />
                <button
                  type="button"
                  disabled={timer.sending}
                  onClick={() => run({ command: "configure", timer_preset: presetDraft })}
                  className="mt-4 min-h-11 rounded-xl px-4 text-sm font-bold disabled:opacity-40"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {i18n("classTimerUsePreset")}
                </button>
              </>
            ) : null}
            {payload.timer.timer_preset && payload.workout ? (
              <button
                type="button"
                disabled={timer.sending}
                onClick={() => run({ command: "configure", timer_preset: null })}
                className="ms-2 mt-4 min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-40"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("classTimerUseWorkout")}
              </button>
            ) : null}
          </section>
        ) : null}

        {payload.segments.length > 1 ? (
          <section className="rounded-3xl border p-5" style={{ borderColor: "var(--border)", background: "var(--panel)" }}>
            <h2 className="text-base font-black">{i18n("classTimerJumpTitle")}</h2>
            <ol className="mt-3 max-h-80 space-y-1 overflow-y-auto">
              {payload.segments.map((segment, index) => {
                const active = position?.index === index && !between;
                return (
                  <li key={segment.segment_key}>
                    <button
                      type="button"
                      disabled={timer.sending}
                      aria-current={active || undefined}
                      onClick={() => run({ command: "jump", index })}
                      className="flex min-h-11 w-full items-center justify-between gap-3 rounded-xl px-3 text-start text-sm disabled:opacity-40"
                      style={active ? { background: "color-mix(in srgb, var(--primary) 18%, transparent)", fontWeight: 700 } : { color: "var(--text-soft)" }}
                    >
                      <span className="min-w-0 truncate">
                        {index + 1}. {segment.section_name ? `${segment.section_name} · ` : ""}
                        {segmentLabel(segment, i18n)}
                      </span>
                      {segment.duration_seconds ? <span className="shrink-0 font-mono tabular-nums">{formatClock(segment.duration_seconds)}</span> : null}
                    </button>
                  </li>
                );
              })}
            </ol>
          </section>
        ) : null}
      </div>
    </main>
  );
}

function ControlButton({ label, disabled, onClick }: { label: string; disabled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="min-h-14 rounded-2xl text-base font-bold disabled:opacity-30"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
    >
      {label}
    </button>
  );
}
