import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";

import {
  changePlatformOrganizationLifecycle,
  changePlatformOrganizationSettings,
  deletePlatformOrganization,
  fetchPlatformOrganizationAccess,
  issuePlatformOrganizationInvitation,
  listPlatformOrganizations,
  provisionPlatformOrganization,
  renamePlatformOrganization,
  sendOwnerInvitationEmail,
  updatePlatformOrganizationMembershipRole,
} from "@/api/platform-organizations";
import { fetchOrganizationMemberships } from "@/api/organizations";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" } }),
}));

vi.mock("@/i18n/use-ui-locale", () => ({
  useUiLocale: () => "en",
}));

vi.mock("@/api/organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/organizations")>();
  return {
    ...actual,
    fetchOrganizationMemberships: vi.fn(),
  };
});

vi.mock("@/api/platform-organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/platform-organizations")>();
  return {
    ...actual,
    changePlatformOrganizationLifecycle: vi.fn(),
    deletePlatformOrganization: vi.fn(),
    fetchPlatformOrganizationAccess: vi.fn(),
    issuePlatformOrganizationInvitation: vi.fn(),
    listPlatformOrganizations: vi.fn(),
    provisionPlatformOrganization: vi.fn(),
    updatePlatformOrganizationMembershipRole: vi.fn(),
    changePlatformOrganizationSettings: vi.fn(),
    renamePlatformOrganization: vi.fn(),
    sendOwnerInvitationEmail: vi.fn(),
  };
});

const organization = {
  organization: {
    id: "org-1",
    slug: "north-harbor",
    name: "North Harbor Strength",
    status: "active" as const,
    inserted_at: "2026-08-04T00:00:00Z",
    updated_at: "2026-08-04T00:00:00Z",
  },
  settings: {
    organization_id: "org-1",
    timezone: "Europe/Athens",
    default_locale: "en",
    invitation_lifetime_seconds: 604_800,
    brand_name: "North Harbor",
    brand_logo_url: null,
    brand_primary_color: "#1f6f5f",
    settings: {},
  },
  canonical_path: "/org/north-harbor",
};

function renderPage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <PlatformOrganizationsPage />
    </QueryClientProvider>,
  );
}

describe("PlatformOrganizationsPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    vi.mocked(fetchOrganizationMemberships).mockResolvedValue([]);
    vi.mocked(listPlatformOrganizations).mockResolvedValue({ organizations: [organization] });
    vi.mocked(changePlatformOrganizationLifecycle).mockResolvedValue({
      organization: { ...organization.organization, status: "archived" },
    });
    vi.mocked(deletePlatformOrganization).mockResolvedValue(undefined);
    vi.mocked(sendOwnerInvitationEmail).mockResolvedValue(undefined);
    vi.mocked(renamePlatformOrganization).mockResolvedValue({
      organization: { ...organization.organization, name: "North Harbor Strength" },
    });
    vi.mocked(changePlatformOrganizationSettings).mockResolvedValue({ settings: organization.settings });
    vi.mocked(fetchPlatformOrganizationAccess).mockResolvedValue({
      organization: organization.organization,
      memberships: [
        {
          id: "membership-1",
          user_id: "user-1",
          role: "member",
          status: "active",
          joined_at: "2026-08-04T00:00:00Z",
          inserted_at: "2026-08-04T00:00:00Z",
          updated_at: "2026-08-04T00:00:00Z",
          user: {
            id: "user-1",
            nickname: "maria",
            role: "member",
            avatar_url: null,
          },
        },
      ],
    });
    vi.mocked(issuePlatformOrganizationInvitation).mockResolvedValue({
      invitation: {
        token: "coach-invite-token",
        expires_at: "2026-08-11T00:00:00Z",
        role: "coach",
      },
    });
    vi.mocked(updatePlatformOrganizationMembershipRole).mockResolvedValue({
      membership: {
        id: "membership-1",
        user_id: "user-1",
        role: "athlete",
        status: "active",
        joined_at: "2026-08-04T00:00:00Z",
        inserted_at: "2026-08-04T00:00:00Z",
        updated_at: "2026-08-04T00:00:00Z",
        user: null,
      },
    });
    vi.mocked(provisionPlatformOrganization).mockResolvedValue({
      organization: { ...organization.organization, id: "org-2", name: "Atlas Gym", slug: "atlas" },
      settings: { ...organization.settings, organization_id: "org-2", brand_name: "Atlas Gym" },
      initial_owner_invitation: {
        token: "invite-token",
        expires_at: "2026-08-11T00:00:00Z",
        role: "owner",
      },
      canonical_path: "/org/atlas",
    });
  });

  it("opens the organization creation form in a dialog", async () => {
    renderPage();

    await screen.findByText("North Harbor Strength");
    expect(screen.queryByRole("dialog", { name: "Create organization" })).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Organization name")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Create organization" }));

    const dialog = screen.getByRole("dialog", { name: "Create organization" });
    expect(within(dialog).getByLabelText("Organization name")).toBeInTheDocument();
    expect(within(dialog).getByRole("button", { name: "Provision organization" })).toBeInTheDocument();
  });

  it("requires an owner email before provisioning, and offers to email the setup link afterward", async () => {
    renderPage();

    await screen.findByText("North Harbor Strength");
    fireEvent.click(screen.getByRole("button", { name: "Create organization" }));

    const dialog = screen.getByRole("dialog", { name: "Create organization" });
    expect(within(dialog).getByLabelText("Initial owner email")).toBeRequired();

    fireEvent.change(within(dialog).getByLabelText("Organization name"), {
      target: { value: "Atlas Gym" },
    });
    fireEvent.change(within(dialog).getByLabelText("Initial owner email"), {
      target: { value: "owner@atlas.test" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Provision organization" }));

    await waitFor(() => {
      expect(provisionPlatformOrganization).toHaveBeenCalledWith(
        "token",
        expect.objectContaining({ name: "Atlas Gym", initial_owner_email: "owner@atlas.test" }),
      );
    });

    const sendButton = await screen.findByRole("button", { name: /owner@atlas\.test/ });
    fireEvent.click(sendButton);

    await waitFor(() => {
      expect(sendOwnerInvitationEmail).toHaveBeenCalledWith("token", "org-2", {
        email: "owner@atlas.test",
        token: "invite-token",
      });
    });

    expect(await screen.findByRole("button", { name: "Email sent" })).toBeInTheDocument();
  });

  it("archives an organization only after explicit confirmation", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    fireEvent.click(within(row!).getByRole("button", { name: "Archive" }));
    expect(changePlatformOrganizationLifecycle).not.toHaveBeenCalled();

    const dialog = screen.getByRole("dialog", { name: "Archive organization" });
    fireEvent.click(within(dialog).getByRole("button", { name: "Archive organization" }));

    await waitFor(() => {
      expect(changePlatformOrganizationLifecycle).toHaveBeenCalledWith("token", "org-1", "archived");
    });
  });

  it("does not offer to open an organization the vendor has no membership in", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    expect(within(row!).queryByRole("link", { name: "Open organization" })).not.toBeInTheDocument();
    expect(screen.queryByText("Your memberships")).not.toBeInTheDocument();
  });

  it("opens an organization the vendor is a member of, routed by their role there", async () => {
    vi.mocked(fetchOrganizationMemberships).mockResolvedValue([
      {
        id: "membership-vendor-1",
        role: "owner",
        organization: { id: "org-1", slug: "north-harbor", name: "North Harbor Strength" },
      },
    ]);

    renderPage();

    await screen.findByText("Your memberships");
    const quickLink = screen.getByRole("link", { name: /North Harbor Strength/ });
    expect(quickLink).toHaveAttribute("href", "/org/north-harbor/admin");

    const mentions = await screen.findAllByText("North Harbor Strength");
    const row = mentions.map((node) => node.closest("article")).find((node) => node !== null);
    expect(row).not.toBeNull();

    const openLink = within(row!).getByRole("link", { name: "Open organization" });
    expect(openLink).toHaveAttribute("href", "/org/north-harbor/admin");

    fireEvent.click(openLink);

    expect(window.localStorage.getItem("milos:selected-organization-slug")).toBe("north-harbor");
  });

  it("permanently deletes an organization only after explicit confirmation", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    fireEvent.click(within(row!).getByRole("button", { name: "Delete permanently" }));
    expect(deletePlatformOrganization).not.toHaveBeenCalled();

    const dialog = screen.getByRole("dialog", { name: "Permanently delete organization" });
    fireEvent.click(within(dialog).getByRole("button", { name: "Delete permanently" }));

    await waitFor(() => {
      expect(deletePlatformOrganization).toHaveBeenCalledWith("token", "org-1");
    });
  });

  it("renames an organization from the settings dialog only when the name actually changed", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    fireEvent.click(within(row!).getByRole("button", { name: "Edit settings" }));

    const dialog = screen.getByRole("dialog", { name: "Settings" });
    const nameField = within(dialog).getByLabelText("Organization name");
    expect(nameField).toHaveValue("North Harbor Strength");

    fireEvent.change(nameField, { target: { value: "North Harbor Fitness" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save settings" }));

    await waitFor(() => {
      expect(renamePlatformOrganization).toHaveBeenCalledWith("token", "org-1", "North Harbor Fitness");
      expect(changePlatformOrganizationSettings).toHaveBeenCalled();
    });
  });

  it("does not call rename when the settings dialog is saved with the name unchanged", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    fireEvent.click(within(row!).getByRole("button", { name: "Edit settings" }));

    const dialog = screen.getByRole("dialog", { name: "Settings" });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save settings" }));

    await waitFor(() => {
      expect(changePlatformOrganizationSettings).toHaveBeenCalled();
    });
    expect(renamePlatformOrganization).not.toHaveBeenCalled();
  });

  it("manages tenant access with role-specific invitations and membership roles", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    fireEvent.click(within(row!).getByRole("button", { name: "Manage access" }));

    const dialog = screen.getByRole("dialog", { name: "Access" });
    expect(await within(dialog).findByText("maria")).toBeInTheDocument();

    fireEvent.change(within(dialog).getByLabelText("Invite role"), { target: { value: "coach" } });
    fireEvent.change(within(dialog).getByLabelText("Email hint (optional)"), {
      target: { value: "coach@example.test" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Invite" }));

    await waitFor(() => {
      expect(issuePlatformOrganizationInvitation).toHaveBeenCalledWith("token", "org-1", {
        role: "coach",
        intended_email: "coach@example.test",
        lifetime_seconds: 604_800,
      });
    });

    expect(await within(dialog).findByText("coach-invite-token")).toBeInTheDocument();

    fireEvent.change(within(dialog).getByLabelText("Tenant role"), { target: { value: "athlete" } });

    await waitFor(() => {
      expect(updatePlatformOrganizationMembershipRole).toHaveBeenCalledWith(
        "token",
        "org-1",
        "membership-1",
        "athlete",
      );
    });
  });
});
