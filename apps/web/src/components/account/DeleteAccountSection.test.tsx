import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { DeleteAccountSection } from "@/components/account/DeleteAccountSection";

const fetchAccountDeletion = vi.fn();
const requestAccountDeletion = vi.fn();
const cancelAccountDeletion = vi.fn();
const signOut = vi.fn();
const session = {
  tokens: { access_token: "token" },
  currentUser: { id: "u-1", handle: "maria", email: "maria@example.test", profile_count: 2, email_verified: true } as Record<
    string,
    unknown
  >,
};

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
  useFormatter: () => ({ dateTime: (date: Date) => date.toISOString().slice(0, 10) }),
}));

vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/presentation", () => ({ localizeError: (error: Error) => error.message }));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ ...session, signOut }),
}));

vi.mock("@/api/account-deletion", () => ({
  fetchAccountDeletion: (...args: unknown[]) => fetchAccountDeletion(...args),
  requestAccountDeletion: (...args: unknown[]) => requestAccountDeletion(...args),
  cancelAccountDeletion: (...args: unknown[]) => cancelAccountDeletion(...args),
}));

function renderSection() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <DeleteAccountSection />
    </QueryClientProvider>,
  );
}

async function openSection() {
  fireEvent.click(screen.getByRole("button", { name: /sectionTitle/ }));
}

describe("DeleteAccountSection (ADR-211)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    session.currentUser = { id: "u-1", handle: "maria", email: "maria@example.test", profile_count: 2, email_verified: true };
    fetchAccountDeletion.mockResolvedValue({ status: "none", scope: null, scheduled_for: null });
  });

  it("asks for the password, then says the confirmation link was sent", async () => {
    requestAccountDeletion.mockResolvedValue({ status: "awaiting_confirmation", scope: "profile", scheduled_for: null, email: "maria@example.test" });
    renderSection();
    await openSection();

    fireEvent.click(await screen.findByRole("button", { name: "deleteProfile" }));
    expect(screen.getByText('dialogProfileBody:{"handle":"maria"}')).toBeInTheDocument();
    expect(screen.queryByLabelText("confirmEmailLabel")).toBeNull();

    fireEvent.change(screen.getByLabelText("passwordLabel"), { target: { value: "secret" } });
    fetchAccountDeletion.mockResolvedValue({ status: "awaiting_confirmation", scope: "profile", scheduled_for: null });
    fireEvent.click(screen.getByRole("button", { name: "submit" }));

    await waitFor(() =>
      expect(requestAccountDeletion).toHaveBeenCalledWith("token", { scope: "profile", password: "secret" }),
    );
    expect(await screen.findByText('awaiting:{"email":"maria@example.test"}')).toBeInTheDocument();

    cancelAccountDeletion.mockResolvedValue(undefined);
    fireEvent.click(screen.getByRole("button", { name: "awaitingCancel" }));
    await waitFor(() => expect(cancelAccountDeletion).toHaveBeenCalledWith("token"));
  });

  it("offers only the account deletion for a single profile", async () => {
    session.currentUser = { ...session.currentUser, profile_count: 1 };
    renderSection();
    await openSection();

    expect(await screen.findByRole("button", { name: "deleteAccount" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "deleteProfile" })).toBeNull();
  });

  it("an unconfirmed email types the address; scheduling signs out", async () => {
    session.currentUser = { ...session.currentUser, email_verified: false };
    requestAccountDeletion.mockResolvedValue({ status: "scheduled", scope: "login", scheduled_for: "2026-11-09T10:00:00Z" });
    renderSection();
    await openSection();

    fireEvent.click(await screen.findByRole("button", { name: "deleteAccount" }));
    fireEvent.change(screen.getByLabelText("passwordLabel"), { target: { value: "secret" } });
    const submit = screen.getByRole("button", { name: "submit" });
    expect(submit).toBeDisabled();
    fireEvent.change(screen.getByLabelText("confirmEmailLabel"), { target: { value: "maria@example.test" } });
    fireEvent.click(submit);

    await waitFor(() =>
      expect(requestAccountDeletion).toHaveBeenCalledWith("token", {
        scope: "login",
        password: "secret",
        confirm_email: "maria@example.test",
      }),
    );
    expect(await screen.findByText('scheduledNowAccount:{"date":"2026-11-09"}')).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "signOut" }));
    expect(signOut).toHaveBeenCalled();
  });

  it("explains a wrong password and a sole owner's businesses", async () => {
    requestAccountDeletion
      .mockRejectedValueOnce(new ApiError(422, "wrong", { code: "invalid_password" } as never))
      .mockRejectedValueOnce(
        new ApiError(409, "owner", { code: "sole_owner", organizations: ["Box Kypseli"] } as never),
      );
    renderSection();
    await openSection();

    fireEvent.click(await screen.findByRole("button", { name: "deleteAccount" }));
    fireEvent.change(screen.getByLabelText("passwordLabel"), { target: { value: "nope" } });
    fireEvent.click(screen.getByRole("button", { name: "submit" }));
    expect(await screen.findByText("errorPassword")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("passwordLabel"), { target: { value: "secret" } });
    fireEvent.click(screen.getByRole("button", { name: "submit" }));
    expect(await screen.findByText('errorSoleOwner:{"names":"«Box Kypseli»"}')).toBeInTheDocument();
  });

  it("a scheduled profile deletion seen from another profile can be undone", async () => {
    fetchAccountDeletion.mockResolvedValue({ status: "scheduled", scope: "profile", scheduled_for: "2026-11-09T10:00:00Z" });
    cancelAccountDeletion.mockResolvedValue(undefined);
    renderSection();
    await openSection();

    expect(await screen.findByText('scheduledProfile:{"date":"2026-11-09"}')).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "undo" }));
    await waitFor(() => expect(cancelAccountDeletion).toHaveBeenCalledWith("token"));
  });
});
