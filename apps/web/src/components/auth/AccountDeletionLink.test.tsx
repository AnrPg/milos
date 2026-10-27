import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { AccountDeletionLink } from "@/components/auth/AccountDeletionLink";

const confirmAccountDeletion = vi.fn();
const undoAccountDeletion = vi.fn();
const signOut = vi.fn();
const session = { status: "guest" };
const TOKEN = "a".repeat(43);

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
  useFormatter: () => ({ dateTime: (date: Date) => date.toISOString().slice(0, 10) }),
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/presentation", () => ({ localizeError: (error: Error) => error.message }));
vi.mock("@/components/auth/LanguagePicker", () => ({ LanguagePicker: () => null }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ status: session.status, signOut }) }));
vi.mock("@/api/account-deletion", () => ({
  confirmAccountDeletion: (...args: unknown[]) => confirmAccountDeletion(...args),
  undoAccountDeletion: (...args: unknown[]) => undoAccountDeletion(...args),
}));

describe("AccountDeletionLink (ADR-211)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    session.status = "guest";
    window.location.hash = `#token=${TOKEN}`;
  });

  it("confirms only on the button press, then names the date", async () => {
    confirmAccountDeletion.mockResolvedValue({ status: "scheduled", scope: "login", scheduled_for: "2026-11-09T10:00:00Z" });
    render(<AccountDeletionLink mode="confirm" />);

    const button = await screen.findByRole("button", { name: "confirmButton" });
    await waitFor(() => expect(button).toBeEnabled());
    expect(confirmAccountDeletion).not.toHaveBeenCalled();
    fireEvent.click(button);

    await waitFor(() => expect(confirmAccountDeletion).toHaveBeenCalledWith(TOKEN));
    expect(await screen.findByText('confirmDoneAccount:{"date":"2026-11-09"}')).toBeInTheDocument();
  });

  it("signs this browser out once a deletion is scheduled", async () => {
    session.status = "authenticated";
    confirmAccountDeletion.mockResolvedValue({ status: "scheduled", scope: "profile", scheduled_for: "2026-11-09T10:00:00Z" });
    render(<AccountDeletionLink mode="confirm" />);

    const button = await screen.findByRole("button", { name: "confirmButton" });
    await waitFor(() => expect(button).toBeEnabled());
    fireEvent.click(button);
    expect(await screen.findByText('confirmDoneProfile:{"date":"2026-11-09"}')).toBeInTheDocument();
    await waitFor(() => expect(signOut).toHaveBeenCalledTimes(1));
  });

  it("undoes with the undo link", async () => {
    undoAccountDeletion.mockResolvedValue({ status: "none", scope: null, scheduled_for: null });
    render(<AccountDeletionLink mode="undo" />);

    const button = await screen.findByRole("button", { name: "undoButton" });
    await waitFor(() => expect(button).toBeEnabled());
    fireEvent.click(button);
    expect(await screen.findByText("undoDone")).toBeInTheDocument();
    expect(signOut).not.toHaveBeenCalled();
  });

  it("tells an expired link from a used one, and a missing token", async () => {
    undoAccountDeletion.mockRejectedValueOnce(new ApiError(410, "expired", { code: "expired_deletion_link" } as never));
    const { unmount } = render(<AccountDeletionLink mode="undo" />);
    const button = await screen.findByRole("button", { name: "undoButton" });
    await waitFor(() => expect(button).toBeEnabled());
    fireEvent.click(button);
    expect(await screen.findByText("linkExpired")).toBeInTheDocument();
    unmount();

    window.location.hash = "";
    render(<AccountDeletionLink mode="confirm" />);
    expect(await screen.findByText("linkMissing")).toBeInTheDocument();
  });
});
