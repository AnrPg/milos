import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { EmailVerificationBanner } from "@/components/auth/EmailVerificationBanner";
import { VerifyEmail } from "@/components/auth/VerifyEmail";

const resendVerificationEmail = vi.fn();
const verifyEmailToken = vi.fn();
const fetchCurrentUser = vi.fn();
const session: { status: string; tokens: { access_token: string } | null; currentUser: Record<string, unknown> | null } = {
  status: "guest",
  tokens: null,
  currentUser: null,
};
let pathname = "/";

vi.mock("next/navigation", () => ({ usePathname: () => pathname }));

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("@/components/session-provider", () => ({ useSession: () => session }));
vi.mock("@/components/auth/LanguagePicker", () => ({ LanguagePicker: () => null }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/presentation", () => ({ localizeError: (error: Error) => error.message }));

vi.mock("@/api/auth", () => ({ fetchCurrentUser: (...args: unknown[]) => fetchCurrentUser(...args) }));

vi.mock("@/api/email-verification", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/email-verification")>();
  return {
    ...actual,
    resendVerificationEmail: (...args: unknown[]) => resendVerificationEmail(...args),
    verifyEmailToken: (...args: unknown[]) => verifyEmailToken(...args),
  };
});

const unverified = { id: "u1", email: "maria@example.com", email_verified: false };

function signIn(user: Record<string, unknown> = unverified) {
  session.status = "authenticated";
  session.tokens = { access_token: "access" };
  session.currentUser = user;
}

describe("EmailVerificationBanner", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.sessionStorage.clear();
    session.status = "guest";
    session.tokens = null;
    session.currentUser = null;
    pathname = "/";
  });

  it("resends the link and reports a throttled retry", async () => {
    signIn();
    resendVerificationEmail
      .mockResolvedValueOnce({ status: "sent" })
      .mockRejectedValueOnce(new ApiError(429, "throttled", { code: "throttled", retry_after_seconds: 42 } as ConstructorParameters<typeof ApiError>[2]));

    const { unmount } = render(<EmailVerificationBanner />);
    const banner = await screen.findByTestId("email-verification-banner");
    expect(banner).toHaveTextContent('bannerText:{"email":"maria@example.com"}');
    expect(screen.getByRole("link", { name: "changeEmail" })).toHaveAttribute("href", "/me/settings#personal");

    fireEvent.click(screen.getByRole("button", { name: "resend" }));
    expect(await screen.findByRole("status")).toHaveTextContent("resent");
    expect(resendVerificationEmail).toHaveBeenCalledWith("access");
    unmount();

    render(<EmailVerificationBanner />);
    fireEvent.click(await screen.findByRole("button", { name: "resend" }));
    expect(await screen.findByRole("status")).toHaveTextContent('throttled:{"seconds":42}');
  });

  it("hides for the rest of the session once dismissed", async () => {
    signIn();
    const { unmount } = render(<EmailVerificationBanner />);
    fireEvent.click(await screen.findByRole("button", { name: "dismiss" }));
    expect(screen.queryByTestId("email-verification-banner")).toBeNull();
    unmount();

    render(<EmailVerificationBanner />);
    await waitFor(() => expect(screen.queryByTestId("email-verification-banner")).toBeNull());
  });

  it("stays away for verified people and on the verify page", async () => {
    signIn({ ...unverified, email_verified: true });
    const { unmount } = render(<EmailVerificationBanner />);
    await waitFor(() => expect(screen.queryByTestId("email-verification-banner")).toBeNull());
    unmount();

    signIn();
    pathname = "/verify-email";
    render(<EmailVerificationBanner />);
    await waitFor(() => expect(screen.queryByTestId("email-verification-banner")).toBeNull());
  });
});

describe("VerifyEmail", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    session.status = "guest";
    session.tokens = null;
    session.currentUser = null;
    window.history.replaceState(null, "", "/verify-email");
  });

  it("posts the fragment's token once, drops it from the URL and confirms", async () => {
    window.history.replaceState(null, "", "/verify-email#token=abc123");
    verifyEmailToken.mockResolvedValue({ email_verified: true });

    render(<VerifyEmail />);

    expect(await screen.findByRole("heading", { name: "verifiedTitle" })).toBeInTheDocument();
    expect(verifyEmailToken).toHaveBeenCalledTimes(1);
    expect(verifyEmailToken).toHaveBeenCalledWith("abc123");
    expect(window.location.hash).toBe("");
    expect(screen.getByRole("link", { name: "signIn" })).toHaveAttribute("href", "/login");
  });

  it("shows an expired link as an error and, signed out, sends people to sign in", async () => {
    window.history.replaceState(null, "", "/verify-email#token=old");
    verifyEmailToken.mockRejectedValue(new ApiError(410, "expired", { code: "expired_verification_link" }));

    render(<VerifyEmail />);

    expect(await screen.findByRole("alert")).toHaveTextContent("expiredBody");
    expect(screen.getByRole("link", { name: "signInForNewLink" })).toHaveAttribute("href", "/login");
  });

  it("signed in, a used link offers a new one", async () => {
    signIn();
    window.history.replaceState(null, "", "/verify-email#token=spent");
    verifyEmailToken.mockRejectedValue(new ApiError(409, "used", { code: "used_verification_link" }));
    resendVerificationEmail.mockResolvedValue({ status: "sent" });

    render(<VerifyEmail />);

    expect(await screen.findByRole("alert")).toHaveTextContent("usedBody");
    fireEvent.click(screen.getByRole("button", { name: "sendNewLink" }));
    expect(await screen.findByText('newLinkSent:{"email":"maria@example.com"}')).toBeInTheDocument();
  });

  it("signed in and already verified, a used link is simply done", async () => {
    signIn({ ...unverified, email_verified: true });
    window.history.replaceState(null, "", "/verify-email#token=spent");
    verifyEmailToken.mockRejectedValue(new ApiError(409, "used", { code: "used_verification_link" }));

    render(<VerifyEmail />);

    expect(await screen.findByText("alreadyVerifiedBody")).toBeInTheDocument();
  });

  it("a link to an old address explains the change and offers no new link", async () => {
    signIn();
    window.history.replaceState(null, "", "/verify-email#token=old-address");
    verifyEmailToken.mockRejectedValue(new ApiError(409, "changed", { code: "verification_email_changed" }));

    render(<VerifyEmail />);

    expect(await screen.findByRole("alert")).toHaveTextContent("emailChangedBody");
    expect(screen.queryByRole("button", { name: "sendNewLink" })).toBeNull();
  });

  it("without a token the link is invalid", async () => {
    render(<VerifyEmail />);
    expect(await screen.findByRole("alert")).toHaveTextContent("invalidBody");
    expect(verifyEmailToken).not.toHaveBeenCalled();
  });
});
