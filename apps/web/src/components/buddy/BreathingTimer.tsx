"use client";

import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { BREATHING_SECONDS, breathingState, clock, key } from "./buddy-model";

/**
 * Two minutes of calm breathing (board 15 q5 A): a circle that grows on the
 * in-breath and shrinks on the out-breath, the words for each phase in a
 * polite live region, and the time left. With reduced motion the circle
 * stays still and the words carry it.
 */
export function BreathingTimer({ seconds = BREATHING_SECONDS, onDone }: { seconds?: number; onDone?: () => void }) {
  const t = useTranslations("Buddy");
  const [running, setRunning] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const startedAt = useRef<number | null>(null);
  const base = useRef(0);
  const doneCalled = useRef(false);
  const state = breathingState(elapsed, seconds);

  useEffect(() => {
    if (!running) return;
    startedAt.current = performance.now();
    const timer = setInterval(() => {
      const now = performance.now();
      const next = base.current + (now - (startedAt.current ?? now)) / 1000;
      setElapsed(Math.min(next, seconds));
    }, 100);
    return () => {
      clearInterval(timer);
      base.current += (performance.now() - (startedAt.current ?? performance.now())) / 1000;
      startedAt.current = null;
    };
  }, [running, seconds]);

  useEffect(() => {
    if (!state.done || doneCalled.current) return;
    doneCalled.current = true;
    const frame = requestAnimationFrame(() => {
      setRunning(false);
      onDone?.();
    });
    return () => cancelAnimationFrame(frame);
  }, [onDone, state.done]);

  function reset() {
    setRunning(false);
    base.current = 0;
    doneCalled.current = false;
    setElapsed(0);
  }

  const size = 72 + state.scale * 56;
  const phaseText = state.done ? t("breathDone") : running || elapsed > 0 ? t(key("breath", state.phase)) : t("breathReady");

  return (
    <div className="flex flex-col items-center gap-3 rounded-2xl p-4" style={{ background: "var(--panel-raised)" }} data-testid="breathing-timer">
      <div className="flex h-36 w-36 items-center justify-center" aria-hidden="true">
        <span
          className="block rounded-full motion-safe:transition-[width,height] motion-safe:duration-100 motion-reduce:!h-24 motion-reduce:!w-24"
          style={{ width: size, height: size, background: "color-mix(in srgb, var(--primary) 30%, transparent)", border: "2px solid var(--primary)" }}
        />
      </div>
      <p className="text-lg font-bold" aria-live="polite" style={{ color: "var(--text)" }} data-testid="breath-phase">{phaseText}</p>
      <p role="timer" aria-label={t("breathLeft", { time: clock(state.remaining) })} className="text-sm tabular-nums" style={{ color: "var(--dim)" }}>
        {clock(state.remaining)}
      </p>
      <div className="flex gap-2">
        {state.done ? (
          <button type="button" onClick={reset} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("breathAgain")}
          </button>
        ) : (
          <button
            type="button"
            onClick={() => setRunning(!running)}
            className="min-h-11 rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {running ? t("breathPause") : elapsed > 0 ? t("breathResume") : t("breathStart")}
          </button>
        )}
        {elapsed > 0 && !state.done ? (
          <button type="button" onClick={reset} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("breathStop")}
          </button>
        ) : null}
      </div>
    </div>
  );
}
