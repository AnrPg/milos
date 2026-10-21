"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { ApiError } from "@/api/client";
import {
  approveOrganizationPurge,
  cancelOrganizationPurge,
  fetchOrganizationPurge,
  requestOrganizationPurge,
  resumeOrganizationPurge,
  type OrganizationPurge,
  type PlatformOrganization,
} from "@/api/platform-organizations";
import { formatPurgeCopy, platformOrganizationPurgeCopy } from "@/i18n/platform-organization-purge";

const cancellableStatuses = new Set<OrganizationPurge["status"]>(["requested", "exported"]);
const workingStatuses = new Set<OrganizationPurge["status"]>(["requested", "exporting", "approved", "purging"]);

export function OrganizationPurgeDialog({
  accessToken,
  locale,
  organization,
  onClose,
  onChanged,
}: {
  accessToken: string | undefined;
  locale: string;
  organization: PlatformOrganization;
  onClose: () => void;
  onChanged: () => void;
}) {
  const copy = platformOrganizationPurgeCopy(locale);
  const organizationId = organization.organization.id;
  const [confirmation, setConfirmation] = useState("");
  const [pending, setPending] = useState<"request" | "approve" | "cancel" | "resume" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  // Status is refreshed on demand (and after every action) rather than polled.
  const purgeQuery = useQuery({
    queryKey: ["platform-organization-purge", accessToken, organizationId],
    enabled: Boolean(accessToken),
    retry: false,
    queryFn: async () => {
      try {
        return await fetchOrganizationPurge(accessToken!, organizationId);
      } catch (error) {
        if (error instanceof ApiError && error.status === 404) return null;
        throw error;
      }
    },
  });

  const status = purgeQuery.data ?? null;
  const purge = status?.purge ?? null;

  async function run(kind: NonNullable<typeof pending>, action: () => Promise<unknown>) {
    if (!accessToken) return;
    setPending(kind);
    setActionError(null);

    try {
      await action();
      setConfirmation("");
      await purgeQuery.refetch();
      onChanged();
    } catch (error) {
      setActionError(error instanceof ApiError && error.payload.error ? error.payload.error : copy.actionError);
    } finally {
      setPending(null);
    }
  }

  const slug = purge?.organization_slug ?? organization.organization.slug;
  const canApprove = purge?.status === "exported" && confirmation.trim() === slug;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[var(--scrim)] p-4" role="dialog" aria-modal="true" aria-label={copy.title}>
      <div className="max-h-[90vh] w-full max-w-3xl overflow-y-auto bg-[var(--surface)] p-6 shadow-xl">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-xl font-semibold text-[var(--text)]">{copy.title}</h2>
            <p className="mt-1 text-sm text-[var(--text-soft)]">{organization.organization.name}</p>
          </div>
          <div className="flex shrink-0 gap-2">
            <button type="button" onClick={() => void purgeQuery.refetch()} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
              {copy.refresh}
            </button>
            <button type="button" onClick={onClose} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
              {copy.close}
            </button>
          </div>
        </div>

        <p className="mt-4 text-sm leading-6 text-[var(--text-soft)]">{copy.intro}</p>

        {actionError ? <p className="mt-4 border-l-4 border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] px-4 py-3 text-sm font-semibold text-[var(--danger)]">{actionError}</p> : null}
        {purgeQuery.isError ? <p className="mt-4 border-l-4 border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] px-4 py-3 text-sm font-semibold text-[var(--danger)]">{copy.loadError}</p> : null}

        {purgeQuery.isSuccess && !purge ? (
          <div className="mt-5 border-y border-[var(--border)] py-5">
            <p className="text-sm text-[var(--text)]">{copy.noPurge}</p>
            <button
              type="button"
              disabled={pending !== null}
              onClick={() => void run("request", () => requestOrganizationPurge(accessToken!, organizationId))}
              className="mt-4 bg-[var(--danger)] px-4 py-2 text-sm font-semibold text-[var(--danger-contrast)] disabled:opacity-50"
            >
              {pending === "request" ? copy.requesting : copy.request}
            </button>
          </div>
        ) : null}

        {purge ? (
          <div className="mt-5 space-y-5">
            <dl className="grid gap-3 border-y border-[var(--border)] py-4 text-sm sm:grid-cols-3">
              <div>
                <dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.status}</dt>
                <dd className="mt-1 font-semibold text-[var(--text)]" data-testid="purge-status">{copy.statuses[purge.status]}</dd>
              </div>
              <div>
                <dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.requestedAt}</dt>
                <dd className="mt-1 text-[var(--text)]">{new Date(purge.requested_at).toLocaleString(locale)}</dd>
              </div>
              {purge.approval_mode ? (
                <div>
                  <dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.approvedBy}</dt>
                  <dd className="mt-1 text-[var(--text)]">
                    {purge.approval_mode === "second_vendor" ? copy.approvalSecondVendor : copy.approvalTyped}
                  </dd>
                </div>
              ) : null}
            </dl>

            {workingStatuses.has(purge.status) ? <p className="text-sm text-[var(--text-soft)]">{copy.workingBody}</p> : null}
            {purge.status === "completed" ? <p className="text-sm font-semibold text-[var(--text)]">{copy.completedBody}</p> : null}
            {purge.status === "cancelled" ? <p className="text-sm text-[var(--text)]">{copy.cancelledBody}</p> : null}
            {purge.status === "failed" ? (
              <div className="border-l-4 border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] px-4 py-3 text-sm text-[var(--danger)]">
                <p>
                  {formatPurgeCopy(copy.failedBody, {
                    stage: purge.failed_stage === "export" ? copy.stageExport : copy.stagePurge,
                    reason: purge.failure_reason ?? "-",
                  })}
                </p>
                <button
                  type="button"
                  disabled={pending !== null}
                  onClick={() => void run("resume", () => resumeOrganizationPurge(accessToken!, organizationId))}
                  className="mt-3 border border-[var(--danger)] px-3 py-2 text-sm font-semibold disabled:opacity-50"
                >
                  {pending === "resume" ? copy.resuming : copy.resume}
                </button>
              </div>
            ) : null}

            {status?.export_download_url ? (
              <section>
                <h3 className="text-sm font-semibold uppercase text-[var(--text-soft)]">{copy.exportReady}</h3>
                <a href={status.export_download_url} className="mt-2 inline-flex border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold" rel="noreferrer">
                  {copy.download}
                </a>
                <p className="mt-2 text-xs text-[var(--text-soft)]">{copy.downloadExpires}</p>
                <p className="mt-1 break-all text-xs text-[var(--text-soft)]">
                  {copy.exportSize}: {formatPurgeCopy(copy.bytes, { size: String(purge.export_byte_size ?? 0) })} · {copy.exportChecksum}: {purge.export_sha256}
                </p>
              </section>
            ) : null}

            {purge.retention_review.length > 0 ? (
              <section>
                <h3 className="text-sm font-semibold uppercase text-[var(--text-soft)]">{copy.retentionTitle}</h3>
                <table className="mt-2 w-full text-left text-sm">
                  <thead>
                    <tr className="border-b border-[var(--border)] text-xs uppercase text-[var(--text-soft)]">
                      <th className="py-2 pr-3">{copy.retentionContext}</th>
                      <th className="py-2 pr-3">{copy.retentionPolicy}</th>
                      <th className="py-2 pr-3">{copy.retentionRecords}</th>
                      <th className="py-2">{copy.retentionUntil}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {purge.retention_review.map((entry) => (
                      <tr key={entry.context} className="border-b border-[var(--border)] align-top" title={entry.basis}>
                        <td className="py-2 pr-3 font-semibold text-[var(--text)]">{entry.context}</td>
                        <td className="py-2 pr-3 text-[var(--text)]">{copy.dispositions[entry.disposition]}</td>
                        <td className="py-2 pr-3 text-[var(--text)]">{entry.record_count}</td>
                        <td className="py-2 text-[var(--text)]">{entry.retained_until ?? "-"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>
            ) : null}

            {purge.status === "exported" ? (
              <section className="border border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] p-4 text-[var(--text)]">
                <h3 className="text-base font-semibold">{copy.approveTitle}</h3>
                <p className="mt-2 text-sm leading-6">{copy.approveBody}</p>
                <label className="mt-3 block text-sm font-medium">
                  <span className="mb-1.5 block">{formatPurgeCopy(copy.confirmationLabel, { slug })}</span>
                  <input
                    value={confirmation}
                    onChange={(event) => setConfirmation(event.target.value)}
                    className="w-full border border-[var(--danger)] bg-[var(--panel)] px-3 py-2.5 text-[var(--text)] outline-none focus:border-[var(--danger)]"
                    autoComplete="off"
                  />
                </label>
                <button
                  type="button"
                  disabled={!canApprove || pending !== null}
                  onClick={() => void run("approve", () => approveOrganizationPurge(accessToken!, organizationId, confirmation))}
                  className="mt-3 bg-[var(--danger)] px-4 py-2 text-sm font-semibold text-[var(--danger-contrast)] disabled:opacity-50"
                >
                  {pending === "approve" ? copy.approving : copy.approve}
                </button>
              </section>
            ) : null}

            {cancellableStatuses.has(purge.status) || (purge.status === "failed" && purge.failed_stage === "export") ? (
              <button
                type="button"
                disabled={pending !== null}
                onClick={() => void run("cancel", () => cancelOrganizationPurge(accessToken!, organizationId))}
                className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold disabled:opacity-50"
              >
                {pending === "cancel" ? copy.cancelling : copy.cancelPurge}
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
    </div>
  );
}
