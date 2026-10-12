import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  fetchOrganizationSlugImpact,
  renamePlatformOrganizationSlug,
  type OrganizationSlugImpact,
} from "@/api/platform-organizations";
import {
  OrganizationSlugRenameDialog,
  isValidOrganizationSlug,
} from "@/components/platform/OrganizationSlugRenameDialog";

vi.mock("@/api/platform-organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/platform-organizations")>();
  return {
    ...actual,
    fetchOrganizationSlugImpact: vi.fn(),
    renamePlatformOrganizationSlug: vi.fn(),
  };
});

const organization = {
  organization: {
    id: "org-1",
    slug: "harbor-gym",
    name: "Harbor Gym",
    status: "active" as const,
    inserted_at: "2026-08-04T00:00:00Z",
    updated_at: "2026-08-04T00:00:00Z",
  },
  settings: null,
  canonical_path: "/org/harbor-gym",
  pending_registration: false,
};

const impact: OrganizationSlugImpact = {
  organization: { id: "org-1", slug: "harbor-gym", name: "Harbor Gym", status: "active" },
  canonical_path: "/org/harbor-gym",
  active_member_count: 12,
  pending_invitation_count: 3,
  purge_open: false,
  previous_slugs: [{ slug: "old-harbor", retired_at: "2026-09-01T00:00:00Z" }],
};

function renderDialog(onRenamed = vi.fn()) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  render(
    <QueryClientProvider client={queryClient}>
      <OrganizationSlugRenameDialog
        accessToken="token"
        locale="en"
        organization={organization}
        onClose={vi.fn()}
        onRenamed={onRenamed}
      />
    </QueryClientProvider>,
  );

  return { onRenamed };
}

describe("OrganizationSlugRenameDialog", () => {
  beforeEach(() => {
    vi.mocked(fetchOrganizationSlugImpact).mockReset().mockResolvedValue(impact);
    vi.mocked(renamePlatformOrganizationSlug).mockReset();
  });

  it("shows the impact summary before anything can be renamed", async () => {
    renderDialog();

    expect(await screen.findByText("12 active members will move to the new path.")).toBeInTheDocument();
    expect(screen.getByText(/3 pending invitations keep working/)).toBeInTheDocument();
    expect(screen.getByText(/that use \/org\/harbor-gym keep working: they redirect/)).toBeInTheDocument();
    expect(screen.getByText(/old-harbor/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Change slug" })).toBeDisabled();
  });

  it("requires a valid new slug and the current slug retyped before submitting", async () => {
    vi.mocked(renamePlatformOrganizationSlug).mockResolvedValue({
      organization: impact.organization,
      canonical_path: "/org/north-harbor",
      previous_slug: "harbor-gym",
      previous_slugs: [{ slug: "harbor-gym", retired_at: "2026-10-12T00:00:00Z" }],
    });
    const { onRenamed } = renderDialog();
    await screen.findByText("12 active members will move to the new path.");

    const submit = screen.getByRole("button", { name: "Change slug" });
    fireEvent.change(screen.getByLabelText("New slug"), { target: { value: "North Harbor" } });
    fireEvent.change(screen.getByLabelText("Type harbor-gym to confirm"), { target: { value: "harbor-gym" } });
    expect(submit).toBeDisabled();

    fireEvent.change(screen.getByLabelText("New slug"), { target: { value: "north-harbor" } });
    fireEvent.change(screen.getByLabelText("Type harbor-gym to confirm"), { target: { value: "harbor" } });
    expect(submit).toBeDisabled();

    fireEvent.change(screen.getByLabelText("Type harbor-gym to confirm"), { target: { value: "harbor-gym" } });
    expect(screen.getByTestId("slug-new-path")).toHaveTextContent("/org/north-harbor");
    expect(submit).toBeEnabled();
    fireEvent.click(submit);

    await waitFor(() =>
      expect(renamePlatformOrganizationSlug).toHaveBeenCalledWith("token", "org-1", {
        slug: "north-harbor",
        confirmation: "harbor-gym",
      }),
    );
    expect(await screen.findByText("The organization now lives at /org/north-harbor.")).toBeInTheDocument();
    expect(onRenamed).toHaveBeenCalled();
  });

  it("explains a slug that is taken or reserved", async () => {
    vi.mocked(renamePlatformOrganizationSlug).mockRejectedValue(
      new ApiError(409, "taken", { code: "slug_taken" }),
    );
    renderDialog();
    await screen.findByText("12 active members will move to the new path.");

    fireEvent.change(screen.getByLabelText("New slug"), { target: { value: "other-gym" } });
    fireEvent.change(screen.getByLabelText("Type harbor-gym to confirm"), { target: { value: "harbor-gym" } });
    fireEvent.click(screen.getByRole("button", { name: "Change slug" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "This slug belongs to another organization or is reserved as its previous slug.",
    );
  });

  it("blocks the rename while a purge is open", async () => {
    vi.mocked(fetchOrganizationSlugImpact).mockResolvedValue({ ...impact, purge_open: true });
    renderDialog();

    expect(await screen.findByText(/Cancel it before changing the slug/)).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("New slug"), { target: { value: "north-harbor" } });
    fireEvent.change(screen.getByLabelText("Type harbor-gym to confirm"), { target: { value: "harbor-gym" } });
    expect(screen.getByRole("button", { name: "Change slug" })).toBeDisabled();
  });
});

describe("isValidOrganizationSlug", () => {
  it("mirrors the API slug policy", () => {
    expect(isValidOrganizationSlug("north-harbor")).toBe(true);
    expect(isValidOrganizationSlug("ab")).toBe(false);
    expect(isValidOrganizationSlug("north--harbor")).toBe(false);
    expect(isValidOrganizationSlug("-north")).toBe(false);
    expect(isValidOrganizationSlug("a".repeat(64))).toBe(false);
  });
});
