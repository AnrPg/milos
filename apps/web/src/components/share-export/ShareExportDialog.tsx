"use client";

import { useId, useState } from "react";

import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import {
  generateExportFile,
  renderText,
  type ExportDocument,
  type ExportFormat,
} from "@/lib/document-export";
import { openEmailAttachmentFallback } from "@/lib/share-export-delivery";
import { Dialog } from "@/components/ui/Dialog";

export type ShareExportCopy = {
  title: string;
  chooseFormat: string;
  chooseDestination: string;
  formatHelp: string;
  download: string;
  share: string;
  export: string;
  email: string;
  googleDrive: string;
  oneDrive: string;
  iCloudDrive: string;
  social: string;
  otherApps: string;
  close: string;
  working: string;
  ready: string;
  downloadedFallback: string;
  shareUnavailable: string;
  copiedFallback: string;
  failed: string;
  formatPdf: string;
  formatMarkdown: string;
  formatText: string;
  formatOdt: string;
  formatCsv: string;
};

type Destination = "download" | "system" | "email" | "google" | "microsoft" | "apple" | "social";

type ShareExportDialogProps = {
  copy: ShareExportCopy;
  document: ExportDocument;
  onClose: () => void;
  generateFile?: (document: ExportDocument, format: ExportFormat) => Promise<File>;
};

const FORMATS: Array<{ value: ExportFormat; key: "formatPdf" | "formatMarkdown" | "formatText" | "formatOdt" | "formatCsv" }> = [
  { value: "pdf", key: "formatPdf" },
  { value: "md", key: "formatMarkdown" },
  { value: "txt", key: "formatText" },
  { value: "odt", key: "formatOdt" },
  { value: "csv", key: "formatCsv" },
];

const DESTINATIONS: Array<{
  value: Destination;
  key: "download" | "otherApps" | "email" | "googleDrive" | "oneDrive" | "iCloudDrive" | "social";
}> = [
  { value: "download", key: "download" },
  { value: "system", key: "otherApps" },
  { value: "email", key: "email" },
  { value: "google", key: "googleDrive" },
  { value: "microsoft", key: "oneDrive" },
  { value: "apple", key: "iCloudDrive" },
  { value: "social", key: "social" },
];

const PROVIDER_URLS: Partial<Record<Destination, string>> = {
  google: "https://drive.google.com/drive/my-drive",
  microsoft: "https://onedrive.live.com/",
  apple: "https://www.icloud.com/iclouddrive/",
};

function downloadFile(file: File) {
  const url = URL.createObjectURL(file);
  const anchor = window.document.createElement("a");
  anchor.href = url;
  anchor.download = file.name;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

function canShareFile(file: File): boolean {
  if (typeof navigator.share !== "function") return false;
  if (typeof navigator.canShare !== "function") return true;
  return navigator.canShare({ files: [file] });
}

async function shareText(title: string, content: string): Promise<"shared" | "copied"> {
  if (typeof navigator.share === "function") {
    await navigator.share({ title, text: content });
    return "shared";
  }
  await navigator.clipboard.writeText(content);
  return "copied";
}

export function ShareExportDialog({
  copy,
  document,
  onClose,
  generateFile = generateExportFile,
}: ShareExportDialogProps) {
  const [format, setFormat] = useState<ExportFormat>("pdf");
  const [destination, setDestination] = useState<Destination>("download");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const titleId = useId();
  const formatHelpId = useId();

  async function prepareFile() {
    setStatus(copy.working);
    return generateFile(document, format);
  }

  async function handleExport() {
    setBusy(true);
    try {
      const file = await prepareFile();
      const content = renderText(document);

      if (destination === "download") {
        downloadFile(file);
        setStatus(copy.ready);
        return;
      }

      if (canShareFile(file)) {
        await navigator.share({
          title: document.title,
          text: content,
          files: [file],
        });
        setStatus(copy.ready);
        return;
      }

      if (destination === "email") {
        openEmailAttachmentFallback(document.title, content);
        setStatus(copy.shareUnavailable);
        return;
      }

      const providerUrl = PROVIDER_URLS[destination];
      if (providerUrl) {
        window.open(providerUrl, "_blank", "noopener,noreferrer");
        downloadFile(file);
        setStatus(`${copy.shareUnavailable} ${copy.downloadedFallback}`);
        return;
      }

      const result = await shareText(document.title, content);
      setStatus(result === "copied" ? copy.copiedFallback : copy.ready);
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        setStatus(null);
      } else {
        setStatus(copy.failed);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      eyebrow={<>{document.icon} {document.category}</>}
      title={copy.title}
      titleId={titleId}
      description={<span className="block truncate">{document.title}</span>}
      closeLabel={copy.close}
      size="lg"
    >
        

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="space-y-2 text-sm font-bold" style={{ color: "var(--text)" }}>
            <span>{copy.chooseFormat}</span>
            <select
              aria-describedby={formatHelpId}
              className="w-full rounded-xl px-4 py-3 text-sm font-semibold outline-none"
              onChange={(event) => setFormat(event.target.value as ExportFormat)}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={format}
            >
              {FORMATS.map((option) => <option key={option.value} value={option.value}>{copy[option.key]}</option>)}
            </select>
          </label>
          <label className="space-y-2 text-sm font-bold" style={{ color: "var(--text)" }}>
            <span>{copy.chooseDestination}</span>
            <select
              className="w-full rounded-xl px-4 py-3 text-sm font-semibold outline-none"
              onChange={(event) => setDestination(event.target.value as Destination)}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={destination}
            >
              {DESTINATIONS.map((option) => <option key={option.value} value={option.value}>{copy[option.key]}</option>)}
            </select>
          </label>
        </div>
        <p id={formatHelpId} className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{copy.formatHelp}</p>

        <button
          aria-label={copy.export}
          className="mt-5 w-full rounded-xl px-4 py-3.5 text-sm font-bold disabled:opacity-50"
          disabled={busy}
          onClick={() => void handleExport()}
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          type="button"
        >
          {busy ? copy.working : copy.export}
        </button>

        <p aria-live="polite" className="mt-4 min-h-5 text-center text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {status}
        </p>
    </Dialog>
  );
}
