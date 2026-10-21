import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { VoiceRecorderError, type VoiceRecorder } from "@/lib/platform/voice-recorder";

import { VoiceLogSheet } from "./VoiceLogSheet";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "el" }));
vi.mock("@/hooks/useModalFocusTrap", () => ({ useModalFocusTrap: () => ({ current: null }) }));

const createVoiceDraft = vi.fn();

function fakeRecorder(overrides: Partial<VoiceRecorder> = {}): VoiceRecorder {
  return {
    start: vi.fn(async () => undefined),
    stop: vi.fn(async () => ({ audioBase64: "UklGRg==", mimeType: "audio/wav" as const, durationMs: 4_000 })),
    cancel: vi.fn(),
    ...overrides,
  };
}

const result = {
  transcript: "Fran σε 6 λεπτά",
  parsed: true,
  draft: { title: "Fran", duration_minutes: 6, perceived_effort: null, days_ago: null, notes: null, exercises: [] },
};

describe("VoiceLogSheet", () => {
  beforeEach(() => createVoiceDraft.mockReset());

  it("records, stops, sends the clip and hands back the draft (nothing saved here)", async () => {
    createVoiceDraft.mockResolvedValue(result);
    const recorder = fakeRecorder();
    const onDraft = vi.fn();
    render(<VoiceLogSheet token="t" maxSeconds={60} onDraft={onDraft} onClose={vi.fn()} recorderFactory={() => recorder} submit={createVoiceDraft} />);

    fireEvent.click(screen.getByRole("button", { name: "record" }));
    await screen.findByRole("button", { name: "stop" });
    fireEvent.click(screen.getByRole("button", { name: "stop" }));

    await waitFor(() => expect(onDraft).toHaveBeenCalledWith(result));
    expect(createVoiceDraft).toHaveBeenCalledWith("t", {
      audio_base64: "UklGRg==",
      mime_type: "audio/wav",
      duration_ms: 4_000,
      locale: "el",
    });
  });

  it("explains a refused microphone and lets the member try again", async () => {
    const recorder = fakeRecorder({ start: vi.fn(async () => Promise.reject(new VoiceRecorderError("permission"))) });
    render(<VoiceLogSheet token="t" maxSeconds={60} onDraft={vi.fn()} onClose={vi.fn()} recorderFactory={() => recorder} submit={createVoiceDraft} />);

    fireEvent.click(screen.getByRole("button", { name: "record" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("errors.permission");
    expect(screen.getByRole("button", { name: "record" })).not.toBeDisabled();
  });

  it("blocks recording when today's limit is reached", async () => {
    const refuse = async () => {
      throw new ApiError(429, "limit", { code: "voice_log_daily_limit" });
    };
    render(<VoiceLogSheet token="t" maxSeconds={60} onDraft={vi.fn()} onClose={vi.fn()} recorderFactory={() => fakeRecorder()} submit={refuse} />);

    fireEvent.click(screen.getByRole("button", { name: "record" }));
    fireEvent.click(await screen.findByRole("button", { name: "stop" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("errors.dailyLimit");
    expect(screen.getByRole("button", { name: "record" })).toBeDisabled();
  });

  it("stops by itself at the time limit", async () => {
    createVoiceDraft.mockResolvedValue(result);
    const onDraft = vi.fn();
    render(<VoiceLogSheet token="t" maxSeconds={0} onDraft={onDraft} onClose={vi.fn()} recorderFactory={() => fakeRecorder()} submit={createVoiceDraft} />);

    fireEvent.click(screen.getByRole("button", { name: "record" }));
    await waitFor(() => expect(onDraft).toHaveBeenCalledWith(result));
    expect(createVoiceDraft).toHaveBeenCalledTimes(1);
  });

  it("cancel drops the recording", async () => {
    const recorder = fakeRecorder();
    const onClose = vi.fn();
    render(<VoiceLogSheet token="t" maxSeconds={60} onDraft={vi.fn()} onClose={onClose} recorderFactory={() => recorder} submit={createVoiceDraft} />);

    fireEvent.click(screen.getByRole("button", { name: "record" }));
    await screen.findByRole("button", { name: "stop" });
    fireEvent.click(screen.getByRole("button", { name: "cancel" }));

    expect(recorder.cancel).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
    expect(createVoiceDraft).not.toHaveBeenCalled();
  });
});
