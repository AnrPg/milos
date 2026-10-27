import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { completePasswordReset, inspectPasswordReset, requestPasswordReset } from "@/api/auth";
import { ForgotPassword } from "@/components/auth/ForgotPassword";
import { ResetPassword } from "@/components/auth/ResetPassword";

const replace = vi.fn();
const signOut = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace, refresh: vi.fn() }),
}));

vi.mock("next-intl", () => ({
  useLocale: () => "el",
  useTranslations: (namespace: string) => (key: string) => `${namespace}.${key}`,
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "guest", signOut }),
}));

vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/presentation", () => ({ localizeError: (error: Error) => error.message }));

vi.mock("@/api/auth", () => ({
  requestPasswordReset: vi.fn().mockResolvedValue({ status: "sent" }),
  resetPasswordWithRecoveryCode: vi.fn(),
  inspectPasswordReset: vi.fn(),
  completePasswordReset: vi.fn(),
}));

function at(url: string) {
  window.history.replaceState(null, "", url);
}

describe("ForgotPassword (ADR-206)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("asks for an emailed link and shows the same 'check your email' answer", async () => {
    render(<ForgotPassword />);
    fireEvent.change(screen.getByLabelText("authRecovery.identifierLabel"), { target: { value: " @maria " } });
    fireEvent.click(screen.getByRole("button", { name: "passwordReset.sendLink" }));

    expect(await screen.findByRole("status")).toHaveTextContent("passwordReset.sentBody");
    expect(requestPasswordReset).toHaveBeenCalledWith("@maria", { cantAccessEmail: false, locale: "el" });
    expect(screen.getByRole("button", { name: "passwordReset.cantAccessEmail" })).toBeInTheDocument();
  });

  it("'I can't access my email' asks people who know the person instead", async () => {
    render(<ForgotPassword />);
    fireEvent.click(screen.getByRole("button", { name: "passwordReset.cantAccessEmail" }));
    expect(screen.getByText("passwordReset.noEmailIntro")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("authRecovery.identifierLabel"), { target: { value: "maria" } });
    fireEvent.click(screen.getByRole("button", { name: "passwordReset.askForHelp" }));

    expect(await screen.findByRole("status")).toHaveTextContent("passwordReset.helpSentBody");
    expect(requestPasswordReset).toHaveBeenCalledWith("maria", { cantAccessEmail: true, locale: "el" });
  });

  it("needs an identifier before sending", () => {
    render(<ForgotPassword />);
    fireEvent.click(screen.getByRole("button", { name: "passwordReset.sendLink" }));
    expect(screen.getByText("authRecovery.identifierRequired")).toBeInTheDocument();
    expect(requestPasswordReset).not.toHaveBeenCalled();
  });
});

describe("ResetPassword (ADR-206)", () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => at("/"));

  async function fillAndSubmit() {
    fireEvent.change(await screen.findByLabelText("authRecovery.newPasswordLabel"), { target: { value: "new pass" } });
    fireEvent.change(screen.getByLabelText("authRecovery.confirmPasswordLabel"), { target: { value: "new pass" } });
    fireEvent.click(screen.getByRole("button", { name: "authRecovery.setNewPassword" }));
  }

  it("checks the link from the fragment, hides it from the address bar and spends it only on submit", async () => {
    vi.mocked(inspectPasswordReset).mockResolvedValue({ expires_at: "2026-12-24T13:00:00Z" });
    vi.mocked(completePasswordReset).mockResolvedValue(undefined);
    at("/reset-password#token=abc");

    render(<ResetPassword />);
    await waitFor(() => expect(inspectPasswordReset).toHaveBeenCalledWith("abc"));
    expect(window.location.hash).toBe("");
    expect(completePasswordReset).not.toHaveBeenCalled();

    await fillAndSubmit();
    expect(await screen.findByRole("status")).toHaveTextContent("authRecovery.resetDoneBody");
    expect(completePasswordReset).toHaveBeenCalledWith("abc", "new pass");
  });

  it("still opens old ?token= links", async () => {
    vi.mocked(inspectPasswordReset).mockResolvedValue({ expires_at: "2026-12-24T13:00:00Z" });
    at("/reset-password?token=legacy");

    render(<ResetPassword />);
    await waitFor(() => expect(inspectPasswordReset).toHaveBeenCalledWith("legacy"));
    expect(window.location.search).toBe("");
    expect(await screen.findByLabelText("authRecovery.newPasswordLabel")).toBeInTheDocument();
  });

  it.each([
    ["expired_reset_link", 410, "passwordReset.linkExpired"],
    ["used_reset_link", 410, "passwordReset.linkUsed"],
    ["invalid_reset_link", 422, "passwordReset.linkInvalid"],
  ])("shows %s before any password is typed", async (code, status, message) => {
    vi.mocked(inspectPasswordReset).mockRejectedValue(new ApiError(status, "", { code }));
    at("/reset-password#token=abc");

    render(<ResetPassword />);
    expect(await screen.findByText(message)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "authRecovery.askForNewLink" })).toHaveAttribute("href", "/forgot-password");
    expect(screen.queryByLabelText("authRecovery.newPasswordLabel")).not.toBeInTheDocument();
  });

  it("a link used up meanwhile shows 'used' after submit", async () => {
    vi.mocked(inspectPasswordReset).mockResolvedValue({ expires_at: "2026-12-24T13:00:00Z" });
    vi.mocked(completePasswordReset).mockRejectedValue(new ApiError(410, "", { code: "used_reset_link" }));
    at("/reset-password#token=abc");

    render(<ResetPassword />);
    await fillAndSubmit();
    expect(await screen.findByText("passwordReset.linkUsed")).toBeInTheDocument();
  });

  it("without a token says the link is not valid", async () => {
    at("/reset-password");
    render(<ResetPassword />);
    expect(await screen.findByText("passwordReset.linkInvalid")).toBeInTheDocument();
    expect(inspectPasswordReset).not.toHaveBeenCalled();
  });
});
