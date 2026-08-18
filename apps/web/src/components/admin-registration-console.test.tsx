import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AdminRegistrationConsole } from "@/components/admin-registration-console";
import { inspectInvitation } from "@/api/auth";
import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

const replace = vi.fn();
const signUpAdmin = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace }),
  useSearchParams: () => new URLSearchParams("token=admin-token-1234567890"),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ signUpAdmin, status: "guest" }),
}));

vi.mock("@/api/auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/auth")>();
  return {
    ...actual,
    inspectInvitation: vi.fn(),
  };
});

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

vi.mock("@/i18n/presentation", () => ({
  localizeError: (error: Error) => error.message,
}));

describe("AdminRegistrationConsole", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    vi.mocked(inspectInvitation).mockResolvedValue({
      role: "admin",
      expires_at: "2026-08-19T00:00:00Z",
      organization: {
        id: "org-1",
        slug: "milos-method",
        name: "Milos Method",
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

    await screen.findByText("Milos Method");

    fireEvent.change(screen.getByLabelText("nicknamece2bd99"), {
      target: { value: "client_admin" },
    });
    fireEvent.change(screen.getByLabelText("emailAddress"), {
      target: { value: "client@example.test" },
    });
    fireEvent.change(screen.getByLabelText("password8be3c94"), {
      target: { value: "S3cur3P@ss!42" },
    });
    fireEvent.click(screen.getByRole("button", { name: "createAdminAccount" }));

    await waitFor(() => {
      expect(signUpAdmin).toHaveBeenCalledWith({
        nickname: "client_admin",
        email: "client@example.test",
        password: "S3cur3P@ss!42",
        invitation_token: "admin-token-1234567890",
      });
    });

    expect(window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY)).toBe("milos-method");
    expect(replace).toHaveBeenCalledWith("/org/milos-method/admin");
  });
});
