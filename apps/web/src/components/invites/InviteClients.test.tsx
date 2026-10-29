import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { ApiError } from "@/api/client";
import { bulkInvite, fetchJoinLink, issueClientInvitation, listPendingInvitations, resendInvitation, updateJoinLink } from "@/api/organizations";
import { InviteClientsDialog } from "./InviteClients";

const state = vi.hoisted(() => ({
  membership: null as unknown as Record<string, unknown>,
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, status: "authenticated" }),
}));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "kypseli" }));
vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "en" }));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membership: state.membership }) }));
vi.mock("@/api/facility", () => ({ listAdminLocations: vi.fn().mockResolvedValue([]) }));

vi.mock("@/api/organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/organizations")>();
  return {
    ...actual,
    issueClientInvitation: vi.fn(),
    listPendingInvitations: vi.fn(),
    bulkInvite: vi.fn(),
    resendInvitation: vi.fn(),
    revokeInvitation: vi.fn(),
    fetchJoinLink: vi.fn(),
    updateJoinLink: vi.fn(),
  };
});

function renderDialog(initialTab?: "link" | "bulk" | "public" | "pending") {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <InviteClientsDialog onClose={() => undefined} initialTab={initialTab} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const organization = { id: "org-1", slug: "kypseli", name: "Box Kypseli" };

beforeEach(() => {
  vi.clearAllMocks();
  state.membership = {
    role: "owner",
    roles: ["coach"],
    capabilities: {},
    organization: { ...organization, activation: "active" },
    settings: { brand_name: null, brand_logo_url: null, brand_primary_color: null, default_locale: "el" },
  };
  vi.mocked(listPendingInvitations).mockResolvedValue([]);
  vi.mocked(fetchJoinLink).mockResolvedValue({ member: { enabled: false }, athlete: { enabled: false, key: null } });
});

describe("Join links, one per role (ADR-216)", () => {
  it("switches each link on its own and both can be on", async () => {
    vi.mocked(fetchJoinLink).mockResolvedValue({ member: { enabled: true }, athlete: { enabled: false, key: null } });
    vi.mocked(updateJoinLink).mockResolvedValue({ member: { enabled: true }, athlete: { enabled: true, key: "Kq9_x-2" } });
    renderDialog("public");

    const member = await screen.findByRole("region", { name: "Link for box members" });
    expect(member).toHaveTextContent("Whoever uses it becomes a box member");
    expect(screen.getByDisplayValue(/\/join\/kypseli$/)).toBeInTheDocument();
    // ADR-255: the athlete link sits under «Advanced», closed by default.
    expect(screen.queryByRole("region", { name: "Link for athletes" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Advanced/ }));
    expect(screen.getByRole("region", { name: "Link for athletes" })).toHaveTextContent("Off.");
    expect(screen.queryByRole("radio", { name: /Athlete/ })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("switch", { name: "Link for athletes" }));
    await waitFor(() => expect(updateJoinLink).toHaveBeenCalledWith("access", "kypseli", { role: "athlete", enabled: true }));
    expect(await screen.findByDisplayValue(/\/join\/kypseli\/athlete\/Kq9_x-2$/)).toBeInTheDocument();
    expect(screen.getByRole("switch", { name: "Link for box members" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("switch", { name: "Link for athletes" })).toHaveAttribute("aria-checked", "true");
  });

  it("gives the athletes' link a new key only after confirming", async () => {
    vi.mocked(fetchJoinLink).mockResolvedValue({ member: { enabled: false }, athlete: { enabled: true, key: "old-key" } });
    vi.mocked(updateJoinLink).mockResolvedValue({ member: { enabled: false }, athlete: { enabled: true, key: "new-key" } });
    renderDialog("public");

    fireEvent.click(await screen.findByRole("button", { name: /Advanced/ }));
    fireEvent.click(await screen.findByRole("button", { name: "New athletes’ link" }));
    expect(updateJoinLink).not.toHaveBeenCalled();
    expect(screen.getByText(/The current link stops working right away/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Yes, make a new one" }));

    await waitFor(() => expect(updateJoinLink).toHaveBeenCalledWith("access", "kypseli", { role: "athlete", rotate_key: true }));
    expect(await screen.findByDisplayValue(/\/athlete\/new-key$/)).toBeInTheDocument();
  });
});

describe("Send by email (ADR-209)", () => {
  it("emails the invitation in the box's language and shows where it went", async () => {
    vi.mocked(issueClientInvitation).mockResolvedValue({
      organization,
      role: "member",
      roles: ["member"],
      expires_at: "2026-11-03T10:00:00Z",
      id: "inv-1",
      email: "nikos@example.com",
      delivery_status: "queued",
    });
    renderDialog();

    expect(screen.getByRole("button", { name: "Create invite link" })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(/Email \(optional\)/), { target: { value: "nikos@example.com" } });

    expect(screen.getByRole("combobox", { name: /Email language/ })).toHaveTextContent("Ελληνικά (your box’s language)");
    fireEvent.click(screen.getByRole("button", { name: "Send invitation" }));

    await screen.findByText("Invitation sent to nikos@example.com.");
    expect(issueClientInvitation).toHaveBeenCalledWith("access", "kypseli", expect.objectContaining({
      role: "member",
      intended_email: "nikos@example.com",
      send_email: true,
      email_locale: "el",
    }));
    expect(screen.queryByRole("button", { name: "Copy" })).not.toBeInTheDocument();
  });

  it("names an email refusal", async () => {
    vi.mocked(issueClientInvitation).mockRejectedValue(new ApiError(422, "error", { code: "suppressed", error: "x" }));
    renderDialog();
    fireEvent.change(screen.getByLabelText(/Email \(optional\)/), { target: { value: "bounce@example.com" } });
    fireEvent.click(screen.getByRole("button", { name: "Send invitation" }));
    await screen.findByText("Emails to this address bounce. Check it or use another one.");
  });

  it("explains demo mode instead of offering the form", () => {
    state.membership = { ...state.membership, organization: { ...organization, activation: "demo" } };
    renderDialog();
    expect(screen.getByRole("note")).toHaveTextContent("demo mode");
    expect(screen.queryByRole("button", { name: "Create invite link" })).not.toBeInTheDocument();
  });
});

describe("Several people", () => {
  it("counts the pasted addresses and sends one invitation each", async () => {
    vi.mocked(bulkInvite).mockResolvedValue({
      results: [
        { email: "a@example.com", status: "queued", invitation_id: "i1" },
        { email: "b@example.com", error: "suppressed" },
      ],
      sent: 1,
      failed: 1,
      skipped: [],
    });
    renderDialog("bulk");

    fireEvent.change(screen.getByLabelText(/^Email addresses/), { target: { value: "a@example.com, B@example.com\nnope" } });
    expect(screen.getByText("2 addresses")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Send 2 invitations" }));

    await screen.findByText("1 invitation sent.");
    expect(bulkInvite).toHaveBeenCalledWith("access", "kypseli", expect.objectContaining({ emails: ["a@example.com", "b@example.com"], email_locale: "el" }));
    expect(screen.getByText(/b@example.com: Emails to this address bounce/)).toBeInTheDocument();
  });
});

describe("Pending invitations", () => {
  it("shows the delivery status and resends an emailed invitation", async () => {
    vi.mocked(listPendingInvitations).mockResolvedValue([
      { id: "inv-1", role: "member", roles: ["member"], expires_at: "2026-11-03T10:00:00Z", issued_at: "2026-10-27T10:00:00Z", email_bound: true, email: "nikos@example.com", delivery_status: "bounced" },
      { id: "inv-2", role: "member", roles: ["member"], expires_at: "2026-11-03T10:00:00Z", issued_at: "2026-10-27T10:00:00Z", email_bound: false, email: null, delivery_status: null },
    ]);
    vi.mocked(resendInvitation).mockResolvedValue({ id: "inv-3", role: "member", expires_at: "2026-11-03T10:00:00Z", issued_at: "2026-10-27T11:00:00Z", email_bound: true, email: "nikos@example.com", delivery_status: "queued" });
    renderDialog("pending");

    await screen.findByText("nikos@example.com");
    expect(screen.getByText("Bounced")).toBeInTheDocument();
    const resend = screen.getAllByRole("button", { name: "Resend" });
    expect(resend).toHaveLength(1);
    fireEvent.click(resend[0]);
    await waitFor(() => expect(resendInvitation).toHaveBeenCalledWith("access", "kypseli", "inv-1"));
    await screen.findByText("Sent again to nikos@example.com. The previous link no longer works.");
  });
});
