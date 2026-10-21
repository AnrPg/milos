import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import { VoiceRecorderError } from "@/lib/platform/voice-recorder";

import { elapsedLabel, voiceErrorKey } from "./voice-log-model";

describe("voiceErrorKey", () => {
  it("maps recorder and API errors to neutral messages", () => {
    expect(voiceErrorKey(new VoiceRecorderError("permission"))).toBe("permission");
    expect(voiceErrorKey(new VoiceRecorderError("unsupported"))).toBe("unsupported");
    expect(voiceErrorKey(new VoiceRecorderError("failed"))).toBe("recordFailed");
    expect(voiceErrorKey(new ApiError(422, "x", { code: "no_speech" }))).toBe("noSpeech");
    expect(voiceErrorKey(new ApiError(429, "x", { code: "voice_log_daily_limit" }))).toBe("dailyLimit");
    expect(voiceErrorKey(new ApiError(403, "x", { code: "voice_log_unavailable" }))).toBe("off");
    expect(voiceErrorKey(new ApiError(500, "x", {}))).toBe("unavailable");
    expect(voiceErrorKey(new Error("network"))).toBe("unavailable");
  });
});

describe("elapsedLabel", () => {
  it("formats minutes and seconds", () => {
    expect(elapsedLabel(0)).toBe("0:00");
    expect(elapsedLabel(7_900)).toBe("0:07");
    expect(elapsedLabel(60_000)).toBe("1:00");
  });
});
