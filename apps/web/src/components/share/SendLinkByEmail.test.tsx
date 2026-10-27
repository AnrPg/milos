import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { sendShareLinkByEmail } from "@/api/share-links";
import { SendLinkByEmail } from "@/components/share/SendLinkByEmail";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, string>) =>
    values ? `${key} ${Object.values(values).join(" ")}` : key,
}));

vi.mock("@/api/share-links", () => ({ sendShareLinkByEmail: vi.fn() }));

function renderIt(token: string | null = "ABCD1234") {
  const client = new QueryClient({ defaultOptions: { mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <SendLinkByEmail link="referral" token={token} />
    </QueryClientProvider>,
  );
}

function sendTo(address: string) {
  fireEvent.click(screen.getByTestId("share-by-email"));
  fireEvent.change(screen.getByLabelText("label"), { target: { value: address } });
  fireEvent.click(screen.getByRole("button", { name: "send" }));
}

describe("SendLinkByEmail (ADR-210)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(sendShareLinkByEmail).mockResolvedValue({ delivery: { id: "m1", status: "queued" } });
  });

  it("stays a quiet link until opened, and nothing shows before the link exists", () => {
    const { unmount } = renderIt(null);
    expect(screen.queryByTestId("share-by-email")).not.toBeInTheDocument();
    unmount();

    renderIt();
    expect(screen.getByTestId("share-by-email")).toHaveTextContent("action");
    expect(screen.queryByLabelText("label")).not.toBeInTheDocument();
  });

  it("sends the same link with the typed address and confirms it", async () => {
    renderIt();
    sendTo("  friend@example.test ");

    await waitFor(() => {
      expect(sendShareLinkByEmail).toHaveBeenCalledWith("token", {
        link: "referral",
        token: "ABCD1234",
        to: "friend@example.test",
      });
    });
    expect(await screen.findByRole("status")).toHaveTextContent("sent friend@example.test");
  });

  it.each([
    ["share_link_sender_unverified", "errors.unverified"],
    ["share_link_daily_limit", "errors.dailyLimit"],
    ["suppressed", "errors.suppressed"],
    ["business_not_activated", "errors.demo"],
    ["something_else", "errors.generic"],
  ])("explains %s", async (code, key) => {
    vi.mocked(sendShareLinkByEmail).mockRejectedValueOnce(new ApiError(403, code, { code }));
    renderIt();
    sendTo("friend@example.test");

    expect(await screen.findByText(key)).toBeInTheDocument();
  });
});
