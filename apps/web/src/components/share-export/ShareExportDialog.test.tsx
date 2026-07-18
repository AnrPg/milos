import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { ShareExportDialog, type ShareExportCopy } from "@/components/share-export/ShareExportDialog";
import type { ExportDocument, ExportFormat } from "@/lib/document-export";

const copy: ShareExportCopy = {
  title: "Share or export",
  chooseFormat: "Choose a file format",
  chooseDestination: "Export to",
  formatHelp: "The selected format is used for every action.",
  download: "Download file",
  share: "Share file",
  export: "Export",
  email: "Email",
  googleDrive: "Google Drive",
  oneDrive: "OneDrive",
  iCloudDrive: "iCloud Drive",
  social: "Social apps",
  otherApps: "Other apps",
  close: "Close",
  working: "Preparing file…",
  ready: "Your file is ready.",
  downloadedFallback: "The file was downloaded for manual attachment or upload.",
  shareUnavailable: "File sharing is unavailable in this browser.",
  copiedFallback: "The full content was copied.",
  failed: "The file could not be generated.",
  formatPdf: "PDF",
  formatMarkdown: "Markdown",
  formatText: "Text",
  formatOdt: "ODT",
  formatCsv: "CSV",
};

const document: ExportDocument = {
  icon: "🏆",
  category: "Personal record",
  title: "Deadlift",
  metadata: [],
  sections: [],
  footer: "Milos Training",
};

describe("ShareExportDialog", () => {
  it("passes the generated file in the selected format to the system share sheet", async () => {
    const share = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "canShare", { configurable: true, value: () => true });
    Object.defineProperty(navigator, "share", { configurable: true, value: share });
    const generateFile = vi.fn(async (_document: ExportDocument, format: ExportFormat) =>
      new File(["odt"], `deadlift.${format}`, { type: "application/vnd.oasis.opendocument.text" }));

    render(
      <ShareExportDialog
        copy={copy}
        document={document}
        generateFile={generateFile}
        onClose={() => undefined}
      />,
    );

    fireEvent.change(screen.getByRole("combobox", { name: "Choose a file format" }), { target: { value: "odt" } });
    fireEvent.change(screen.getByRole("combobox", { name: "Export to" }), { target: { value: "system" } });
    fireEvent.click(screen.getByRole("button", { name: "Export" }));

    await waitFor(() => expect(share).toHaveBeenCalledOnce());
    expect(generateFile).toHaveBeenCalledWith(document, "odt");
    expect(share.mock.calls[0][0].files[0]).toBeInstanceOf(File);
    expect(share.mock.calls[0][0].files[0].name).toBe("deadlift.odt");
  });

  it("presents one format selector, one destination selector, and one export action", () => {
    render(<ShareExportDialog copy={copy} document={document} onClose={() => undefined} />);

    expect(screen.getByRole("dialog", { name: "Share or export" })).toBeVisible();
    expect(screen.getAllByRole("combobox")).toHaveLength(2);
    expect(screen.getByRole("option", { name: "Email" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Google Drive" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Social apps" })).toBeInTheDocument();
    expect(screen.getAllByRole("button")).toHaveLength(2);
  });

  it("shares the complete document text without downloading when social apps cannot receive files", async () => {
    const share = vi.fn().mockResolvedValue(undefined);
    const createObjectURL = vi.spyOn(URL, "createObjectURL");
    Object.defineProperty(navigator, "canShare", { configurable: true, value: () => false });
    Object.defineProperty(navigator, "share", { configurable: true, value: share });

    render(<ShareExportDialog copy={copy} document={document} onClose={() => undefined} />);

    fireEvent.change(screen.getByRole("combobox", { name: "Export to" }), { target: { value: "social" } });
    fireEvent.click(screen.getByRole("button", { name: "Export" }));

    await waitFor(() => expect(share).toHaveBeenCalledOnce());
    expect(share.mock.calls[0][0].files).toBeUndefined();
    expect(share.mock.calls[0][0].text).toContain("Deadlift");
    expect(share.mock.calls[0][0].text).toContain("PERSONAL RECORD");
    expect(createObjectURL).not.toHaveBeenCalled();
  });
});
