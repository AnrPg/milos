"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";

import type { OrganizationBranding, OrganizationLogoApi } from "@/api/organization-branding";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import {
  TENANT_LOGO_ACCEPT,
  TenantLogoUploadError,
  uploadTenantLogo,
  validateTenantLogoFile,
  type TenantLogoFileProblem,
} from "@/lib/tenant-logo-upload";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type TenantLogoUploaderProps = {
  /** Current logo URL (uploaded or legacy external), or null. */
  currentUrl: string | null;
  /** True when currentUrl comes from an uploaded object (ADR-121). */
  uploaded: boolean;
  api: OrganizationLogoApi;
  onChange: (branding: OrganizationBranding) => void;
};

const PROBLEM_KEYS: Record<TenantLogoFileProblem | "storageRejected", string> = {
  empty: "brandLogoEmpty",
  unsupportedType: "brandLogoUnsupportedType",
  tooLarge: "brandLogoTooLarge",
  storageRejected: "brandLogoStorageRejected",
};

export function TenantLogoUploader({ currentUrl, uploaded, api, onChange }: TenantLogoUploaderProps) {
  const i18n = useUiTranslations();
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [pending, setPending] = useState<"upload" | "remove" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<"saved" | "removed" | null>(null);

  useEffect(() => {
    if (!file) return;
    const url = URL.createObjectURL(file);
    queueMicrotask(() => setPreviewUrl(url));
    return () => URL.revokeObjectURL(url);
  }, [file]);

  function describe(err: unknown) {
    if (err instanceof TenantLogoUploadError) return i18n(PROBLEM_KEYS[err.reason]);
    return localizeError(err, i18n);
  }

  function clearSelection() {
    setFile(null);
    setPreviewUrl(null);
    if (inputRef.current) inputRef.current.value = "";
  }

  function select(next: File | undefined) {
    setError(null);
    setStatus(null);
    if (!next) return;
    const problem = validateTenantLogoFile(next);
    if (problem) {
      clearSelection();
      setError(i18n(PROBLEM_KEYS[problem]));
      return;
    }
    setFile(next);
  }

  async function upload() {
    if (!file) return;
    setPending("upload");
    setError(null);
    try {
      const branding = await uploadTenantLogo(file, api);
      clearSelection();
      setStatus("saved");
      onChange(branding);
    } catch (err) {
      setError(describe(err));
    } finally {
      setPending(null);
    }
  }

  async function remove() {
    setPending("remove");
    setError(null);
    try {
      const branding = await api.remove();
      setStatus("removed");
      onChange(branding);
    } catch (err) {
      setError(describe(err));
    } finally {
      setPending(null);
    }
  }

  const shownUrl = previewUrl ?? currentUrl;
  const busy = pending !== null;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-4">
        <div
          className="flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-xl"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        >
          {shownUrl ? (
            <Image
              alt={previewUrl ? i18n("brandLogoPreviewAlt") : i18n("brandLogoCurrentAlt")}
              className="h-full w-full object-contain"
              height={80}
              src={shownUrl}
              unoptimized
              width={80}
            />
          ) : (
            <span className="px-2 text-center text-xs" style={{ color: "var(--dim)" }}>
              {i18n("brandLogoNone")}
            </span>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <input
            ref={inputRef}
            accept={TENANT_LOGO_ACCEPT}
            aria-label={i18n("brandLogoChoose")}
            className="hidden"
            type="file"
            onChange={(event) => select(event.target.files?.[0])}
          />
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
            disabled={busy}
            style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}
            type="button"
            onClick={() => inputRef.current?.click()}
          >
            {currentUrl ? i18n("brandLogoReplace") : i18n("brandLogoChoose")}
          </button>
          {file ? (
            <>
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
                disabled={busy}
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                type="button"
                onClick={() => void upload()}
              >
                {pending === "upload" ? i18n("brandLogoUploading") : i18n("brandLogoUpload")}
              </button>
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
                disabled={busy}
                style={{ color: "var(--muted)" }}
                type="button"
                onClick={clearSelection}
              >
                {i18n("brandLogoCancel")}
              </button>
            </>
          ) : currentUrl ? (
            <button
              className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
              disabled={busy}
              style={{ color: "var(--danger)" }}
              type="button"
              onClick={() => void remove()}
            >
              {pending === "remove" ? i18n("brandLogoRemoving") : i18n("brandLogoRemove")}
            </button>
          ) : null}
        </div>
      </div>
      <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("brandLogoRequirements")}</p>
      {currentUrl && !uploaded && !file ? (
        <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("brandLogoExternalUrl")}</p>
      ) : null}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      {status && !error ? (
        <p className="text-sm" style={{ color: "var(--success)" }}>
          {status === "saved" ? i18n("brandLogoSaved") : i18n("brandLogoRemoved")}
        </p>
      ) : null}
    </div>
  );
}
