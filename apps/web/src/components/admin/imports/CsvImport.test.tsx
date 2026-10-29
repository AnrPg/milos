import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import type { ImportRow, PeopleImport } from "@/api/imports";

import { CsvImport } from "./CsvImport";

const api = vi.hoisted(() => ({
  listImports: vi.fn(),
  uploadImport: vi.fn(),
  previewImport: vi.fn(),
  fetchImport: vi.fn(),
  fetchImportRows: vi.fn(),
  fetchImportCatalog: vi.fn(),
  applyImport: vi.fn(),
  sendImportInvitations: vi.fn(),
  undoImport: vi.fn(),
  deleteImport: vi.fn(),
}));
const nav = vi.hoisted(() => ({ replace: vi.fn(), params: new URLSearchParams() }));

vi.mock("@/api/imports", () => api);
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "kypseli", adminHref: (href: string) => href }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: nav.replace }),
  usePathname: () => "/admin/users/import",
  useSearchParams: () => nav.params,
}));

const draft: PeopleImport = {
  id: "imp-1",
  status: "draft",
  source: "wodify",
  filename: "wodify-members.csv",
  byte_size: 2048,
  encoding: "utf-8",
  delimiter: ",",
  header: ["First Name", "Email", "Membership", "Coach Notes"],
  row_count: 3,
  mapping: [
    { column: 0, field: "first_name" },
    { column: 1, field: "email" },
    { column: 2, field: "package_name" },
  ],
  date_order: "mdy",
  default_role: "member",
  file_warnings: [],
  preview: {
    rows: 3,
    outcomes: { create_person: 2, invalid: 1 },
    actions: { create_person: 2, assign_package: 2, create_package: 1 },
    warnings: { package_created: 1, invalid_email: 1 },
  },
  previewed_at: "2026-10-29T10:00:00Z",
  counts: { statuses: { pending: 3 }, outcomes: { create_person: 2, invalid: 1 } },
  inserted_at: "2026-10-29T10:00:00Z",
} as PeopleImport;

const row = (row_number: number, cells: string[], patch: Partial<ImportRow> = {}) =>
  ({ id: `r${row_number}`, row_number, cells, status: "pending", outcome: "create_person", warnings: [], errors: [], result: {}, ...patch }) as ImportRow;

const sample = [
  row(2, ["Maria", "maria@example.com", "Gold 2024", "Shoulder"], { warnings: [{ code: "package_created", field: "package_name" }] }),
  row(3, ["Nikos", "nikos@", "Gold 2024", ""], { warnings: [{ code: "invalid_email", field: "email" }] }),
  row(4, ["", "", "", ""], { outcome: "invalid", errors: [{ code: "missing_person", field: null }] }),
];

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      <QueryClientProvider client={client}>
        <CsvImport />
      </QueryClientProvider>
    </NextIntlClientProvider>,
  );
}

beforeEach(() => {
  Object.values(api).forEach((fn) => fn.mockReset());
  nav.replace.mockReset();
  nav.params = new URLSearchParams();
  api.listImports.mockResolvedValue([]);
  api.fetchImportCatalog.mockResolvedValue({ presets: [{ key: "wodify", name: "Wodify", date_order: "mdy" }] });
  api.fetchImportRows.mockResolvedValue({ rows: sample, next_after_row: null });
});

describe("CsvImport", () => {
  it("uploads the dropped file, runs the dry run and opens it", async () => {
    api.uploadImport.mockResolvedValue({ ...draft, preview: null });
    api.previewImport.mockResolvedValue(draft);
    renderPage();

    expect(screen.getByText(en.CsvImport.dropTitle)).toBeInTheDocument();
    expect(screen.getByText(en.CsvImport.nothingChanges)).toBeInTheDocument();
    const file = new File(["First Name,Email\nMaria,maria@example.com\n"], "people.csv", { type: "text/csv" });
    fireEvent.change(screen.getByLabelText(en.CsvImport.dropChoose), { target: { files: [file] } });

    await waitFor(() => expect(nav.replace).toHaveBeenCalledWith("/admin/users/import?import=imp-1"));
    expect(api.uploadImport).toHaveBeenCalledWith("token", file, null);
    expect(api.previewImport).toHaveBeenCalledWith("token", "imp-1");
  });

  it("shows the upload error inside the drop card", async () => {
    const { ApiError } = await import("@/api/client");
    api.uploadImport.mockRejectedValue(new ApiError(413, "too large", { code: "file_too_large" }));
    renderPage();
    fireEvent.change(screen.getByLabelText(en.CsvImport.dropChoose), { target: { files: [new File(["x"], "big.csv")] } });
    expect(await screen.findByText(en.CsvImport.errors.file_too_large)).toBeInTheDocument();
  });

  it("asks only the decisions, re-runs the dry run on an answer and imports when all are answered", async () => {
    nav.params = new URLSearchParams("import=imp-1");
    api.fetchImport.mockResolvedValue(draft);
    api.previewImport.mockImplementation(async (_token: string, _id: string, body: { mapping: unknown }) => ({ ...draft, mapping: body.mapping, previewed_at: "2026-10-29T10:01:00Z" }));
    api.applyImport.mockResolvedValue({ ...draft, status: "queued" });
    renderPage();

    expect(await screen.findByTestId("import-recognized")).toHaveTextContent("Recognised: an export from Wodify · 3 rows");
    expect(screen.getByTestId("import-kpis")).toHaveTextContent("2new box members");
    expect(screen.getByTestId("import-decisions-title")).toHaveTextContent("Need your decision · 3");
    expect(screen.getByText("The package «Gold 2024» does not exist here (2 box members)")).toBeInTheDocument();
    expect(screen.getByText("2 rows with a wrong value or no name")).toBeInTheDocument();
    expect(screen.getByText("The column «Coach Notes» has no place")).toBeInTheDocument();

    const apply = screen.getByTestId("import-apply");
    expect(apply).toHaveTextContent("Import 2 box members");
    expect(apply).toBeDisabled();

    fireEvent.click(within(screen.getByTestId("import-decision-packages")).getByRole("button", { name: "Leave packages out" }));
    await waitFor(() =>
      expect(api.previewImport).toHaveBeenCalledWith("token", "imp-1", {
        mapping: [
          { column: 0, field: "first_name" },
          { column: 1, field: "email" },
        ],
        date_order: "mdy",
      }),
    );
    fireEvent.click(screen.getByRole("button", { name: en.CsvImport.rowsOk }));
    fireEvent.click(within(screen.getByTestId("import-decision-column")).getByRole("button", { name: en.CsvImport.columnNotes }));
    await waitFor(() => expect(screen.getByTestId("import-decisions-title")).toHaveTextContent(en.CsvImport.allReady));
    await waitFor(() => expect(apply).toBeEnabled());
    expect(api.previewImport).toHaveBeenLastCalledWith("token", "imp-1", {
      mapping: [
        { column: 0, field: "first_name" },
        { column: 1, field: "email" },
        { column: 3, field: "notes" },
      ],
      date_order: "mdy",
    });

    fireEvent.click(apply);
    await waitFor(() => expect(api.applyImport).toHaveBeenCalledWith("token", "imp-1"));
    expect(await screen.findByTestId("import-applying")).toBeInTheDocument();
  });

  it("opens the full column mapping with a sample per column", async () => {
    nav.params = new URLSearchParams("import=imp-1");
    api.fetchImport.mockResolvedValue(draft);
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "All column mappings (4)" }));
    const mapping = screen.getByTestId("import-mapping");
    expect(within(mapping).getByText("First Name")).toBeInTheDocument();
    expect(within(mapping).getByText("e.g. maria@example.com")).toBeInTheDocument();
    // No date column is mapped, so the date order is not asked.
    expect(within(mapping).queryByText(en.CsvImport.dateOrder)).toBeNull();
  });

  it("shows progress while the import runs in the background", async () => {
    nav.params = new URLSearchParams("import=imp-1");
    api.fetchImport.mockResolvedValue({ ...draft, status: "applying", row_count: 200, counts: { statuses: { applied: 50, pending: 150 }, outcomes: {} } });
    renderPage();

    expect(await screen.findByRole("progressbar")).toHaveAttribute("aria-valuenow", "25");
    expect(screen.getByText("50 of 200 rows")).toBeInTheDocument();
  });

  it("reports the result, sends invitations on request and undoes within the window", async () => {
    nav.params = new URLSearchParams("import=imp-1");
    const applied = {
      ...draft,
      status: "applied",
      finished_at: "2026-10-29T10:05:00Z",
      undo_until: "2999-11-05T10:05:00Z",
      summary: { people_created: 206, people_matched: 5, subscriptions: 180 },
      counts: { statuses: { applied: 211, skipped: 3 }, outcomes: {} },
    } as PeopleImport;
    api.fetchImport.mockResolvedValue(applied);
    api.sendImportInvitations.mockResolvedValue({ sent: 200, failed: 0, remaining: 11, results: [] });
    api.undoImport.mockResolvedValue({ ...applied, status: "undone" });
    renderPage();

    expect(await screen.findByText("211 box members and 180 subscription packages imported")).toBeInTheDocument();
    expect(screen.getByText(/3 rows were skipped/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: en.CsvImport.inviteNow }));
    expect(await screen.findByText("200 invitations sent · 11 left, press again")).toBeInTheDocument();
    expect(api.sendImportInvitations).toHaveBeenCalledWith("token", "imp-1");

    fireEvent.click(screen.getByRole("button", { name: en.CsvImport.undoLink }));
    fireEvent.click(await screen.findByTestId("import-undo-confirm"));
    expect(await screen.findByTestId("import-undone")).toBeInTheDocument();
  });

  it("lists the rows with filters", async () => {
    nav.params = new URLSearchParams("import=imp-1");
    api.fetchImport.mockResolvedValue(draft);
    renderPage();

    fireEvent.click((await screen.findAllByRole("button", { name: en.CsvImport.seeRows }))[0]!);
    const dialog = await screen.findByTestId("import-rows");
    expect(await within(dialog).findByText("Maria · maria@example.com")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Skipped · 1" }));
    await waitFor(() =>
      expect(api.fetchImportRows).toHaveBeenLastCalledWith("token", "imp-1", { outcome: "invalid", limit: 100, after_row: undefined }),
    );
  });
});
