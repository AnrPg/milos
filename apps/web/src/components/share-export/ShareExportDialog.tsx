"use client";

import { useId, useState, type ReactNode } from "react";

import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import {
  generateExportFile,
  type ExportDocument,
  type ExportFormat,
} from "@/lib/document-export";
import { openEmailAttachmentFallback } from "@/lib/share-export-delivery";

export type ShareExportCopy = {
  title: string;
  chooseFormat: string;
  formatHelp: string;
  download: string;
  share: string;
  email: string;
  googleDrive: string;
  oneDrive: string;
  iCloudDrive: string;
  social: string;
  close: string;
  working: string;
  ready: string;
  downloadedFallback: string;
  shareUnavailable: string;
  failed: string;
  formatPdf: string;
  formatMarkdown: string;
  formatText: string;
  formatOdt: string;
  formatCsv: string;
};

type Destination = "system" | "email" | "google" | "microsoft" | "apple" | "social";

type ShareExportDialogProps = {
  copy: ShareExportCopy;
  document: ExportDocument;
  onClose: () => void;
  secondaryContent?: ReactNode;
  generateFile?: (document: ExportDocument, format: ExportFormat) => Promise<File>;
};

const FORMATS: Array<{ value: ExportFormat; key: "formatPdf" | "formatMarkdown" | "formatText" | "formatOdt" | "formatCsv"; icon: string; color: string }> = [
  { value: "pdf", key: "formatPdf", icon: "📕", color: "#E11D48" },
  { value: "md", key: "formatMarkdown", icon: "✨", color: "#7C3AED" },
  { value: "txt", key: "formatText", icon: "📝", color: "#0F766E" },
  { value: "odt", key: "formatOdt", icon: "📘", color: "#2563EB" },
  { value: "csv", key: "formatCsv", icon: "📊", color: "#15803D" },
];

const DESTINATIONS: Array<{
  value: Exclude<Destination, "system">;
  key: "email" | "googleDrive" | "oneDrive" | "iCloudDrive" | "social";
  icon: string;
}> = [
  { value: "email", key: "email", icon: "✉️" },
  { value: "google", key: "googleDrive", icon: "🔺" },
  { value: "microsoft", key: "oneDrive", icon: "☁️" },
  { value: "apple", key: "iCloudDrive", icon: "🍎" },
  { value: "social", key: "social", icon: "💬" },
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

export function ShareExportDialog({
  copy,
  document,
  onClose,
  secondaryContent,
  generateFile = generateExportFile,
}: ShareExportDialogProps) {
  const [format, setFormat] = useState<ExportFormat>("pdf");
  const [busy, setBusy] = useState<"download" | Destination | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const titleId = useId();
  const formatHelpId = useId();
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);

  async function prepareFile() {
    setStatus(copy.working);
    return generateFile(document, format);
  }

  async function handleDownload() {
    setBusy("download");
    try {
      const file = await prepareFile();
      downloadFile(file);
      setStatus(copy.ready);
    } catch {
      setStatus(copy.failed);
    } finally {
      setBusy(null);
    }
  }

  async function handleShare(destination: Destination) {
    setBusy(destination);
    try {
      const file = await prepareFile();
      if (canShareFile(file)) {
        await navigator.share({
          title: document.title,
          text: document.category,
          files: [file],
        });
        setStatus(copy.ready);
        return;
      }

      downloadFile(file);
      setStatus(`${copy.shareUnavailable} ${copy.downloadedFallback}`);

      if (destination === "email") {
        openEmailAttachmentFallback(document.title, copy.downloadedFallback);
      } else {
        const providerUrl = PROVIDER_URLS[destination];
        if (providerUrl) window.open(providerUrl, "_blank", "noopener,noreferrer");
      }
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        setStatus(null);
      } else {
        setStatus(copy.failed);
      }
    } finally {
      setBusy(null);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[80] flex items-end justify-center p-3 sm:items-center sm:p-6"
      style={{ background: "rgba(8, 12, 24, 0.72)", backdropFilter: "blur(8px)" }}
      onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}
      role="presentation"
    >
      <div
        ref={dialogRef}
        aria-labelledby={titleId}
        aria-modal="true"
        className="max-h-[92vh] w-full max-w-2xl overflow-y-auto rounded-[2rem] p-5 outline-none sm:p-7"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", boxShadow: "0 30px 90px rgba(0,0,0,0.35)" }}
        role="dialog"
        tabIndex={-1}
      >
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
              {document.icon} {document.category}
            </p>
            <h2 id={titleId} className="mt-1 truncate text-2xl font-bold" style={{ color: "var(--text)" }}>
              {copy.title}
            </h2>
            <p className="mt-1 truncate text-sm" style={{ color: "var(--muted)" }}>{document.title}</p>
          </div>
          <button
            aria-label={copy.close}
            className="shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold"
            style={{ background: "var(--border)", color: "var(--muted)" }}
            onClick={onClose}
            type="button"
          >
            {copy.close}
          </button>
        </div>

        <fieldset aria-describedby={formatHelpId} className="mt-6">
          <legend className="text-sm font-bold" style={{ color: "var(--text)" }}>{copy.chooseFormat}</legend>
          <p id={formatHelpId} className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{copy.formatHelp}</p>
          <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
            {FORMATS.map((option) => {
              const active = format === option.value;
              return (
                <label
                  key={option.value}
                  className="relative flex cursor-pointer items-center gap-2 rounded-2xl px-3 py-3 text-sm font-semibold transition-transform hover:-translate-y-0.5 sm:flex-col sm:justify-center"
                  style={{
                    background: active ? `color-mix(in srgb, ${option.color} 16%, var(--panel))` : "var(--panel-muted)",
                    border: active ? `2px solid ${option.color}` : "1px solid var(--border)",
                    color: active ? option.color : "var(--muted)",
                  }}
                >
                  <input
                    checked={active}
                    className="sr-only"
                    name="export-format"
                    onChange={() => setFormat(option.value)}
                    type="radio"
                    value={option.value}
                  />
                  <span aria-hidden="true" className="text-xl">{option.icon}</span>
                  <span>{copy[option.key]}</span>
                </label>
              );
            })}
          </div>
        </fieldset>

        <div className="mt-5 grid gap-3 sm:grid-cols-2">
          <button
            aria-label={copy.download}
            className="rounded-2xl px-4 py-3.5 text-sm font-bold disabled:opacity-50"
            disabled={busy !== null}
            onClick={() => void handleDownload()}
            style={{ background: "var(--text)", color: "var(--bg)" }}
            type="button"
          >
            ⬇️ {busy === "download" ? copy.working : copy.download}
          </button>
          <button
            aria-label={copy.share}
            className="rounded-2xl px-4 py-3.5 text-sm font-bold disabled:opacity-50"
            disabled={busy !== null}
            onClick={() => void handleShare("system")}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="button"
          >
            📤 {busy === "system" ? copy.working : copy.share}
          </button>
        </div>

        <div className="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-5">
          {DESTINATIONS.map((destination) => (
            <button
              key={destination.value}
              className="flex min-h-20 flex-col items-center justify-center gap-1 rounded-2xl px-2 py-3 text-center text-xs font-semibold disabled:opacity-50"
              disabled={busy !== null}
              onClick={() => void handleShare(destination.value)}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              type="button"
            >
              <span aria-hidden="true" className="text-xl">{destination.icon}</span>
              <span>{copy[destination.key]}</span>
            </button>
          ))}
        </div>

        {secondaryContent ? (
          <div className="mt-5 border-t pt-5" style={{ borderColor: "var(--border)" }}>
            {secondaryContent}
          </div>
        ) : null}

        <p aria-live="polite" className="mt-4 min-h-5 text-center text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {status}
        </p>
      </div>
    </div>
  );
}
