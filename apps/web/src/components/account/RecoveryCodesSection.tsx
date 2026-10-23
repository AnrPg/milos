"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { fetchRecoveryCodesStatus, generateRecoveryCodes } from "@/api/account-profiles";
import {
  describeAccountError,
  downloadTextFile,
  recoveryCodesFileName,
  recoveryCodesFileText,
} from "@/components/account/account-model";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const RECOVERY_CODES_QUERY_KEY = ["account", "recovery-codes"] as const;

/**
 * Ρυθμίσεις › Recovery codes (ADR-187): ten one-time codes that reset the
 * password without anyone's help. Optional but recommended; generating new
 * ones needs the current password and voids the old ones. Reachable as
 * /me/settings#recovery-codes.
 */
export function RecoveryCodesSection() {
  const t = useTranslations("accountProfiles");
  const { tokens, currentUser } = useSession();
  const [dialogOpen, setDialogOpen] = useState(false);
  const statusQuery = useQuery({
    queryKey: [...RECOVERY_CODES_QUERY_KEY, currentUser?.id ?? null],
    queryFn: () => fetchRecoveryCodesStatus(tokens!.access_token),
    enabled: Boolean(tokens?.access_token),
  });
  const status = statusQuery.data;
  const isSetUp = Boolean(status && status.total > 0);

  return (
    <CollapsibleSection id="recovery-codes" title={t("codesTitle")} description={t("codesDescription")}>
      <div className="space-y-4">
        {status ? (
          <p
            className="text-sm font-semibold"
            style={{ color: isSetUp && status.unused > 0 ? "var(--text)" : "var(--warning)" }}
          >
            {isSetUp ? t("codesUnused", { unused: status.unused, total: status.total }) : t("codesNotSetUp")}
          </p>
        ) : statusQuery.isError ? (
          <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("codesLoadError")}</p>
        ) : null}
        <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>{t("codesExplainer")}</p>
        <button
          type="button"
          onClick={() => setDialogOpen(true)}
          className="rounded-xl px-5 py-2.5 text-sm font-semibold"
          style={
            isSetUp
              ? { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }
              : { background: "var(--primary)", color: "var(--primary-contrast)" }
          }
        >
          {isSetUp ? t("codesRegenerate") : t("codesGenerate")}
        </button>
      </div>
      {dialogOpen ? (
        <RecoveryCodesDialog regenerate={isSetUp} onClose={() => setDialogOpen(false)} />
      ) : null}
    </CollapsibleSection>
  );
}

function RecoveryCodesDialog({ regenerate, onClose }: { regenerate: boolean; onClose: () => void }) {
  const t = useTranslations("accountProfiles");
  const i18n = useUiTranslations();
  const format = useFormatter();
  const { tokens, currentUser } = useSession();
  const queryClient = useQueryClient();
  const [password, setPassword] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [codes, setCodes] = useState<string[] | null>(null);
  const [copied, setCopied] = useState(false);
  const [saved, setSaved] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!tokens || pending || codes) return;
    setPending(true);
    setError(null);
    try {
      const result = await generateRecoveryCodes(tokens.access_token, password);
      setCodes(result.codes);
      setPassword("");
      void queryClient.invalidateQueries({ queryKey: RECOVERY_CODES_QUERY_KEY });
    } catch (err) {
      const described = describeAccountError(err);
      setError(described ? t(described.key, described.values) : localizeError(err, i18n));
    } finally {
      setPending(false);
    }
  }

  async function copyAll() {
    if (!codes) return;
    try {
      await navigator.clipboard.writeText(codes.join("\n"));
      setCopied(true);
      setSaved(true);
    } catch {
      setCopied(false);
    }
  }

  function download() {
    if (!codes) return;
    const now = new Date();
    const account = currentUser?.email
      ? `${currentUser.email} · @${currentUser.handle}`
      : `@${currentUser?.handle ?? ""}`;
    downloadTextFile(
      recoveryCodesFileName(currentUser?.handle, now),
      recoveryCodesFileText({
        heading: t("codesFileHeading"),
        account,
        generatedAt: t("codesFileGenerated", { date: format.dateTime(now, { dateStyle: "long", timeStyle: "short" }) }),
        note: t("codesFileNote"),
        codes,
      }),
    );
    setSaved(true);
  }

  if (codes) {
    return (
      <Dialog
        onClose={onClose}
        title={t("codesShownTitle")}
        size="md"
        dismissible={false}
        footer={
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-xl px-5 py-2.5 text-sm font-semibold sm:w-auto"
            style={
              saved
                ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                : { border: "1px solid var(--border)", color: "var(--text-soft)" }
            }
          >
            {t("codesDone")}
          </button>
        }
      >
        <div className="space-y-4">
          <p
            className="rounded-2xl px-4 py-3 text-sm font-semibold leading-6"
            style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", color: "var(--text)" }}
            role="alert"
          >
            {t("codesShownWarning")}
          </p>
          <ol
            className="grid grid-cols-2 gap-x-4 gap-y-2 rounded-2xl px-4 py-3 font-mono text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            dir="ltr"
          >
            {codes.map((code) => (
              <li key={code} className="select-all tracking-wide">{code}</li>
            ))}
          </ol>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => void copyAll()}
              className="min-h-11 flex-1 rounded-xl px-4 text-sm font-semibold"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {copied ? t("codesCopied") : t("codesCopyAll")}
            </button>
            <button
              type="button"
              onClick={download}
              className="min-h-11 flex-1 rounded-xl px-4 text-sm font-semibold"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("codesDownload")}
            </button>
          </div>
          <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("codesUseHint")}</p>
        </div>
      </Dialog>
    );
  }

  return (
    <Dialog
      onClose={onClose}
      title={regenerate ? t("codesRegenerate") : t("codesGenerate")}
      size="md"
      dismissible={!pending}
      onSubmit={(event) => void submit(event)}
      footer={
        <div className="flex w-full gap-3 sm:w-auto">
          <button
            type="button"
            onClick={onClose}
            disabled={pending}
            className="flex-1 rounded-xl px-5 py-2.5 text-sm font-semibold sm:flex-none"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="submit"
            disabled={pending || !password}
            className="flex-1 rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50 sm:flex-none"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {pending ? t("codesGenerating") : t("codesConfirm")}
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        {regenerate ? (
          <p className="text-sm font-semibold leading-6" style={{ color: "var(--warning)" }}>
            {t("codesRegenerateWarning")}
          </p>
        ) : null}
        <div className="space-y-1.5">
          <label
            htmlFor="recovery-codes-password"
            className="block text-xs font-semibold uppercase tracking-[0.18em]"
            style={{ color: "var(--muted)" }}
          >
            {t("currentPasswordLabel")}
          </label>
          <input
            id="recovery-codes-password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="current-password"
            autoFocus
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </div>
        {error ? (
          <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{error}</p>
        ) : null}
      </div>
    </Dialog>
  );
}
