"use client";

import { useUiTranslations } from "@/i18n/ui";
import React, { useEffect, useRef } from "react";

import { TimerNowPanel } from "@/components/class-timer/TimerNowPanel";
import type { TimerNow } from "@/lib/timer-now";

import { formatClock, PHASE_COLORS, type TimerPhase } from "./TimerDisplay";
import { useHideBottomNav } from "@/components/nav/bottom-nav-visibility";

type Props = {
  seconds: number;
  phase: TimerPhase;
  label: string;
  sectionName: string;
  /** e.g. "Round 4" or "Round 3 / 8"; null when the segment has no rounds. */
  roundText: string | null;
  nextText: string | null;
  finalSeconds: boolean;
  paused: boolean;
  /** What is done now (this window's exercises, the section's text), shown under the clock. */
  now?: TimerNow | null;
  onExit: () => void;
};

/**
 * Gym-display mode: the clock fills the screen so it reads from across the
 * room (a phone propped against a wall, or a laptop cast to a TV). It asks for
 * fullscreen and landscape where the browser allows, and any tap exits.
 */
export function CastView({ seconds, phase, label, sectionName, roundText, nextText, finalSeconds, paused, now = null, onExit }: Props) {
  // A full-screen surface: the member app's bottom bar steps aside.
  useHideBottomNav();
  const i18n = useUiTranslations();
  const rootRef = useRef<HTMLDivElement>(null);
  const color = PHASE_COLORS[phase];
  const phaseLabel =
    phase === "rest" ? i18n("restPhaseLabel") : phase === "transition" ? i18n("transitionPhaseLabel") : i18n("workPhaseLabel");

  useEffect(() => {
    const element = rootRef.current;
    let enteredFullscreen = false;
    if (element?.requestFullscreen && !document.fullscreenElement) {
      element
        .requestFullscreen()
        .then(() => {
          enteredFullscreen = true;
          const orientation = screen.orientation as ScreenOrientation & { lock?: (o: string) => Promise<void> };
          return orientation.lock?.("landscape");
        })
        .catch(() => undefined);
    }

    const onFullscreenChange = () => {
      if (enteredFullscreen && !document.fullscreenElement) onExit();
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onExit();
    };
    document.addEventListener("fullscreenchange", onFullscreenChange);
    window.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("fullscreenchange", onFullscreenChange);
      window.removeEventListener("keydown", onKey);
      if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined);
    };
  }, [onExit]);

  return (
    <div
      ref={rootRef}
      role="dialog"
      aria-modal="true"
      aria-label={i18n("castModeLabel")}
      onClick={onExit}
      className="fixed inset-0 z-(--z-fullscreen) flex cursor-pointer flex-col items-center justify-center gap-[2vmin] p-[3vmin]"
      style={{ background: `color-mix(in srgb, ${color} 22%, var(--bg))`, color: "var(--text)" }}
    >
      <div className="absolute start-[3vmin] top-[3vmin] max-w-[45vw] truncate font-semibold" style={{ fontSize: "clamp(1rem, 3.2vmin, 2.5rem)", color: "var(--text-soft)" }}>
        {sectionName}
      </div>
      {roundText ? (
        <div className="absolute end-[3vmin] top-[3vmin] font-bold tabular-nums" style={{ fontSize: "clamp(1.25rem, 5vmin, 4rem)" }}>
          {roundText}
        </div>
      ) : null}

      <div className="font-bold uppercase tracking-widest" style={{ fontSize: "clamp(1.25rem, 5vmin, 4rem)", color }}>
        {paused ? i18n("pausedc7dfb6f") : phaseLabel}
      </div>
      <div
        role="timer"
        aria-live="off"
        className={`font-mono font-bold tabular-nums leading-none ${finalSeconds ? "motion-safe:animate-pulse" : ""}`}
        style={{ fontSize: seconds >= 3600 ? "min(24vw, 50vh)" : "min(34vw, 62vh)" }}
      >
        {formatClock(seconds)}
      </div>
      <div className="max-w-[90vw] truncate text-center font-semibold" style={{ fontSize: "clamp(1rem, 4vmin, 3rem)", color: "var(--text-soft)" }}>
        {label}
      </div>
      {now ? <TimerNowPanel now={now} size="wall" style={{ maxWidth: "90vw", maxHeight: "28vh", fontSize: "clamp(0.9rem, 3.2vmin, 2.25rem)" }} /> : null}
      {nextText ? (
        <div className="absolute bottom-[3vmin] max-w-[90vw] truncate" style={{ fontSize: "clamp(0.9rem, 3vmin, 2rem)", color: "var(--muted)" }}>
          {nextText}
        </div>
      ) : null}
      <span className="sr-only">{i18n("castModeExitHint")}</span>
    </div>
  );
}
