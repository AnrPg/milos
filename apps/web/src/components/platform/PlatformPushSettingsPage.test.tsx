import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  fetchPlatformPushSettings,
  replacePlatformPushKeys,
  updatePlatformPushContact,
  type PlatformPushStatus,
} from "@/api/settings";
import { PlatformPushSettingsPage } from "@/components/platform/PlatformPushSettingsPage";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("@/api/settings", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/settings")>()),
  fetchPlatformPushSettings: vi.fn(),
  updatePlatformPushContact: vi.fn(),
  replacePlatformPushKeys: vi.fn(),
}));

const status: PlatformPushStatus = {
  enabled: true,
  source: "palee",
  vapid_subject: "mailto:alerts@palee.app",
  subject_source: "default",
  keys_created_at: "2026-10-29T21:00:00Z",
  device_count: 37,
  last_sent_at: null,
};

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <PlatformPushSettingsPage />
    </QueryClientProvider>,
  );
}

describe("PlatformPushSettingsPage (ADR-277)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("shows status, devices and the contact, and never a key", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(status);
    renderPage();

    expect((await screen.findByTestId("push-status")).textContent).toBe("statusOn");
    expect(screen.getByText("howMembersChoose")).toBeTruthy();
    expect(screen.getByTestId("push-stats").textContent).toContain('deviceCount:{"count":37}');
    expect(screen.getByTestId("push-stats").textContent).toContain("neverSent");
    expect((screen.getByLabelText("subjectLabel") as HTMLInputElement).value).toBe("mailto:alerts@palee.app");
    expect(document.getElementById("push-subject-help")?.textContent).toBe("subjectHelp");
    expect(document.querySelector("textarea")).toBeNull();
    expect(screen.queryByText(/publicKey|privateKey/)).toBeNull();
  });

  it("saves the contact as typed; the server adds mailto:", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(status);
    vi.mocked(updatePlatformPushContact).mockResolvedValue({ ...status, vapid_subject: "mailto:ops@palee.app", subject_source: "palee" });
    renderPage();

    const save = await screen.findByRole("button", { name: "save" });
    expect((save as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("subjectLabel"), { target: { value: "ops@palee.app" } });
    fireEvent.click(save);

    await waitFor(() => expect(updatePlatformPushContact).toHaveBeenCalledWith("token", "ops@palee.app"));
    expect(await screen.findByText("saved")).toBeTruthy();
    expect((screen.getByLabelText("subjectLabel") as HTMLInputElement).value).toBe("mailto:ops@palee.app");
  });

  it("marks a refused contact red with the reason under it", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(status);
    vi.mocked(updatePlatformPushContact).mockRejectedValue(
      new ApiError(422, "invalid", { code: "invalid_push_contact" } as never),
    );
    renderPage();

    fireEvent.change(await screen.findByLabelText("subjectLabel"), { target: { value: "nope" } });
    fireEvent.click(screen.getByRole("button", { name: "save" }));

    expect(await screen.findByText("subjectInvalid")).toBeTruthy();
    expect(screen.getByLabelText("subjectLabel").getAttribute("aria-invalid")).toBe("true");
  });

  it("asks before replacing the keys and says how many devices stop", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue(status);
    vi.mocked(replacePlatformPushKeys).mockResolvedValue({ ...status, device_count: 0 });
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "rotate" }));
    expect(replacePlatformPushKeys).not.toHaveBeenCalled();
    expect(screen.getByTestId("push-rotate-confirm").textContent).toContain('rotateConfirm:{"count":37}');

    fireEvent.click(screen.getByRole("button", { name: "cancel" }));
    expect(screen.queryByTestId("push-rotate-confirm")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "rotate" }));
    fireEvent.click(screen.getByRole("button", { name: "rotateConfirmButton" }));
    await waitFor(() => expect(replacePlatformPushKeys).toHaveBeenCalledWith("token"));
    expect(await screen.findByText("rotated")).toBeTruthy();
  });

  it("with the server's WEB_PUSH_* keys, nothing here can change them", async () => {
    vi.mocked(fetchPlatformPushSettings).mockResolvedValue({ ...status, source: "server", subject_source: "server" });
    renderPage();

    expect(await screen.findByText("sourceServer")).toBeTruthy();
    expect((screen.getByLabelText("subjectLabel") as HTMLInputElement).disabled).toBe(true);
    expect(screen.getByText("subjectServer")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "save" })).toBeNull();
    expect(screen.queryByText("advanced")).toBeNull();
  });

  it("tells a gym owner the page is not theirs", async () => {
    vi.mocked(fetchPlatformPushSettings).mockRejectedValue(new ApiError(403, "vendor_required", { code: "vendor_required" } as never));
    renderPage();
    expect(await screen.findByText("forbidden")).toBeTruthy();
  });
});
