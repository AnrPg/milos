import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  approveOrganizationPurge,
  cancelOrganizationPurge,
  fetchOrganizationPurge,
  requestOrganizationPurge,
  resumeOrganizationPurge,
  type OrganizationPurge,
} from "@/api/platform-organizations";
import { OrganizationPurgeDialog } from "@/components/platform/OrganizationPurgeDialog";

vi.mock("@/api/platform-organizations", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/platform-organizations")>();
  return {
    ...actual,
    approveOrganizationPurge: vi.fn(),
    cancelOrganizationPurge: vi.fn(),
    fetchOrganizationPurge: vi.fn(),
    requestOrganizationPurge: vi.fn(),
    resumeOrganizationPurge: vi.fn(),
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
  settings: null,
  canonical_path: "/org/north-harbor",
  pending_registration: false,
};

const exportedPurge: OrganizationPurge = {
  id: "purge-1",
  organization_id: "org-1",
  organization_slug: "north-harbor",
  status: "exported",
  failed_stage: null,
  failure_reason: null,
  requested_by_user_id: "vendor-1",
  requested_at: "2026-10-12T08:00:00Z",
  export_completed_at: "2026-10-12T08:01:00Z",
  export_byte_size: 2048,
  export_sha256: "abc123",
  retention_review: [
    {
      context: "finance",
      disposition: "retain",
      retain_years: 10,
      retained_until: "2036-10-12",
      basis: "Accounting records",
      record_count: 12,
      resources: [{ resource: "finance_invoices", count: 12 }],
    },
    {
      context: "workouts",
      disposition: "purge",
      retain_years: null,
      retained_until: null,
      basis: "Tenant content",
      record_count: 4,
      resources: [{ resource: "master_workouts", count: 4 }],
    },
  ],
  approved_by_user_id: null,
  approval_mode: null,
  approved_at: null,
  purge_started_at: null,
  steps: {},
  completed_at: null,
  cancelled_at: null,
};

function renderDialog(onChanged = vi.fn()) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  render(
    <QueryClientProvider client={queryClient}>
      <OrganizationPurgeDialog
        accessToken="token"
        locale="en"
        organization={organization}
        onClose={vi.fn()}
        onChanged={onChanged}
      />
    </QueryClientProvider>,
  );

  return { onChanged };
}

describe("OrganizationPurgeDialog", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("requests a purge when none exists", async () => {
    vi.mocked(fetchOrganizationPurge)
      .mockRejectedValueOnce(new ApiError(404, "Not found", { code: "not_found" }))
      .mockResolvedValue({ purge: { ...exportedPurge, status: "requested", retention_review: [] }, export_download_url: null });
    vi.mocked(requestOrganizationPurge).mockResolvedValue({ purge: { ...exportedPurge, status: "requested" } });

    const { onChanged } = renderDialog();

    fireEvent.click(await screen.findByRole("button", { name: "Request export & purge" }));

    await waitFor(() => expect(requestOrganizationPurge).toHaveBeenCalledWith("token", "org-1"));
    expect(await screen.findByTestId("purge-status")).toHaveTextContent("Requested");
    expect(onChanged).toHaveBeenCalled();
  });

  it("shows the export link and retention review, and approves only after the typed slug", async () => {
    vi.mocked(fetchOrganizationPurge).mockResolvedValue({
      purge: exportedPurge,
      export_download_url: "https://objects.test/export.zip",
    });
    vi.mocked(approveOrganizationPurge).mockResolvedValue({
      purge: { ...exportedPurge, status: "approved", approval_mode: "typed_confirmation" },
    });

    renderDialog();

    expect(await screen.findByRole("link", { name: "Download export (ZIP)" })).toHaveAttribute(
      "href",
      "https://objects.test/export.zip",
    );
    expect(screen.getByText("finance")).toBeInTheDocument();
    expect(screen.getByText("Retain")).toBeInTheDocument();
    expect(screen.getByText("2036-10-12")).toBeInTheDocument();

    const approve = screen.getByRole("button", { name: "Approve and purge" });
    expect(approve).toBeDisabled();

    fireEvent.change(screen.getByLabelText("Type north-harbor to confirm"), { target: { value: "north" } });
    expect(approve).toBeDisabled();

    fireEvent.change(screen.getByLabelText("Type north-harbor to confirm"), { target: { value: "north-harbor" } });
    expect(approve).toBeEnabled();
    fireEvent.click(approve);

    await waitFor(() =>
      expect(approveOrganizationPurge).toHaveBeenCalledWith("token", "org-1", "north-harbor"),
    );
  });

  it("offers retry for a failed stage and cancel before approval", async () => {
    vi.mocked(fetchOrganizationPurge).mockResolvedValue({
      purge: { ...exportedPurge, status: "failed", failed_stage: "export", failure_reason: "object_store_failed" },
      export_download_url: null,
    });
    vi.mocked(resumeOrganizationPurge).mockResolvedValue({ purge: { ...exportedPurge, status: "requested" } });
    vi.mocked(cancelOrganizationPurge).mockResolvedValue({ purge: { ...exportedPurge, status: "cancelled" } });

    renderDialog();

    expect(await screen.findByText("The export stage failed: object_store_failed.")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    await waitFor(() => expect(resumeOrganizationPurge).toHaveBeenCalledWith("token", "org-1"));

    fireEvent.click(screen.getByRole("button", { name: "Cancel purge" }));
    await waitFor(() => expect(cancelOrganizationPurge).toHaveBeenCalledWith("token", "org-1"));
  });

  it("surfaces server errors from purge actions", async () => {
    vi.mocked(fetchOrganizationPurge).mockResolvedValue({ purge: exportedPurge, export_download_url: null });
    vi.mocked(cancelOrganizationPurge).mockRejectedValue(
      new ApiError(409, "Conflict", { code: "invalid_purge_transition", error: "Not allowed now" }),
    );

    renderDialog();

    fireEvent.click(await screen.findByRole("button", { name: "Cancel purge" }));
    expect(await screen.findByText("Not allowed now")).toBeInTheDocument();
  });
});
