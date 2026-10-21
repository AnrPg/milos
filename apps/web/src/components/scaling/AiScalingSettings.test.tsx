import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AiScalingSettings } from "./AiScalingSettings";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

const fetchAiSettings = vi.fn();
const updateAiSettings = vi.fn();
vi.mock("@/api/scaling", () => ({
  AI_SETTINGS_KEY: ["admin", "ai-settings"],
  fetchAiSettings: (token: string) => fetchAiSettings(token),
  updateAiSettings: (token: string, body: unknown) => updateAiSettings(token, body),
}));

const settings = {
  provider: "anthropic",
  scaling_enabled: false,
  voice_enabled: false,
  key_configured: true,
  key_last4: "abcd",
  key_status: "valid",
  model: null,
  default_model: "default-model",
  usage: { suggestions: 0, cost_usd: 0 },
};

function renderSettings() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <AiScalingSettings token="t" />
    </QueryClientProvider>,
  );
}

describe("AiScalingSettings", () => {
  beforeEach(() => {
    fetchAiSettings.mockReset().mockResolvedValue(settings);
    updateAiSettings.mockReset();
  });

  // ADR-174/175: a tapped switch shows its new state at once and stays there
  // while the save runs (it never flips back for a moment).
  it("keeps a tapped switch on while the save runs, then shows the saved state", async () => {
    let resolve: (value: unknown) => void = () => undefined;
    updateAiSettings.mockReturnValue(new Promise((done) => (resolve = done)));
    renderSettings();

    const toggle = (await screen.findAllByRole("switch"))[0] as HTMLInputElement;
    fireEvent.click(toggle);
    expect(toggle.checked).toBe(true);
    expect(toggle.disabled).toBe(true);
    await vi.waitFor(() => expect(updateAiSettings).toHaveBeenCalledWith("t", { scaling_enabled: true }));
    expect(toggle.checked).toBe(true);

    await act(async () => resolve({ ...settings, scaling_enabled: true }));
    expect(toggle.checked).toBe(true);
    expect(toggle.disabled).toBe(false);
  });

  it("returns to the stored state when the save fails", async () => {
    updateAiSettings.mockRejectedValue(new Error("nope"));
    renderSettings();

    const voice = (await screen.findAllByRole("switch"))[1] as HTMLInputElement;
    fireEvent.click(voice);
    expect(voice.checked).toBe(true);
    await screen.findByRole("alert");
    expect(voice.checked).toBe(false);
    expect(updateAiSettings).toHaveBeenCalledWith("t", { voice_enabled: true });
  });
});
