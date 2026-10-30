import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { YourDataSection } from "@/components/account/YourDataSection";

const fetchDataExports = vi.fn();
const requestDataExport = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
  useFormatter: () => ({
    dateTime: (date: Date) => date.toISOString().slice(0, 10),
    number: (value: number, options: { unit: string }) => `${Math.round(value)} ${options.unit}`,
  }),
}));

vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/presentation", () => ({ localizeError: (error: Error) => error.message }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" }, currentUser: { id: "u-1" } }),
}));

vi.mock("@/api/data-exports", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/data-exports")>();
  return {
    ...actual,
    fetchDataExports: (...args: unknown[]) => fetchDataExports(...args),
    requestDataExport: (...args: unknown[]) => requestDataExport(...args),
  };
});

function renderSection() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <YourDataSection />
    </QueryClientProvider>,
  );
  fireEvent.click(screen.getByRole("button", { name: /yourDataTitle/ }));
}

const ready = {
  id: "e-1",
  status: "ready",
  requested_at: "2026-10-28T09:00:00Z",
  completed_at: "2026-10-28T09:02:00Z",
  expires_at: "2026-11-04T09:02:00Z",
  record_count: 42,
  file: { name: "palee-my-data-2026-10-28.zip", bytes: 2_400_000, sha256: "abc", download_url: "https://media.example/x.zip?sig=1" },
};

describe("YourDataSection (ADR-267)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    fetchDataExports.mockResolvedValue([]);
  });

  it("asks for a copy, then shows it is being prepared", async () => {
    renderSection();
    expect(screen.getByRole("link", { name: "privacyTitle" })).toHaveAttribute("href", "/privacy");
    expect(screen.getByRole("link", { name: "termsTitle" })).toHaveAttribute("href", "/terms");

    requestDataExport.mockResolvedValue({ ...ready, status: "pending", file: null, completed_at: null });
    fetchDataExports.mockResolvedValue([{ ...ready, status: "pending", file: null, completed_at: null }]);
    fireEvent.click(await screen.findByRole("button", { name: "downloadMyData" }));

    await waitFor(() => expect(requestDataExport).toHaveBeenCalledWith("token"));
    expect(await screen.findByText('exportPending:{"date":"2026-10-28"}')).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "requestNewCopy" })).toBeDisabled();
  });

  it("offers the ready file with its size and until when it is kept", async () => {
    fetchDataExports.mockResolvedValue([ready]);
    renderSection();

    const link = await screen.findByRole("link", { name: 'downloadFile:{"size":"2 megabyte"}' });
    expect(link).toHaveAttribute("href", "https://media.example/x.zip?sig=1");
    expect(link).toHaveAttribute("download", "palee-my-data-2026-10-28.zip");
    expect(screen.getByText('exportAvailableUntil:{"date":"2026-11-04"}')).toBeInTheDocument();
  });

  it("says when the next copy can be asked for", async () => {
    fetchDataExports.mockResolvedValue([ready]);
    requestDataExport.mockRejectedValue(
      new ApiError(429, "", { code: "export_rate_limited", retry_at: "2026-10-29T09:00:00Z" } as never),
    );
    renderSection();

    fireEvent.click(await screen.findByRole("button", { name: "requestNewCopy" }));
    expect(await screen.findByText('exportRateLimited:{"date":"2026-10-29"}')).toBeInTheDocument();
  });

  it("shows a failed build as an error and lets the person try again", async () => {
    fetchDataExports.mockResolvedValue([{ ...ready, status: "failed", file: null }]);
    renderSection();

    expect(await screen.findByText("exportFailed")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "requestNewCopy" })).toBeEnabled();
  });
});
