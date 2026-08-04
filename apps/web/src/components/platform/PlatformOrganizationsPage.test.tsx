import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";

import {
  changePlatformOrganizationLifecycle,
  deletePlatformOrganization,
  listPlatformOrganizations,
  provisionPlatformOrganization,
} from "@/api/platform-organizations";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" } }),
}));

vi.mock("@/i18n/use-ui-locale", () => ({
  useUiLocale: () => "en",
}));

vi.mock("@/api/platform-organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/platform-organizations")>();
  return {
    ...actual,
    changePlatformOrganizationLifecycle: vi.fn(),
    deletePlatformOrganization: vi.fn(),
    listPlatformOrganizations: vi.fn(),
    provisionPlatformOrganization: vi.fn(),
    changePlatformOrganizationSettings: vi.fn(),
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
    vi.mocked(listPlatformOrganizations).mockResolvedValue({ organizations: [organization] });
    vi.mocked(changePlatformOrganizationLifecycle).mockResolvedValue({
      organization: { ...organization.organization, status: "archived" },
    });
    vi.mocked(deletePlatformOrganization).mockResolvedValue(undefined);
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

  it("opens an active organization by selecting it and entering the admin dashboard", async () => {
    renderPage();

    const article = await screen.findByText("North Harbor Strength");
    const row = article.closest("article");
    expect(row).not.toBeNull();

    const openLink = within(row!).getByRole("link", { name: "Open organization" });
    expect(openLink).toHaveAttribute("href", "/admin");

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
});
