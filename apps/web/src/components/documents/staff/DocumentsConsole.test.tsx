import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import * as api from "@/api/documents";
import { DocumentsConsole } from "./DocumentsConsole";

const state = vi.hoisted(() => ({ capabilities: {} as Record<string, string> }));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ membership: { role: "owner", roles: ["owner"], capabilities: state.capabilities }, isLoading: false }),
}));
vi.mock("@/lib/organization-slug", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/organization-slug")>()),
  useOrganizationSlug: () => "box",
}));
vi.mock("@/api/documents", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/documents")>()),
  fetchDocumentTemplates: vi.fn(),
  fetchOutstanding: vi.fn(),
  fetchDocumentSettings: vi.fn(),
  fetchHealthCertificates: vi.fn(),
  fetchPendingRequests: vi.fn(),
  fetchSignatures: vi.fn(),
  fetchStarterDocuments: vi.fn(),
  requestSignatures: vi.fn(),
  createDocumentTemplate: vi.fn(),
  setDocumentRequirement: vi.fn(),
}));

const template = (id: string, title: string, requirement: api.DocumentRequirement): api.DocumentTemplate => ({
  id,
  kind: "terms",
  title,
  requirement,
  status: "active",
  current_version_id: `${id}-v3`,
  current_version_number: 3,
  required_version_number: 3,
  archived_at: null,
  inserted_at: "2026-10-01T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
});

const settings: api.DocumentSettings = {
  block_booking_on_unsigned: true,
  health_certificate_required: true,
  block_booking_on_health_certificate: true,
  health_certificate_validity_months: 12,
  health_certificate_reminder_days: 30,
};

function renderConsole() {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <DocumentsConsole />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  state.capabilities = { manage_settings: "all", manage_health_certificates: "all" };
  vi.mocked(api.fetchDocumentTemplates).mockResolvedValue([template("terms", "Terms of participation", "mandatory"), template("privacy", "Privacy notice", "optional")]);
  vi.mocked(api.fetchOutstanding).mockResolvedValue({
    clients: 8,
    templates: [
      {
        template_id: "terms",
        signed: 6,
        outstanding: 2,
        clients: [
          { user_id: "maria", display_name: "Maria K.", handle: null, status: "resign_required" },
          { user_id: "anna", display_name: "Anna Z.", handle: null, status: "unsigned" },
        ],
      },
      { template_id: "privacy", signed: 7, outstanding: 1, clients: [{ user_id: "anna", display_name: "Anna Z.", handle: null, status: "unsigned" }] },
    ],
  });
  vi.mocked(api.fetchDocumentSettings).mockResolvedValue(settings);
  vi.mocked(api.fetchHealthCertificates).mockResolvedValue({
    required: true,
    full_access: true,
    health_certificates: [
      {
        user_id: "nikos",
        display_name: "Nikos A.",
        handle: null,
        status: "expired",
        certificate: { id: "c1", user_id: "nikos", issued_on: "2025-10-20", expires_on: "2026-10-20", content_type: "image/jpeg", byte_size: 1, uploaded_by_id: null, inserted_at: "2025-10-20T00:00:00Z" },
      },
      { user_id: "eleni", display_name: "Eleni N.", handle: null, status: "valid", certificate: null },
    ],
  });
  vi.mocked(api.fetchPendingRequests).mockResolvedValue([
    { id: "r1", template_id: "terms", user_id: "anna", batch_id: null, audience: "person", status: "pending", requested_by_id: null, requested_at: "2026-10-25T09:00:00Z", signature_id: null, closed_at: null },
  ]);
  vi.mocked(api.fetchSignatures).mockResolvedValue([]);
  vi.mocked(api.requestSignatures).mockResolvedValue({ batch_id: "b", audience: "all_clients", recipients: 2, created: 1, skipped: 1, requests: [] });
});

describe("Χρήστες › Έγγραφα (s7 option B)", () => {
  it("lists each document with «missing N» and whether it blocks booking, then the health certificate", async () => {
    renderConsole();

    const terms = await screen.findByTestId("documents-row-terms");
    expect(within(terms).getByText("2 missing")).toBeInTheDocument();
    expect(within(terms).getByText(/blocks booking/)).toBeInTheDocument();
    expect(within(terms).getByText("Mandatory")).toBeInTheDocument();

    const privacy = screen.getByTestId("documents-row-privacy");
    expect(within(privacy).getByText("Optional")).toBeInTheDocument();
    expect(within(privacy).queryByText(/blocks booking/)).toBeNull();

    const health = screen.getByTestId("documents-row-health");
    expect(within(health).getByText("1 missing")).toBeInTheDocument();
    expect(screen.getByText(en.Documents.startersLine)).toBeInTheDocument();
  });

  it("opens a document's panel: who is missing, when they were asked, and a reminder to everyone", async () => {
    renderConsole();
    fireEvent.click(await screen.findByTestId("documents-row-terms"));

    const missing = await screen.findByTestId("missing-list");
    expect(within(missing).getByText("Maria K.")).toBeInTheDocument();
    expect(within(missing).getByText(en.Documents.detailResign)).toBeInTheDocument();
    await waitFor(() => expect(within(missing).getByText(/Asked .* · not signed/)).toBeInTheDocument());

    fireEvent.click(within(missing).getByRole("button", { name: "Remind everyone (2)" }));
    await waitFor(() => expect(api.requestSignatures).toHaveBeenCalledWith("access", "terms", { audience: "all_clients" }));
    expect(await screen.findByText(/Signature request sent to 1 person/)).toBeInTheDocument();
  });

  it("asks before a document becomes mandatory, saying how many clients it blocks now", async () => {
    vi.mocked(api.setDocumentRequirement).mockResolvedValue(template("privacy", "Privacy notice", "mandatory"));
    renderConsole();
    fireEvent.click(await screen.findByTestId("documents-row-privacy"));

    fireEvent.click(await screen.findByRole("radio", { name: "Mandatory" }));
    const confirm = await screen.findByRole("alertdialog", { name: /Bookings will be blocked/ });
    expect(confirm).toHaveTextContent("1 client will not be able to book until they sign.");
    expect(api.setDocumentRequirement).not.toHaveBeenCalled();

    fireEvent.click(within(confirm).getByRole("button", { name: "Back" }));
    expect(screen.queryByTestId("publish-confirm")).toBeNull();

    fireEvent.click(screen.getByRole("radio", { name: "Mandatory" }));
    fireEvent.click(await screen.findByRole("button", { name: "Yes, make it mandatory" }));
    await waitFor(() => expect(api.setDocumentRequirement).toHaveBeenCalledWith("access", "privacy", "mandatory"));
    expect(await screen.findByTestId("booking-block-warning")).toHaveTextContent(en.Documents.mandatoryBlocksBooking);
  });

  it("starts a new document from a starter, marked as a draft for legal review, and warns before a mandatory publish", async () => {
    vi.mocked(api.fetchStarterDocuments).mockResolvedValue([
      { kind: "waiver", language: "en", title: "Waiver", body: "DRAFT FOR LEGAL REVIEW\nText", requirement: "mandatory", draft: true, legal_review_required: true },
    ]);
    vi.mocked(api.createDocumentTemplate).mockResolvedValue({ template: template("new", "Waiver", "mandatory"), version: {} as api.DocumentVersion });
    renderConsole();

    fireEvent.click(await screen.findByRole("button", { name: "New document" }));
    const dialog = await screen.findByTestId("new-document-dialog");
    expect(await within(dialog).findByText("Draft for legal review")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: /Waiver/ }));

    expect(await screen.findByTestId("draft-banner")).toBeInTheDocument();
    expect(screen.getByTestId("booking-block-warning")).toHaveTextContent(en.Documents.publishBlocksBooking);
    fireEvent.click(screen.getByRole("button", { name: "Publish" }));
    // A new mandatory document blocks every client of the box until they sign.
    expect(await screen.findByTestId("publish-confirm")).toHaveTextContent("8 clients will not be able to book until they sign.");
    expect(api.createDocumentTemplate).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Yes, publish" }));
    await waitFor(() =>
      expect(api.createDocumentTemplate).toHaveBeenCalledWith("access", expect.objectContaining({ kind: "waiver", requirement: "mandatory", language: "en" })),
    );
  });

  it("lets front desk ask for signatures and see certificates, but not write documents, open the evidence or upload", async () => {
    state.capabilities = { request_signatures: "all", view_health_certificates: "all" };
    vi.mocked(api.fetchSignatures).mockResolvedValue([
      { id: "s1", template_id: "terms", version_number: 3, signed_at: "2026-10-20T10:00:00Z", typed_name: "Eleni N.", account: null } as unknown as api.Signature,
    ]);
    vi.mocked(api.requestSignatures).mockResolvedValue({ batch_id: "b", audience: "person", recipients: 1, created: 1, skipped: 0, requests: [] });
    renderConsole();

    expect(screen.queryByRole("button", { name: "New document" })).toBeNull();
    fireEvent.click(await screen.findByTestId("documents-row-terms"));
    const missing = await screen.findByTestId("missing-list");
    fireEvent.click(within(missing).getAllByRole("button", { name: "Ask" })[0]);
    await waitFor(() => expect(api.requestSignatures).toHaveBeenCalledWith("access", "terms", { audience: "person", user_id: "maria" }));

    const signed = await screen.findByTestId("signed-list");
    expect(within(signed).getByText("Eleni N.")).toBeInTheDocument();
    expect(within(signed).queryByRole("button", { name: "Certificate (PDF)" })).toBeNull();
    expect(screen.queryByRole("radio", { name: "Mandatory" })).toBeNull();
  });

  it("shows coaches only whether their clients' certificates are valid", async () => {
    state.capabilities = { view_health: "own" };
    vi.mocked(api.fetchHealthCertificates).mockResolvedValue({
      required: true,
      full_access: false,
      health_certificates: [
        { user_id: "nikos", display_name: "Nikos A.", handle: null, status: "expired", certificate: null },
        { user_id: "eleni", display_name: "Eleni N.", handle: null, status: "valid", certificate: null },
      ],
    });
    renderConsole();

    fireEvent.click(await screen.findByTestId("documents-row-health"));
    const list = await screen.findByTestId("health-status-list");
    expect(within(list).getByText("Expired")).toBeInTheDocument();
    expect(within(list).getByText("Valid")).toBeInTheDocument();
    expect(screen.queryByTestId("documents-row-terms")).toBeNull();
    expect(screen.queryByRole("button", { name: "New document" })).toBeNull();
    expect(api.fetchDocumentTemplates).not.toHaveBeenCalled();
  });
});
