import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AuthConsole } from "@/components/auth-console";
import { ApiError } from "@/api/client";
import { chooseValue } from "@/components/ui/select-test-utils";

const replace = vi.fn();
const refresh = vi.fn();
const signIn = vi.fn();
const signUp = vi.fn();
const switchSession = vi.fn();
const undoAccountDeletionAndSignIn = vi.fn();
const session = { status: "guest" as string };
let search = "";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace, refresh }),
  useSearchParams: () => new URLSearchParams(search),
}));

vi.mock("next-intl", () => {
  const translate = (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key;
  translate.rich = (key: string, values?: Record<string, unknown>) =>
    `${key}:${JSON.stringify({ email: values?.email })}`;
  return {
    useLocale: () => "en",
    useTranslations: () => translate,
    useFormatter: () => ({ dateTime: (date: Date) => date.toISOString().slice(0, 10) }),
  };
});

vi.mock("@/api/account-deletion", () => ({
  undoAccountDeletionAndSignIn: (...args: unknown[]) => undoAccountDeletionAndSignIn(...args),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ signIn, signUp, signUpInvited: vi.fn(), switchSession, status: session.status, tokens: null }),
}));

vi.mock("@/api/auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/auth")>();
  return {
    ...actual,
    suggestHandle: vi.fn().mockResolvedValue({ handle: "maria_k" }),
    checkHandleAvailable: vi.fn().mockResolvedValue({ available: true, handle: "maria_k", suggestions: [] }),
  };
});

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

vi.mock("@/i18n/presentation", () => ({
  localizeError: (error: Error) => error.message,
}));

vi.mock("@/lib/referral-claim", () => ({ markReferralNewAccount: vi.fn() }));

describe("AuthConsole", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    session.status = "guest";
    search = "";
  });

  it("switches the page language from the sign-in screen (ADR-195)", async () => {
    render(<AuthConsole />);

    await chooseValue(screen.getByRole("combobox", { name: "languageLabel" }), "el");

    expect(document.cookie).toContain("palee_locale=el");
    expect(document.documentElement.lang).toBe("el");
    await waitFor(() => expect(refresh).toHaveBeenCalled());
  });

  it("shows a failed sign-in as a red alert", async () => {
    signIn.mockRejectedValue(new Error("Invalid credentials"));
    render(<AuthConsole />);

    fireEvent.change(screen.getByLabelText("identifierLabel"), { target: { value: "maria_k" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "wrong" } });
    fireEvent.click(screen.getByRole("button", { name: "signInada2e9e" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Invalid credentials");
    expect(alert).toHaveAttribute("data-error-notice", "banner");
    expect(alert.getAttribute("style")).toContain("var(--danger-strong)");
  });

  it("signs in with one email-or-handle identifier and links to the forgot-password page", async () => {
    signIn.mockResolvedValue({});
    render(<AuthConsole />);

    expect(screen.getByRole("link", { name: "forgotPasswordLink" })).toHaveAttribute("href", "/forgot-password");

    fireEvent.change(screen.getByLabelText("identifierLabel"), { target: { value: " @maria_k " } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "abcd" } });
    fireEvent.click(screen.getByRole("button", { name: "signInada2e9e" }));

    await waitFor(() => expect(signIn).toHaveBeenCalledWith({ identifier: "@maria_k", password: "abcd" }));
  });

  it("prefills the handle from the display name, says a link was sent, then offers recovery codes", async () => {
    signUp.mockImplementation(async () => {
      session.status = "authenticated";
      return { email: "maria@example.test", user: { id: "u-1" } };
    });
    render(<AuthConsole initialMode="register" />);
    // ADR-183: no member/athlete picker; what you are is a membership, not the account.
    expect(screen.queryByText("iAmA5191365")).toBeNull();

    fireEvent.change(screen.getByLabelText("displayNameLabel"), { target: { value: "Maria K" } });
    await waitFor(() => expect(screen.getByLabelText("handleLabel")).toHaveValue("maria_k"), { timeout: 2000 });

    fireEvent.change(screen.getByLabelText("emailAddress"), { target: { value: "maria@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "abcd" } });
    fireEvent.click(screen.getByRole("button", { name: "createAccountaaf3744" }));

    await waitFor(() =>
      expect(signUp).toHaveBeenCalledWith({
        handle: "maria_k",
        display_name: "Maria K",
        email: "maria@example.test",
        password: "abcd",
        role: "member",
      }),
    );
    // ADR-211: the same "check your inbox" step as a sign-up with a known email.
    expect(await screen.findByText('sentTo:{"email":"maria@example.test"}')).toBeInTheDocument();
    expect(replace).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "continue" }));

    const action = await screen.findByRole("link", { name: "recoveryOfferAction" });
    expect(action).toHaveAttribute("href", "/me/settings#recovery-codes");
    expect(replace).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "recoveryOfferSkip" }));
    expect(replace).toHaveBeenCalledWith("/");
  });

  it("answers a known email like a new one, then leads to sign-in (ADR-211)", async () => {
    signUp.mockResolvedValue({ email: "maria@example.test", user: null });
    render(<AuthConsole initialMode="register" />);

    fireEvent.change(screen.getByLabelText("displayNameLabel"), { target: { value: "Maria" } });
    fireEvent.change(screen.getByLabelText("handleLabel"), { target: { value: "maria" } });
    fireEvent.change(screen.getByLabelText("emailAddress"), { target: { value: "maria@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "abcd" } });
    fireEvent.click(screen.getByRole("button", { name: "createAccountaaf3744" }));

    expect(await screen.findByText('sentTo:{"email":"maria@example.test"}')).toBeInTheDocument();
    expect(screen.queryByRole("alert")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "continue" }));

    expect(await screen.findByLabelText("identifierLabel")).toHaveValue("maria@example.test");
    expect(screen.getByLabelText("password8be3c94")).toHaveValue("");
    expect(screen.queryByRole("link", { name: "recoveryOfferAction" })).toBeNull();
    expect(replace).not.toHaveBeenCalled();
  });

  it("offers to undo a scheduled deletion after the right password (ADR-211)", async () => {
    signIn.mockRejectedValue(
      new ApiError(403, "This account is scheduled for deletion", {
        code: "account_deletion_scheduled",
        scheduled_for: "2026-11-09T10:00:00Z",
      } as never),
    );
    const issued = { access_token: "fresh" };
    undoAccountDeletionAndSignIn.mockResolvedValue(issued);
    render(<AuthConsole />);

    fireEvent.change(screen.getByLabelText("identifierLabel"), { target: { value: "maria@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "abcd" } });
    fireEvent.click(screen.getByRole("button", { name: "signInada2e9e" }));

    expect(await screen.findByText('signInScheduled:{"date":"2026-11-09"}')).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "signInUndo" }));

    await waitFor(() =>
      expect(undoAccountDeletionAndSignIn).toHaveBeenCalledWith({ identifier: "maria@example.test", password: "abcd" }),
    );
    await waitFor(() => expect(switchSession).toHaveBeenCalledWith(issued));
  });
});
