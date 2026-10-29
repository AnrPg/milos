import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { useState, type ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import * as api from "@/api/documents";
import { DocumentsBoxCard } from "./DocumentsBoxCard";
import { DocumentsGate } from "./DocumentsGate";
import { gateSteps } from "./documents-model";
import { MyDocuments } from "./MyDocuments";
import { SignDocument } from "./SignDocument";

const push = vi.fn();

vi.mock("next/navigation", () => ({ useRouter: () => ({ push, replace: vi.fn(), back: vi.fn() }), usePathname: () => "/box/documents" }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({
    membership: { role: "member", roles: ["member"], capabilities: {}, organization: { name: "CrossFit Kifisia" }, settings: {} },
    isLoading: false,
  }),
}));
vi.mock("@/lib/organization-slug", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/organization-slug")>()),
  useOrganizationSlug: () => "box",
}));
vi.mock("@/api/documents", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/documents")>()),
  fetchMyDocuments: vi.fn(),
  fetchMyDocument: vi.fn(),
  fetchMySignatures: vi.fn(),
  signMyDocument: vi.fn(),
}));

const item = (template_id: string, title: string, patch: Partial<api.DocumentItem> = {}): api.DocumentItem => ({
  template_id,
  kind: "terms",
  title,
  requirement: "mandatory",
  current_version_id: `${template_id}-v3`,
  current_version_number: 3,
  status: "unsigned",
  outstanding: true,
  requested: false,
  signature: null,
  ...patch,
});

const overview = (documents: api.DocumentItem[], health: api.MyDocumentsOverview["health_certificate"]): api.MyDocumentsOverview => ({
  documents,
  outstanding: documents.filter((document) => document.outstanding).length,
  health_certificate: health,
});

function wrap(children: ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        {children}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const version = (id: string): api.DocumentVersion =>
  ({ id, template_id: "terms", number: 3, title: "Terms of participation", body: "1. I train at my own risk.", change_kind: "major" }) as api.DocumentVersion;

beforeEach(() => {
  vi.clearAllMocks();
  // jsdom has no canvas: the pad draws nothing, which is fine here.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(null);
  vi.mocked(api.fetchMySignatures).mockResolvedValue([]);
  vi.mocked(api.fetchMyDocument).mockResolvedValue({
    template: { id: "terms", title: "Terms of participation" } as api.DocumentTemplate,
    version: version("terms-v3"),
    status: "unsigned",
  });
  vi.mocked(api.signMyDocument).mockResolvedValue({ id: "sig" } as api.Signature);
});

describe("Box › «N documents missing» card", () => {
  it("shows while something mandatory is missing", async () => {
    vi.mocked(api.fetchMyDocuments).mockResolvedValue(
      overview([item("terms", "Terms"), item("privacy", "Privacy", { requirement: "optional", outstanding: false })], {
        required: true,
        status: "missing",
        certificate: null,
      }),
    );
    wrap(<DocumentsBoxCard />);
    const card = await screen.findByTestId("box-documents-card");
    expect(card).toHaveTextContent("2 documents missing");
    expect(card).toHaveAttribute("href", "/box/documents");
  });

  it("is hidden once everything is signed", async () => {
    vi.mocked(api.fetchMyDocuments).mockResolvedValue(
      overview([item("terms", "Terms", { status: "signed", outstanding: false })], { required: false, status: "missing", certificate: null }),
    );
    wrap(<DocumentsBoxCard />);
    await waitFor(() => expect(api.fetchMyDocuments).toHaveBeenCalled());
    expect(screen.queryByTestId("box-documents-card")).toBeNull();
  });
});

describe("Box › Documents", () => {
  it("lists what is missing first, opens it to sign, and offers the certificate of past signatures", async () => {
    vi.mocked(api.fetchMyDocuments).mockResolvedValue(
      overview(
        [
          item("privacy", "Privacy notice", { status: "signed", outstanding: false, signature: { id: "s1", version_number: 1, signed_at: "2026-09-01T10:00:00Z", content_hash: "h" } }),
          item("terms", "Terms of participation", { status: "resign_required" }),
        ],
        { required: true, status: "missing", certificate: null },
      ),
    );
    vi.mocked(api.fetchMySignatures).mockResolvedValue([{ id: "s1", template_id: "privacy", version_number: 1, signed_at: "2026-09-01T10:00:00Z" } as api.Signature]);
    wrap(<MyDocuments />);

    const terms = await screen.findByTestId("my-doc-terms");
    expect(terms).toHaveTextContent(en.Documents.detailResign);
    expect(terms).toHaveTextContent("Missing");
    expect(screen.getByTestId("my-doc-health")).toHaveTextContent(en.Documents.healthDetailMissing);
    // Outstanding first, then the signed one.
    const rows = screen.getAllByTestId(/^my-doc-/).map((row) => row.dataset.testid);
    expect(rows.indexOf("my-doc-terms")).toBeLessThan(rows.indexOf("my-doc-privacy"));

    fireEvent.click(terms);
    expect(push).toHaveBeenCalledWith("/box/documents/terms");
    expect(await screen.findByRole("button", { name: "Certificate (PDF)" })).toBeInTheDocument();
  });
});

describe("Read and sign", () => {
  it("signs with a typed name once the text has loaded", async () => {
    const onSigned = vi.fn();
    wrap(<SignDocument templateId="terms" boxName="CrossFit Kifisia" onSigned={onSigned} />);

    expect(await screen.findByText("1. I train at my own risk.")).toBeInTheDocument();
    const sign = screen.getByRole("button", { name: "Sign" });
    expect(sign).toBeDisabled();

    fireEvent.change(screen.getByLabelText("Or type your full name"), { target: { value: "Maria  Kosta" } });
    fireEvent.click(sign);
    await waitFor(() => expect(onSigned).toHaveBeenCalled());
    expect(api.signMyDocument).toHaveBeenCalledWith("access", "terms", { version_id: "terms-v3", agreed: true, typed_name: "Maria Kosta" });
  });
});

function GateHarness({ required }: { required: api.DocumentsRequired }) {
  const steps = gateSteps(required);
  const [done, setDone] = useState<Set<string>>(() => new Set());
  const [open, setOpen] = useState<string | null>(null);
  return <DocumentsGate steps={steps} done={done} openKey={open} onOpen={setOpen} onDone={(key) => setDone((current) => new Set(current).add(key))} />;
}

describe("Booking › documents required", () => {
  it("lists what is missing, signs it in place and comes back ready to book", async () => {
    wrap(
      <GateHarness
        required={{ documents: [{ template_id: "terms", title: "Terms of participation", kind: "terms", reason: "resign_required" }], health_certificate: "expired" }}
      />,
    );

    const gate = screen.getByTestId("documents-gate");
    expect(gate).toHaveTextContent(en.Documents.gateMissing);
    expect(within(gate).getByTestId("gate-step-terms")).toHaveTextContent(en.Documents.gateResign);
    expect(within(gate).getByTestId("gate-step-health")).toHaveTextContent(en.Documents.gateHealthExpired);

    fireEvent.click(within(gate).getByTestId("gate-step-terms"));
    expect(await screen.findByRole("button", { name: /Back to booking/ })).toBeInTheDocument();
    fireEvent.change(await screen.findByLabelText("Or type your full name"), { target: { value: "Maria Kosta" } });
    fireEvent.click(screen.getByRole("button", { name: "Sign" }));

    const back = await screen.findByTestId("documents-gate");
    expect(within(back).getByTestId("gate-step-terms")).toHaveTextContent(en.Documents.gateDone);
    expect(within(back).getByTestId("gate-step-terms")).toBeDisabled();
    expect(back).toHaveTextContent(en.Documents.gateMissing);
  });
});
