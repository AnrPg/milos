import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { inspectInvitation } from "@/api/auth";
import { ApiError } from "@/api/client";
import { redeemInvitation } from "@/api/organizations";
import { InviteRedeemPage, PENDING_INVITE_KEY } from "./InviteRedeem";

const session = vi.hoisted(() => ({ status: "guest", signOut: vi.fn() }));

vi.mock("next/navigation", () => ({ useRouter: () => ({ replace: vi.fn() }) }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ ...session, tokens: session.status === "authenticated" ? { access_token: "access" } : null, rotate: vi.fn().mockResolvedValue(undefined) }),
}));
vi.mock("@/api/auth", async (importOriginal) => ({ ...(await importOriginal<typeof import("@/api/auth")>()), inspectInvitation: vi.fn() }));
vi.mock("@/api/organizations", async (importOriginal) => ({ ...(await importOriginal<typeof import("@/api/organizations")>()), redeemInvitation: vi.fn() }));

const TOKEN = "t".repeat(43);

function renderPage() {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <InviteRedeemPage />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  session.status = "guest";
  window.sessionStorage.clear();
  window.history.replaceState(null, "", `/invite#token=${TOKEN}`);
  vi.mocked(inspectInvitation).mockResolvedValue({
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
    role: "member",
    roles: ["member"],
    expires_at: "2026-11-03T10:00:00Z",
    email_bound: true,
  });
});

describe("InviteRedeemPage (ADR-209)", () => {
  it("reads the fragment token, hides it from the address bar and offers sign-up with it", async () => {
    renderPage();

    await screen.findByText("Join Box Kypseli");
    expect(inspectInvitation).toHaveBeenCalledWith(TOKEN);
    expect(window.location.hash).toBe("");
    expect(window.sessionStorage.getItem(PENDING_INVITE_KEY)).toBe(TOKEN);
    expect(screen.getByText(/This invitation is for one email address/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Create an account" })).toHaveAttribute("href", `/register#token=${TOKEN}`);
    expect(screen.getByRole("link", { name: "I already have an account" })).toHaveAttribute("href", "/login?next=%2Finvite");
  });

  it("says when the box revoked the invitation", async () => {
    vi.mocked(inspectInvitation).mockRejectedValue(new ApiError(410, "error", { code: "invitation_revoked", error: "x" }));
    renderPage();
    await screen.findByText("This invitation was revoked");
  });

  it("signed in with another address: a clear message that names no address", async () => {
    session.status = "authenticated";
    vi.mocked(redeemInvitation).mockRejectedValue(new ApiError(403, "error", { code: "invitation_email_mismatch", error: "x" }));
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Join Box Kypseli" }));
    await screen.findByText(/signed in with a different email address/);
    fireEvent.click(screen.getByRole("button", { name: "Sign out" }));
    expect(session.signOut).toHaveBeenCalled();
  });

  it("uses the kept token after signing in", async () => {
    window.history.replaceState(null, "", "/invite");
    window.sessionStorage.setItem(PENDING_INVITE_KEY, TOKEN);
    session.status = "authenticated";
    renderPage();
    await screen.findByRole("button", { name: "Join Box Kypseli" });
    expect(inspectInvitation).toHaveBeenCalledWith(TOKEN);
  });
});
