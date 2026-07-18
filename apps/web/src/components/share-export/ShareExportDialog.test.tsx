import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { ShareExportDialog, type ShareExportCopy } from "@/components/share-export/ShareExportDialog";
import type { ExportDocument, ExportFormat } from "@/lib/document-export";

const copy: ShareExportCopy = {
  title: "Share or export",
  chooseFormat: "Choose a file format",
  formatHelp: "The selected format is used for every action.",
  download: "Download file",
  share: "Share file",
  email: "Email",
  googleDrive: "Google Drive",
  oneDrive: "OneDrive",
  iCloudDrive: "iCloud Drive",
  social: "Social apps",
  close: "Close",
  working: "Preparing file…",
  ready: "Your file is ready.",
  downloadedFallback: "The file was downloaded for manual attachment or upload.",
  shareUnavailable: "File sharing is unavailable in this browser.",
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

    fireEvent.click(screen.getByRole("radio", { name: "ODT" }));
    fireEvent.click(screen.getByRole("button", { name: "Share file" }));

    await waitFor(() => expect(share).toHaveBeenCalledOnce());
    expect(generateFile).toHaveBeenCalledWith(document, "odt");
    expect(share.mock.calls[0][0].files[0]).toBeInstanceOf(File);
    expect(share.mock.calls[0][0].files[0].name).toBe("deadlift.odt");
  });

  it("keeps every destination inside one accessible dialog", () => {
    render(<ShareExportDialog copy={copy} document={document} onClose={() => undefined} />);

    expect(screen.getByRole("dialog", { name: "Share or export" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Email" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Google Drive" })).toBeVisible();
    expect(screen.getByRole("button", { name: "OneDrive" })).toBeVisible();
    expect(screen.getByRole("button", { name: "iCloud Drive" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Social apps" })).toBeVisible();
  });
});
