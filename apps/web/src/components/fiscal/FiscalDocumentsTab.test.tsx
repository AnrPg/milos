import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import { chooseValue } from "@/components/ui/select-test-utils";

import { localToday } from "./documents-model";

// Mockup s2, option A grouped per day with «Κλειστή» / «Ανοιχτή» (product owner's change).

const today = localToday();
const yesterday = (() => {
  const date = new Date(`${today}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
})();

const base = {
  content_hash: "h",
  country_code: "GR",
  currency: "EUR",
  journal_position: 1,
  language: "el",
  net_cents: 0,
  prices_include_tax: true,
  seller: { legal_name: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.", tax_id: "801234567" },
  sequence: 1,
  series: "R",
  tax_breakdown: [],
  tax_cents: 0,
  buyer: null,
  payment_method: "card",
};
const accepted = { id: "t1", document_id: "d1", authority: "mydata", attempts: 1, status: "accepted", mark: "400001234567890" };
const r418 = { ...base, id: "d1", number: "R-000418", kind: "receipt", gross_cents: 12400, issue_date: today, issued_at: `${today}T10:42:00Z`, transmission: accepted };
const r417 = { ...base, id: "d2", number: "R-000417", kind: "receipt", gross_cents: 1500, issue_date: today, issued_at: `${today}T09:05:00Z`, transmission: { ...accepted, id: "t2", document_id: "d2", status: "pending", mark: null } };
const i031 = { ...base, id: "d3", number: "I-000031", kind: "invoice", gross_cents: 45000, issue_date: yesterday, issued_at: `${yesterday}T18:20:00Z`, buyer: { name: "ACME Α.Ε." }, payment_method: "bank_transfer", transmission: { ...accepted, id: "t3", document_id: "d3" } };

const detail = {
  ...r418,
  lines: [
    { position: 1, description: "Πακέτο συνδρομής «12 επισκέψεις»", quantity: 1, rate_bp: 2400, gross_cents: 9000, net_cents: 7258, tax_cents: 1742, amount_cents: 9000, discount_cents: 0, unit_price_cents: 9000, tax_category: "standard" },
    { position: 2, description: "Λαβές για pull-ups", quantity: 1, rate_bp: 2400, gross_cents: 3400, net_cents: 2742, tax_cents: 658, amount_cents: 3400, discount_cents: 0, unit_price_cents: 3400, tax_category: "standard" },
  ],
  tax_breakdown: [{ tax_category: "standard", rate_bp: 2400, net_cents: 10000, tax_cents: 2400, gross_cents: 12400 }],
  credit_notes: [],
};

const api = vi.hoisted(() => ({
  listFiscalDocuments: vi.fn(),
  listClosings: vi.fn(),
  fetchFiscalDocument: vi.fn(),
  issueCreditNote: vi.fn(),
  retryTransmission: vi.fn(),
  fetchDocumentHtml: vi.fn(),
  fetchDocumentPdf: vi.fn(),
  verifyJournal: vi.fn(),
  fetchAuditArchive: vi.fn(),
  fetchExportFormats: vi.fn(),
  saveExportSettings: vi.fn(),
  fetchAccountingExport: vi.fn(),
  saveBlob: vi.fn(),
}));

vi.mock("@/api/fiscal", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));

import { FiscalDocumentsTab } from "./FiscalDocumentsTab";

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        <FiscalDocumentsTab />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("FiscalDocumentsTab", () => {
  beforeEach(() => {
    Object.values(api).forEach((mock) => mock.mockReset());
    api.listFiscalDocuments.mockResolvedValue({ documents: [r418, r417, i031], total: 3 });
    api.listClosings.mockImplementation(async (_token: string, filters: { limit?: number }) => ({
      closings: [
        {
          id: "c1",
          period_kind: "day",
          period_start: yesterday,
          period_end: yesterday,
          closed_at: `${today}T00:05:00Z`,
          journal_position: 9,
          totals: { EUR: { documents: 14, gross_cents: 61200, grand_total_cents: 4821000 } },
        },
      ].slice(0, filters.limit ?? 10),
    }));
    api.fetchFiscalDocument.mockResolvedValue({ document: detail });
  });

  it("groups the documents per day, today open and a closed day «Closed»", async () => {
    wrap();

    const todayGroup = await screen.findByTestId(`fiscal-day-${today}`);
    expect(within(todayGroup).getByRole("heading")).toHaveTextContent(/^Today, /);
    expect(within(todayGroup).getByTestId("fiscal-day-state")).toHaveTextContent(en.FiscalDocuments.dayOpen);
    expect(within(todayGroup).getByTestId("fiscal-doc-R-000417")).toHaveTextContent(en.FiscalDocuments.txPending);
    const closedGroup = screen.getByTestId(`fiscal-day-${yesterday}`);
    expect(within(closedGroup).getByTestId("fiscal-day-state")).toHaveTextContent(en.FiscalDocuments.dayClosed);
    expect(within(closedGroup).getByTestId("fiscal-doc-I-000031")).toHaveTextContent("I-000031 · ACME Α.Ε.");
    expect(api.listClosings).toHaveBeenCalledWith("token", expect.objectContaining({ kind: "day" }));

    fireEvent.click(screen.getByTestId("fiscal-filter-pending"));
    expect(screen.queryByTestId(`fiscal-day-${yesterday}`)).not.toBeInTheDocument();
    expect(screen.getByTestId("fiscal-doc-R-000417")).toBeInTheDocument();
    expect(screen.queryByTestId("fiscal-doc-R-000418")).not.toBeInTheDocument();
  });

  it("asks the API for one kind and one number", async () => {
    wrap();
    await screen.findByTestId("fiscal-doc-R-000418");

    fireEvent.click(screen.getByTestId("fiscal-filter-invoice"));
    await waitFor(() => expect(api.listFiscalDocuments).toHaveBeenLastCalledWith("token", expect.objectContaining({ kind: "invoice" })));
    fireEvent.change(screen.getByTestId("fiscal-search"), { target: { value: "000031" } });
    await waitFor(() => expect(api.listFiscalDocuments).toHaveBeenLastCalledWith("token", expect.objectContaining({ number: "000031", kind: "invoice" })));
  });

  it("opens a document with its lines, VAT and myDATA mark, and issues a partial credit note", async () => {
    api.issueCreditNote.mockResolvedValue({ document: { ...r418, id: "c9", kind: "credit_note", number: "C-000010" } });
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-doc-R-000418"));
    const panel = await screen.findByTestId("fiscal-document-panel");
    await within(panel).findByText("Λαβές για pull-ups");
    expect(panel).toHaveTextContent("Net value 24% · VAT €24.00");
    expect(panel).toHaveTextContent("400001234567890");
    expect(panel).toHaveTextContent("ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε. · 801234567");

    fireEvent.click(within(panel).getByTestId("fiscal-doc-credit"));
    const credit = await screen.findByTestId("fiscal-credit-panel");
    expect(within(credit).getByTestId("fiscal-credit-amount")).toHaveTextContent("-€124.00");
    fireEvent.click(within(credit).getByTestId("fiscal-credit-part"));
    expect(within(credit).getByTestId("fiscal-credit-issue")).toBeDisabled();
    fireEvent.click(within(credit).getByTestId("fiscal-credit-line-2"));
    expect(within(credit).getByTestId("fiscal-credit-amount")).toHaveTextContent("-€34.00");
    fireEvent.click(within(credit).getByTestId("fiscal-credit-issue"));

    await waitFor(() => expect(api.issueCreditNote).toHaveBeenCalledWith("token", "d1", expect.any(String), [{ position: 2, quantity: 1 }]));
    await screen.findByTestId("fiscal-document-panel");
  });

  it("shows a pending transmission and retries a failed one", async () => {
    api.fetchFiscalDocument.mockResolvedValue({ document: { ...detail, id: "d2", number: "R-000417", transmission: { ...r417.transmission, status: "failed" } } });
    api.retryTransmission.mockResolvedValue({ transmission: { ...r417.transmission, status: "pending" } });
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-doc-R-000417"));
    const box = await screen.findByTestId("fiscal-doc-tx");
    expect(box).toHaveTextContent(en.FiscalDocuments.txPendingTitle);
    fireEvent.click(within(box).getByTestId("fiscal-doc-retry"));
    await waitFor(() => expect(api.retryTransmission).toHaveBeenCalledWith("token", "d2"));
  });

  it("shows the document in another language and downloads its PDF", async () => {
    api.fetchDocumentHtml.mockResolvedValue("<p>Receipt</p>");
    api.fetchDocumentPdf.mockResolvedValue(new Blob(["%PDF"]));
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-doc-R-000418"));
    fireEvent.click(await screen.findByTestId("fiscal-doc-pdf"));
    const view = await screen.findByTestId("fiscal-document-view");
    await within(view).findByTestId("fiscal-view-frame");
    expect(api.fetchDocumentHtml).toHaveBeenCalledWith("token", "d1", undefined);

    chooseValue(within(view).getByTestId("fiscal-view-language"), "en");
    await waitFor(() => expect(api.fetchDocumentHtml).toHaveBeenLastCalledWith("token", "d1", "en"));
    fireEvent.click(within(view).getByTestId("fiscal-view-pdf"));
    await waitFor(() => expect(api.saveBlob).toHaveBeenCalledWith(expect.any(Blob), "R-000418-en.pdf"));
  });

  it("checks the audit archive and downloads it", async () => {
    api.verifyJournal.mockResolvedValue({ verification: { valid: true, entries: 1284 } });
    api.fetchAuditArchive.mockResolvedValue(new Blob(["zip"]));
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-audit-open"));
    const dialog = await screen.findByTestId("fiscal-audit-dialog");
    await within(dialog).findByText(/documents: 14 · €612.00/);
    expect(dialog).toHaveTextContent("€48,210.00");

    fireEvent.click(within(dialog).getByTestId("fiscal-audit-verify"));
    expect(await within(dialog).findByTestId("fiscal-audit-result")).toHaveTextContent("OK");
    expect(dialog).toHaveTextContent("Entries: 1284");

    fireEvent.click(within(dialog).getByTestId("fiscal-audit-period-year"));
    fireEvent.click(within(dialog).getByTestId("fiscal-audit-download"));
    const year = today.slice(0, 4);
    await waitFor(() => expect(api.fetchAuditArchive).toHaveBeenCalledWith("token", `${year}-01-01`, `${year}-12-31`));
    expect(await within(dialog).findByTestId("fiscal-audit-started")).toHaveTextContent(`palee-fiscal-${year}-01-01-${year}-12-31.zip`);
  });

  it("exports a period for the accountant and saves the format's settings", async () => {
    api.fetchExportFormats.mockResolvedValue({
      formats: [
        { id: "csv", name: "CSV", description: "Flat CSV", file_extension: "csv", file_prefix: "palee-fiscal", content_type: "text/csv", options: [{ key: "separator", type: "enum", values: [",", ";"], default: ",", description: "Field separator" }] },
        { id: "datev", name: "DATEV", description: "DATEV EXTF", file_extension: "csv", file_prefix: "EXTF", content_type: "text/csv", options: [{ key: "consultant_number", type: "integer", default: null, description: "DATEV consultant number" }] },
      ],
      settings: [],
    });
    api.saveExportSettings.mockResolvedValue({ setting: { format: "datev", name: "DATEV", options: { consultant_number: 1001 }, saved: true, updated_at: null } });
    api.fetchAccountingExport.mockResolvedValue(new Blob(["x"]));
    wrap();

    fireEvent.click(await screen.findByTestId("fiscal-export-open"));
    fireEvent.click(await screen.findByTestId("fiscal-export-format-datev"));
    const dialog = screen.getByTestId("fiscal-export-dialog");
    fireEvent.click(within(dialog).getByText("Export settings · DATEV"));
    fireEvent.change(within(dialog).getByTestId("fiscal-export-option-consultant_number"), { target: { value: "1001" } });
    fireEvent.click(within(dialog).getByTestId("fiscal-export-save-settings"));
    await waitFor(() => expect(api.saveExportSettings).toHaveBeenCalledWith("token", "datev", { consultant_number: 1001 }));

    fireEvent.click(within(dialog).getByTestId("fiscal-export-download"));
    await waitFor(() => expect(api.fetchAccountingExport).toHaveBeenCalledWith("token", "datev", expect.stringMatching(/^\d{4}-\d{2}-01$/), expect.any(String)));
    await waitFor(() => expect(api.saveBlob).toHaveBeenCalledWith(expect.any(Blob), expect.stringMatching(/^EXTF-.*\.csv$/)));
  });
});
