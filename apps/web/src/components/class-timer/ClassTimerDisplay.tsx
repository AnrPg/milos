"use client";

import { useUiTranslations } from "@/i18n/ui";
import Link from "next/link";
import React, { useRef, useState } from "react";

import { useSession } from "@/components/session-provider";
import { PHASE_COLORS } from "@/components/workouts/execution/TimerDisplay";
import { useClassTimer } from "@/hooks/useClassTimer";
import { useClassTimerCues } from "@/hooks/useClassTimerCues";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { type CueMode, primeCueAudio, readCueMode, storeCueMode } from "@/lib/timer-cues";

import { ClassTimerFace, phaseOf, SegmentExercises } from "./ClassTimerFace";

/**
 * The gym's wall display (and members' "follow the class" view): a giant
 * clock driven by the coach's remote. Keeps the screen awake, beeps for the
 * room once sound is enabled, and goes fullscreen on request.
 */
export function ClassTimerDisplay({ slotId }: { slotId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const organizationSlug = useOrganizationSlug();
  const { membershipRole } = useSelectedMembershipRole();
  const isStaff = membershipRole === "owner" || membershipRole === "admin" || membershipRole === "coach";
  const timer = useClassTimer(tokens?.access_token, slotId);
  const [cueMode, setCueMode] = useState<CueMode>(() => readCueMode());
  const [soundReady, setSoundReady] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useScreenWakeLock(Boolean(timer.payload));
  useClassTimerCues(soundReady ? timer.position : null, cueMode);

  function enableSound() {
    primeCueAudio();
    setSoundReady(true);
    if (cueMode === "off") {
      setCueMode("sound");
      storeCueMode("sound");
    }
  }

  function toggleSound() {
    const next: CueMode = cueMode === "off" ? "sound" : "off";
    setCueMode(next);
    storeCueMode(next);
    if (next !== "off") enableSound();
  }

  function toggleFullscreen() {
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined);
    else void rootRef.current?.requestFullscreen?.().catch(() => undefined);
  }

  if (!timer.payload) {
    return (
      <div className="flex h-dvh items-center justify-center px-6 text-center text-lg" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        {timer.loadError ? i18n("classTimerUnavailable") : i18n("kpiLoading")}
      </div>
    );
  }

  const { payload, position } = timer;
  const phase = phaseOf(position);
  const tint = position?.status === "running" ? PHASE_COLORS[phase] : "var(--muted)";
  const body = payload.workout?.free_text_body?.trim();

  return (
    <div
      ref={rootRef}
      className="relative flex h-dvh flex-col overflow-hidden"
      style={{ background: `color-mix(in srgb, ${tint} 16%, var(--bg))`, color: "var(--text)" }}
      onPointerDown={soundReady ? undefined : enableSound}
    >
      <header className="flex flex-wrap items-start justify-between gap-4 p-[2.5vmin]">
        <div className="min-w-0">
          <div className="truncate font-black" style={{ fontSize: "clamp(1rem, 3.4vmin, 2.75rem)" }}>
            {payload.workout?.title ?? payload.class.name}
          </div>
          <div className="truncate" style={{ color: "var(--muted)", fontSize: "clamp(0.8rem, 2.2vmin, 1.5rem)" }}>
            {payload.class.name}
          </div>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-2">
          <span
            role="status"
            aria-label={timer.connected ? i18n("classTimerLive") : i18n("classTimerReconnecting")}
            title={timer.connected ? i18n("classTimerLive") : i18n("classTimerReconnecting")}
            className="h-3 w-3 rounded-full"
            style={{ background: timer.connected ? "var(--spark)" : "var(--warning)", boxShadow: "0 0 0 1px var(--border-strong)" }}
          />
          <button type="button" onClick={toggleSound} className="min-h-11 rounded-xl px-3 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>
            {cueMode === "off" ? i18n("classTimerSoundOff") : i18n("classTimerSoundOn")}
          </button>
          <button type="button" onClick={toggleFullscreen} className="min-h-11 rounded-xl px-3 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>
            {i18n("classTimerFullscreen")}
          </button>
          {isStaff ? (
            <Link
              href={adminHref(`/class-timer/${slotId}/control`, organizationSlug)}
              className="min-h-11 rounded-xl px-3 py-2.5 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {i18n("classTimerRemoteLink")}
            </Link>
          ) : null}
        </div>
      </header>

      <main className="grid min-h-0 flex-1 grid-cols-1 items-center gap-[3vmin] px-[3vmin] pb-[3vmin] landscape:grid-cols-[minmax(0,1fr)_auto]">
        <ClassTimerFace payload={payload} position={position} size="wall" />
        {body || (position?.segment?.exercises?.length ?? 0) > 0 ? (
          <aside className="hidden max-w-[34vw] self-stretch overflow-hidden rounded-[2vmin] p-[2.5vmin] landscape:block" style={{ background: "color-mix(in srgb, var(--panel) 80%, transparent)" }}>
            {body ? (
              <pre className="whitespace-pre-wrap font-sans font-semibold leading-snug" style={{ fontSize: "clamp(0.9rem, 2.8vmin, 2.25rem)" }}>
                {body}
              </pre>
            ) : (
              <SegmentExercises position={position} />
            )}
          </aside>
        ) : null}
      </main>

      {payload.segments.length === 0 ? (
        <p className="absolute inset-x-0 bottom-[3vmin] text-center text-sm" style={{ color: "var(--muted)" }}>
          {i18n("classTimerNoTimer")}
        </p>
      ) : null}

      {!soundReady ? (
        <p className="absolute inset-x-0 bottom-[1.5vmin] text-center text-xs" style={{ color: "var(--muted)" }}>
          {i18n("classTimerTapForSound")}
        </p>
      ) : null}
    </div>
  );
}
