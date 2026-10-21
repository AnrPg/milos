import { ApiError } from "@/api/client";
import { VoiceRecorderError } from "@/lib/platform/voice-recorder";

export type VoiceErrorKey =
  | "unsupported"
  | "permission"
  | "recordFailed"
  | "noSpeech"
  | "tooLong"
  | "dailyLimit"
  | "off"
  | "unavailable";

const API_CODES: Record<string, VoiceErrorKey> = {
  no_speech: "noSpeech",
  invalid_audio: "recordFailed",
  audio_too_long: "tooLong",
  voice_log_daily_limit: "dailyLimit",
  voice_log_unavailable: "off",
  transcription_unavailable: "unavailable",
};

/** The message key (namespace VoiceLog.errors) for anything recording can throw. */
export function voiceErrorKey(error: unknown): VoiceErrorKey {
  if (error instanceof VoiceRecorderError) {
    if (error.reason === "unsupported") return "unsupported";
    if (error.reason === "permission") return "permission";
    return "recordFailed";
  }
  if (error instanceof ApiError) {
    const code = error.payload?.code;
    if (code && API_CODES[code]) return API_CODES[code];
  }
  return "unavailable";
}

/** «0:07» from milliseconds. */
export function elapsedLabel(ms: number): string {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
