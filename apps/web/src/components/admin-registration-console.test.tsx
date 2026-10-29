import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AdminRegistrationConsole } from "@/components/admin-registration-console";
import { inspectInvitation } from "@/api/auth";
import { ApiError, SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

const replace = vi.fn();
const signUpAdmin = vi.fn();
const signOut = vi.fn();
const acceptInvitation = vi.fn();
const session: { status: string; currentUser: { handle?: string; nickname: string } | null } = {
  status: "guest",
  currentUser: null,
};

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace }),
  useSearchParams: () => new URLSearchParams("token=admin-token-1234567890"),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ signUpAdmin, signOut, acceptInvitation, ...session }),
}));

vi.mock("@/api/auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/auth")>();
  return {
    ...actual,
    inspectInvitation: vi.fn(),
  };
});

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, values?: Record<string, string>) =>
    values ? `${key} ${Object.values(values).join(" ")}` : key,
}));

vi.mock("next-intl", () => {
  const translate = (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key;
  translate.rich = (key: string) => key;
  return { useTranslations: () => translate };
});

vi.mock("@/i18n/presentation", () => ({
  localizeError: (error: Error) => error.message,
}));

describe("AdminRegistrationConsole", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    session.status = "guest";
    session.currentUser = null;
    window.localStorage.clear();
    vi.mocked(inspectInvitation).mockResolvedValue({
      role: "admin",
      expires_at: "2026-08-19T00:00:00Z",
      organization: {
        id: "org-1",
        slug: "palee-method",
        name: "Palee Method",
      },
    });
    signUpAdmin.mockResolvedValue({
      id: "user-1",
      nickname: "client_admin",
      role: "member",
      vendor: false,
      preferred_locale: "en",
    });
  });

  it("selects the invited organization and opens tenant admin after admin registration", async () => {
    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");

    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), {
      target: { value: "client_admin" },
    });
    fireEvent.change(screen.getByLabelText("emailAddress"), {
      target: { value: "client@example.test" },
    });
    fireEvent.change(screen.getByLabelText("password8be3c94"), {
      target: { value: "S3cur3P@ss!42" },
    });
    fireEvent.click(screen.getByLabelText('ageConfirmation:{"age":16}'));
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    await waitFor(() => {
      expect(signUpAdmin).toHaveBeenCalledWith({
        nickname: "client_admin",
        email: "client@example.test",
        password: "S3cur3P@ss!42",
        invitation_token: "admin-token-1234567890",
        age_confirmed: true,
      });
    });

    expect(window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY)).toBe("palee-method");
    expect(replace).toHaveBeenCalledWith("/org/palee-method/admin");
  });

  it("asks before going on when another account is already signed in", async () => {
    session.status = "authenticated";
    session.currentUser = { handle: "prod_owner_regas", nickname: "Regas" };

    render(<AdminRegistrationConsole />);
    expect(await screen.findByRole("button", { name: "invitationAcceptAs prod_owner_regas" })).toBeInTheDocument();

    expect(await screen.findByText("invitationSignedInAs prod_owner_regas")).toBeInTheDocument();
    expect(await screen.findByText("invitationForAnotherAccount Palee Method")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "createAdminAccount" })).not.toBeInTheDocument();
    expect(replace).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY)).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "signOutAndContinue" }));
    expect(signOut).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole("button", { name: "staySignedIn" }));
    expect(replace).toHaveBeenCalledWith("/");
  });

  it("accepts the invitation with the signed-in profile and opens the invited box (ADR-204)", async () => {
    session.status = "authenticated";
    session.currentUser = { handle: "prod_owner_regas", nickname: "Regas" };
    acceptInvitation.mockResolvedValue({
      organization: { id: "org-1", slug: "palee-method", name: "Palee Method" },
      roles: ["admin"],
      access_token: "new-access",
      user: null,
    });

    render(<AdminRegistrationConsole />);

    fireEvent.click(await screen.findByRole("button", { name: "invitationAcceptAs prod_owner_regas" }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith("/org/palee-method/admin"));
    expect(acceptInvitation).toHaveBeenCalledWith("admin-token-1234567890");
    expect(window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY)).toBe("palee-method");
    expect(signOut).not.toHaveBeenCalled();
  });

  it("shows why an accept failed and stays on the page", async () => {
    session.status = "authenticated";
    session.currentUser = { handle: "someone_else", nickname: "Someone" };
    acceptInvitation.mockRejectedValueOnce(
      new ApiError(403, "This invitation was issued to a different email address", {
        code: "invitation_email_mismatch",
      }),
    );

    render(<AdminRegistrationConsole />);

    fireEvent.click(await screen.findByRole("button", { name: "invitationAcceptAs someone_else" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "This invitation was issued to a different email address",
    );
    expect(replace).not.toHaveBeenCalled();
  });

  it("tells an email that already has an account to use its password or sign in", async () => {
    signUpAdmin.mockRejectedValueOnce(
      new ApiError(409, "This email already has accounts", {
        code: "email_in_use",
        error: "This email already has accounts",
        errors: { email: ["already has accounts"] },
        profile_count: 1,
        profile_limit: 3,
      } as never),
    );

    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");
    expect(screen.getByText(/adminPasswordExistingHint/)).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), { target: { value: "test_admin" } });
    fireEvent.change(screen.getByLabelText("emailAddress"), { target: { value: "vendor@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "1234" } });
    fireEvent.click(screen.getByLabelText('ageConfirmation:{"age":16}'));
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("adminEmailHasProfiles 1 3");
    expect(screen.queryByText(/already has accounts/)).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "adminSignInToAccept" })).toHaveAttribute(
      "href",
      `/login?next=${encodeURIComponent("/set-admin?token=admin-token-1234567890")}`,
    );
    expect(screen.getByRole("link", { name: "adminForgotPassword" })).toHaveAttribute("href", "/forgot-password");
    expect(screen.getByLabelText("password8be3c94")).toHaveAttribute(
      "style",
      expect.stringContaining("var(--danger)"),
    );
    expect(replace).not.toHaveBeenCalled();
  });

  it("says when the email's account has no room for another profile", async () => {
    signUpAdmin.mockRejectedValueOnce(
      new ApiError(422, "", { code: "profile_limit", profile_limit: 3, errors: {} } as never),
    );

    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");
    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), { target: { value: "test_admin" } });
    fireEvent.change(screen.getByLabelText("emailAddress"), { target: { value: "full@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "right-pass" } });
    fireEvent.click(screen.getByLabelText('ageConfirmation:{"age":16}'));
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("adminEmailProfileLimit 3");
  });

  it("requires only the backend-compatible minimum password length before submitting", async () => {
    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");

    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), {
      target: { value: "client_admin" },
    });
    fireEvent.change(screen.getByLabelText("emailAddress"), {
      target: { value: "client@example.test" },
    });
    fireEvent.change(screen.getByLabelText("password8be3c94"), {
      target: { value: "a b " },
    });

    const submit = screen.getByRole("button", { name: "createAdminAccount" });
    expect(submit).toBeEnabled();

    fireEvent.click(screen.getByLabelText('ageConfirmation:{"age":16}'));
    fireEvent.click(submit);

    await waitFor(() => {
      expect(signUpAdmin).toHaveBeenCalledWith({
        nickname: "client_admin",
        email: "client@example.test",
        password: "a b ",
        invitation_token: "admin-token-1234567890",
        age_confirmed: true,
      });
    });
  });

  it("shows password guidance when the password is shorter than four characters", async () => {
    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");

    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), {
      target: { value: "client_admin" },
    });
    fireEvent.change(screen.getByLabelText("emailAddress"), {
      target: { value: "client@example.test" },
    });
    fireEvent.change(screen.getByLabelText("password8be3c94"), {
      target: { value: "abc" },
    });

    fireEvent.click(screen.getByLabelText('ageConfirmation:{"age":16}'));
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("passwordRules0c63f14");
    expect(signUpAdmin).not.toHaveBeenCalled();
  });

  it("asks to confirm the minimum age under the box before signing up (ADR-267)", async () => {
    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");
    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), { target: { value: "client_admin" } });
    fireEvent.change(screen.getByLabelText("emailAddress"), { target: { value: "client@example.test" } });
    fireEvent.change(screen.getByLabelText("password8be3c94"), { target: { value: "S3cur3P@ss!42" } });
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    expect(await screen.findByText("minimumAgeRule")).toBeInTheDocument();
    expect(screen.getByLabelText('ageConfirmation:{"age":16}')).toHaveAttribute("aria-invalid", "true");
    expect(signUpAdmin).not.toHaveBeenCalled();
  });

  it("shows the invite inspection error instead of silently disabling submit", async () => {
    vi.mocked(inspectInvitation).mockRejectedValueOnce(new Error("Invitation is invalid or unavailable"));

    render(<AdminRegistrationConsole />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Invitation is invalid or unavailable");
    expect(screen.getByRole("button", { name: "createAdminAccount" })).toBeDisabled();
  });

  it("shows backend field validation next to the blocked value", async () => {
    signUpAdmin.mockRejectedValueOnce(
      new ApiError(422, "Check the highlighted values and try again.", {
        code: "validation_failed",
        errors: { email: ["has already been taken"] },
      }),
    );

    render(<AdminRegistrationConsole />);

    await screen.findByText("Palee Method");

    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), {
      target: { value: "client_admin" },
    });
    fireEvent.change(screen.getByLabelText("emailAddress"), {
      target: { value: "client@example.test" },
    });
    fireEvent.change(screen.getByLabelText("password8be3c94"), {
      target: { value: "S3cur3P@ss!42" },
    });
    fireEvent.click(screen.getByLabelText('ageConfirmation:{"age":16}'));
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "emailAddress: has already been taken",
    );
    expect(screen.getByText("has already been taken")).toBeInTheDocument();
    expect(screen.getByLabelText("emailAddress")).toHaveAttribute(
      "style",
      expect.stringContaining("var(--danger)"),
    );
  });
});
