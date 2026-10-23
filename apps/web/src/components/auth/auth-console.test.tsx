import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AuthConsole } from "@/components/auth-console";
import { ApiError } from "@/api/client";

const replace = vi.fn();
const signIn = vi.fn();
const signUp = vi.fn();
const session = { status: "guest" as string };
let search = "";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace }),
  useSearchParams: () => new URLSearchParams(search),
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ signIn, signUp, signUpInvited: vi.fn(), status: session.status, tokens: null }),
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

  it("signs in with one email-or-handle identifier and links to the forgot-password page", async () => {
    signIn.mockResolvedValue({});
    render(<AuthConsole />);

    expect(screen.getByRole("link", { name: "forgotPasswordLink" })).toHaveAttribute("href", "/forgot-password");

    fireEvent.change(screen.getByLabelText("identifierLabel"), { target: { value: " @maria_k " } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "abcd" } });
    fireEvent.click(screen.getByRole("button", { name: "signInada2e9e" }));

    await waitFor(() => expect(signIn).toHaveBeenCalledWith({ identifier: "@maria_k", password: "abcd" }));
  });

  it("prefills the handle from the display name and offers recovery codes after sign-up", async () => {
    signUp.mockImplementation(async () => {
      session.status = "authenticated";
      return {};
    });
    render(<AuthConsole initialMode="register" />);

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
    const action = await screen.findByRole("link", { name: "recoveryOfferAction" });
    expect(action).toHaveAttribute("href", "/me/settings#recovery-codes");
    expect(replace).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "recoveryOfferSkip" }));
    expect(replace).toHaveBeenCalledWith("/");
  });

  it("explains a repeat email under the email field", async () => {
    signUp.mockRejectedValue(
      new ApiError(409, "This email already has accounts", {
        code: "email_in_use",
        profile_count: 1,
        profile_limit: 3,
      } as never),
    );
    render(<AuthConsole initialMode="register" />);

    fireEvent.change(screen.getByLabelText("displayNameLabel"), { target: { value: "Maria" } });
    fireEvent.change(screen.getByLabelText("handleLabel"), { target: { value: "maria" } });
    fireEvent.change(screen.getByLabelText("emailAddress"), { target: { value: "maria@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "abcd" } });
    fireEvent.click(screen.getByRole("button", { name: "createAccountaaf3744" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      'emailInUseCount:{"count":1,"limit":3} emailInUseAddProfile',
    );
  });
});
