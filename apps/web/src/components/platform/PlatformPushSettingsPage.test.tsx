import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { fetchPlatformPushSettings, updatePlatformPushSettings } from "@/api/settings";
import { PlatformPushSettingsPage } from "@/components/platform/PlatformPushSettingsPage";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));

vi.mock("next-intl", () => ({ useTranslations: () => (key: string) => key }));

vi.mock("@/api/settings", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/settings")>()),
  fetchPlatformPushSettings: vi.fn(),
  updatePlatformPushSettings: vi.fn(),
}));

const saved = {
  enabled: true,
  vapid_public_key: "public-key",
  vapid_private_key_configured: true,
  vapid_subject: "mailto:alerts@palee.app",
};

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <PlatformPushSettingsPage />
    </QueryClientProvider>,
  );
}

describe("PlatformPushSettingsPage (ADR-218)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("explains every field next to it", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(saved);
    renderPage();

    expect(await screen.findByText("howItWorks")).toBeTruthy();
    expect(screen.getByText("howMembersChoose")).toBeTruthy();
    expect(screen.getByTestId("push-status").textContent).toBe("statusOn");
    for (const [id, help] of [
      ["push-subject", "subjectHelp"],
      ["push-public-key", "publicKeyHelp"],
      ["push-private-key", "privateKeyHelp"],
    ]) {
      expect(document.getElementById(id)?.getAttribute("aria-describedby")).toBe(`${id}-help`);
      expect(document.getElementById(`${id}-help`)?.textContent).toBe(help);
    }
    expect(screen.getByText("generateHelp")).toBeTruthy();
    expect(screen.getByText("turnOffHelp")).toBeTruthy();
  });

  it("keeps the saved private key and adds mailto: to a plain email", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(saved);
    vi.mocked(updatePlatformPushSettings).mockResolvedValue({ ...saved, vapid_subject: "mailto:ops@palee.app" });
    renderPage();

    fireEvent.change(await screen.findByLabelText("subjectLabel"), { target: { value: "ops@palee.app" } });
    fireEvent.click(screen.getByRole("button", { name: "save" }));

    await waitFor(() =>
      expect(updatePlatformPushSettings).toHaveBeenCalledWith("token", {
        vapid_public_key: "public-key",
        vapid_subject: "mailto:ops@palee.app",
      }),
    );
  });

  it("warns that new keys make every device allow alerts again", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(saved);
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "generateReplace" }));
    expect(await screen.findByText("replaceWarning")).toBeTruthy();
  });

  it("tells a gym owner the page is not theirs", async () => {
    vi.mocked(fetchPlatformPushSettings).mockRejectedValue(new ApiError(403, "vendor_required", { code: "vendor_required" } as never));
    renderPage();
    expect(await screen.findByText("forbidden")).toBeTruthy();
  });
});
