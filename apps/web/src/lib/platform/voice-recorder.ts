"use client";

// ADR-175: the microphone, behind a small port so screens never touch
// MediaRecorder directly and tests use a fake.
//
// The same code runs in browsers and inside the store apps (ADR-171): the
// web views support getUserMedia + MediaRecorder once the shell declares the
// microphone permission (NSMicrophoneUsageDescription on iOS, RECORD_AUDIO on
// Android), so no native plugin is needed. The clip lives in memory only and
// is converted to 16 kHz mono WAV before it is sent.

import { encodeWav, toBase64, toMono16k, TARGET_SAMPLE_RATE } from "./wav";

export type RecordedClip = {
  /** Base64 WAV, ready for POST /me/training-log/voice/drafts. */
  audioBase64: string;
  mimeType: "audio/wav";
  durationMs: number;
};

export type RecorderError = "unsupported" | "permission" | "failed";

export class VoiceRecorderError extends Error {
  reason: RecorderError;
  constructor(reason: RecorderError) {
    super(reason);
    this.name = "VoiceRecorderError";
    this.reason = reason;
  }
}

export interface VoiceRecorder {
  /** Asks for the microphone (first time) and starts recording. */
  start(): Promise<void>;
  /** Stops and returns the clip; the microphone is released. */
  stop(): Promise<RecordedClip>;
  /** Stops and drops everything recorded. */
  cancel(): void;
}

type AudioContextConstructor = typeof AudioContext;

function audioContextConstructor(): AudioContextConstructor | null {
  if (typeof window === "undefined") return null;
  const candidate =
    window.AudioContext ?? (window as unknown as { webkitAudioContext?: AudioContextConstructor }).webkitAudioContext;
  return candidate ?? null;
}

/** True when this browser or app can record a clip (false on the server). */
export function canRecordAudio(): boolean {
  if (typeof window === "undefined" || typeof navigator === "undefined") return false;
  return (
    typeof navigator.mediaDevices?.getUserMedia === "function" &&
    typeof window.MediaRecorder === "function" &&
    audioContextConstructor() !== null
  );
}

/** The browser/web-view adapter. */
export function createBrowserVoiceRecorder(): VoiceRecorder {
  let stream: MediaStream | null = null;
  let recorder: MediaRecorder | null = null;
  let chunks: Blob[] = [];
  let startedAt = 0;

  const release = () => {
    stream?.getTracks().forEach((track) => track.stop());
    stream = null;
    recorder = null;
  };

  return {
    async start() {
      if (!canRecordAudio()) throw new VoiceRecorderError("unsupported");
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
        });
      } catch (error) {
        const name = (error as { name?: string } | null)?.name;
        throw new VoiceRecorderError(name === "NotAllowedError" || name === "SecurityError" ? "permission" : "failed");
      }
      chunks = [];
      recorder = new MediaRecorder(stream);
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) chunks.push(event.data);
      };
      recorder.start();
      startedAt = Date.now();
    },

    async stop() {
      const active = recorder;
      if (!active) throw new VoiceRecorderError("failed");
      const durationMs = Date.now() - startedAt;
      const stopped = new Promise<void>((resolve) => {
        active.onstop = () => resolve();
      });
      active.stop();
      await stopped;
      const type = active.mimeType;
      release();

      const blob = new Blob(chunks, type ? { type } : undefined);
      chunks = [];
      const Context = audioContextConstructor();
      if (!Context) throw new VoiceRecorderError("unsupported");
      const context = new Context();
      try {
        const decoded = await context.decodeAudioData(await blob.arrayBuffer());
        const channels = Array.from({ length: decoded.numberOfChannels }, (_, index) => decoded.getChannelData(index));
        const wav = encodeWav(toMono16k(channels, decoded.sampleRate), TARGET_SAMPLE_RATE);
        return { audioBase64: toBase64(wav), mimeType: "audio/wav", durationMs };
      } catch {
        throw new VoiceRecorderError("failed");
      } finally {
        void context.close().catch(() => undefined);
      }
    },

    cancel() {
      try {
        recorder?.stop();
      } catch {}
      chunks = [];
      release();
    },
  };
}
