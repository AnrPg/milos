"use client";

import { useEffect, useEffectEvent, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { createVoiceDraft, type VoiceDraftResponse } from "@/api/voice-log";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { createBrowserVoiceRecorder, type VoiceRecorder } from "@/lib/platform/voice-recorder";

import { elapsedLabel, voiceErrorKey, type VoiceErrorKey } from "./voice-log-model";

type Phase = { name: "idle" } | { name: "recording"; startedAt: number } | { name: "working" } | { name: "error"; key: VoiceErrorKey };

/**
 * «Με φωνή» (ADR-175): one button records, the same button stops (or the
 * time limit does), then the clip becomes a draft. The draft opens in the
 * normal log form for review: nothing is saved from here, and the audio is
 * never kept.
 */
export function VoiceLogSheet({
  token,
  maxSeconds,
  onDraft,
  onClose,
  recorderFactory = createBrowserVoiceRecorder,
  submit = createVoiceDraft,
}: {
  token: string;
  maxSeconds: number;
  onDraft: (result: VoiceDraftResponse) => void;
  onClose: () => void;
  recorderFactory?: () => VoiceRecorder;
  /** Sends the clip (the API by default; a fake in tests). */
  submit?: typeof createVoiceDraft;
}) {
  const t = useTranslations("VoiceLog");
  const locale = useUiLocale();
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const recorderRef = useRef<VoiceRecorder | null>(null);
  const [phase, setPhase] = useState<Phase>({ name: "idle" });
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => () => recorderRef.current?.cancel(), []);

  const recording = phase.name === "recording";
  const startedAt = recording ? phase.startedAt : 0;

  async function stop() {
    const recorder = recorderRef.current;
    if (!recorder) return;
    recorderRef.current = null;
    setPhase({ name: "working" });
    try {
      const clip = await recorder.stop();
      const result = await submit(token, {
        audio_base64: clip.audioBase64,
        mime_type: clip.mimeType,
        duration_ms: clip.durationMs,
        locale,
      });
      onDraft(result);
    } catch (error) {      setPhase({ name: "error", key: voiceErrorKey(error) });
    }
  }

  const tick = useEffectEvent(() => {
    const current = Date.now();
    setNow(current);
    if (current - startedAt >= maxSeconds * 1000) void stop();
  });

  useEffect(() => {
    if (!recording) return;
    const timer = window.setInterval(() => tick(), 250);
    return () => window.clearInterval(timer);
  }, [recording]);

  async function start() {
    const recorder = recorderFactory();
    try {
      await recorder.start();
      recorderRef.current = recorder;
      const current = Date.now();
      setNow(current);
      setPhase({ name: "recording", startedAt: current });
    } catch (error) {
      recorder.cancel();
      setPhase({ name: "error", key: voiceErrorKey(error) });
    }
  }

  const elapsed = recording ? now - startedAt : 0;
  // These cannot be fixed by trying again from here.
  const blocked = phase.name === "error" && ["unsupported", "off", "dailyLimit"].includes(phase.key);

  return (
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center sm:items-center"
      style={{ background: "rgba(0, 0, 0, 0.45)" }}
      onClick={recording || phase.name === "working" ? undefined : onClose}
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-label={t("title")}
        className="w-full max-w-md rounded-t-3xl p-5 text-center sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))" }}
        onClick={(event) => event.stopPropagation()}
        data-testid="voice-log-sheet"
      >
        <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h2>
        <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{t("hint", { seconds: maxSeconds })}</p>

        <div className="my-6 flex flex-col items-center gap-3">
          <button
            type="button"
            onClick={() => (recording ? void stop() : void start())}
            disabled={phase.name === "working" || blocked}
            aria-pressed={recording}
            aria-label={recording ? t("stop") : t("record")}
            className="flex h-20 w-20 items-center justify-center rounded-full disabled:opacity-60"
            style={{
              background: recording ? "var(--danger)" : "var(--primary)",
              color: "var(--bg)",
              boxShadow: recording ? "0 0 0 8px color-mix(in srgb, var(--danger) 25%, transparent)" : undefined,
            }}
          >
            {recording ? (
              <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <rect x="6" y="6" width="12" height="12" rx="2" />
              </svg>
            ) : (
              <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <rect x="9" y="3" width="6" height="11" rx="3" />
                <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
              </svg>
            )}
          </button>
          <p className="min-h-5 text-sm font-semibold" style={{ color: "var(--text)" }} aria-live="polite">
            {phase.name === "recording"
              ? t("recording", { elapsed: elapsedLabel(elapsed), max: elapsedLabel(maxSeconds * 1000) })
              : phase.name === "working"
                ? t("working")
                : phase.name === "error"
                  ? null
                  : t("tapToStart")}
          </p>
          {phase.name === "error" ? (
            <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(`errors.${phase.key}`)}</p>
          ) : null}
        </div>

        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("privacy")}</p>

        <button
          type="button"
          onClick={() => {
            recorderRef.current?.cancel();
            recorderRef.current = null;
            onClose();
          }}
          disabled={phase.name === "working"}
          className="mt-4 min-h-11 w-full rounded-2xl text-sm font-semibold disabled:opacity-60"
          style={{ color: "var(--dim)", border: "1px solid var(--border)" }}
        >
          {t("cancel")}
        </button>
      </div>
    </div>
  );
}
