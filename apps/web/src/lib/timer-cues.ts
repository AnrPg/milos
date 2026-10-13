"use client";

/**
 * Audio + haptic cues for workout execution. Athletes train with the phone on
 * the floor, so every phase change and the final seconds of a timed segment
 * get a distinct sound and vibration pattern instead of requiring them to
 * watch the screen.
 */

export type CueMode = "sound" | "vibrate" | "off";
export type Cue = "tick" | "work" | "rest" | "finish";
export type CuePhase = "work" | "rest";

export type CueSnapshot = {
  segmentKey: string | null;
  running: boolean;
  /** Whole seconds left on a countdown or capped count-up, null when untimed. */
  remaining: number | null;
  phase: CuePhase;
};

export const CUE_MODES: CueMode[] = ["sound", "vibrate", "off"];
const COUNTDOWN_TICKS = new Set([1, 2, 3]);
const STORAGE_KEY = "milos-timer-cue-mode";

/**
 * Decides which cue (if any) a timer transition should play. Pure so the
 * rules are testable without audio hardware.
 */
export function nextCue(previous: CueSnapshot | null, current: CueSnapshot): Cue | null {
  if (!current.running) return null;

  const segmentChanged = previous?.segmentKey !== current.segmentKey;
  const started = segmentChanged || !previous?.running;

  if (started) return current.phase;

  if (
    current.remaining !== null &&
    COUNTDOWN_TICKS.has(current.remaining) &&
    previous.remaining !== current.remaining
  ) {
    return "tick";
  }

  return null;
}

const TONES: Record<Cue, { frequency: number; durationMs: number; offsetMs: number }[]> = {
  tick: [{ frequency: 880, durationMs: 120, offsetMs: 0 }],
  work: [{ frequency: 1320, durationMs: 550, offsetMs: 0 }],
  rest: [{ frequency: 520, durationMs: 650, offsetMs: 0 }],
  finish: [
    { frequency: 880, durationMs: 160, offsetMs: 0 },
    { frequency: 1100, durationMs: 160, offsetMs: 180 },
    { frequency: 1320, durationMs: 500, offsetMs: 360 },
  ],
};

const VIBRATIONS: Record<Cue, number[]> = {
  tick: [60],
  work: [250, 100, 250],
  rest: [450],
  finish: [200, 100, 200, 100, 450],
};

let audioContext: AudioContext | null = null;

function getAudioContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (audioContext) return audioContext;

  const Ctor =
    window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;

  try {
    audioContext = new Ctor();
  } catch {
    audioContext = null;
  }
  return audioContext;
}

/**
 * Browsers only allow audio after a user gesture. Call this from a tap/click
 * handler (e.g. Start, Resume) so later timer-driven cues can play.
 */
export function primeCueAudio() {
  const context = getAudioContext();
  if (context && context.state === "suspended") {
    void context.resume().catch(() => undefined);
  }
}

function playTones(cue: Cue) {
  const context = getAudioContext();
  if (!context || context.state !== "running") return;

  for (const tone of TONES[cue]) {
    const start = context.currentTime + tone.offsetMs / 1000;
    const end = start + tone.durationMs / 1000;
    const oscillator = context.createOscillator();
    const gain = context.createGain();

    oscillator.type = "sine";
    oscillator.frequency.value = tone.frequency;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(0.4, start + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, end);
    oscillator.connect(gain).connect(context.destination);
    oscillator.start(start);
    oscillator.stop(end + 0.02);
  }
}

export function playCue(cue: Cue, mode: CueMode) {
  if (mode === "off") return;
  if (mode === "sound") playTones(cue);

  if (typeof navigator !== "undefined" && typeof navigator.vibrate === "function") {
    try {
      navigator.vibrate(VIBRATIONS[cue]);
    } catch {
      // Vibration is best-effort (unsupported or blocked without user activation).
    }
  }
}

export function readCueMode(): CueMode {
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    return CUE_MODES.includes(stored as CueMode) ? (stored as CueMode) : "sound";
  } catch {
    return "sound";
  }
}

export function storeCueMode(mode: CueMode) {
  try {
    window.localStorage.setItem(STORAGE_KEY, mode);
  } catch {
    // Preference is a per-device convenience; ignore storage failures.
  }
}
