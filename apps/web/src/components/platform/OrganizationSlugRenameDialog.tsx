"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { ApiError } from "@/api/client";
import {
  fetchOrganizationSlugImpact,
  renamePlatformOrganizationSlug,
  type OrganizationSlugRenameResult,
  type PlatformOrganization,
} from "@/api/platform-organizations";
import { formatSlugCopy, platformOrganizationSlugCopy } from "@/i18n/platform-organization-slug";

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function isValidOrganizationSlug(value: string) {
  return value.length >= 3 && value.length <= 63 && SLUG_PATTERN.test(value);
}

// ADR-122: a slug rename moves canonical_path and every /org/:slug link, so
// the vendor reviews the impact and retypes the current slug before it runs.
export function OrganizationSlugRenameDialog({
  accessToken,
  locale,
  organization,
  onClose,
  onRenamed,
}: {
  accessToken: string | undefined;
  locale: string;
  organization: PlatformOrganization;
  onClose: () => void;
  onRenamed: (result: OrganizationSlugRenameResult) => void;
}) {
  const copy = platformOrganizationSlugCopy(locale);
  const organizationId = organization.organization.id;
  const currentSlug = organization.organization.slug;
  const [newSlug, setNewSlug] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [result, setResult] = useState<OrganizationSlugRenameResult | null>(null);

  const impactQuery = useQuery({
    queryKey: ["platform-organization-slug-impact", accessToken, organizationId],
    enabled: Boolean(accessToken),
    retry: false,
    queryFn: () => fetchOrganizationSlugImpact(accessToken!, organizationId),
  });
  const impact = impactQuery.data ?? null;

  const normalizedSlug = newSlug.trim().toLowerCase();
  const slugValid = isValidOrganizationSlug(normalizedSlug);
  const slugChanged = normalizedSlug !== currentSlug;
  const confirmed = confirmation.trim() === currentSlug;
  const canSubmit = Boolean(impact) && !impact?.purge_open && slugValid && slugChanged && confirmed && !submitting;

  function errorMessage(error: unknown) {
    if (!(error instanceof ApiError)) return copy.actionError;
    switch (error.payload.code) {
      case "invalid_slug":
        return copy.invalidSlug;
      case "slug_unchanged":
        return copy.unchanged;
      case "slug_taken":
        return copy.taken;
      case "slug_confirmation_mismatch":
        return copy.mismatch;
      case "slug_rename_blocked_by_purge":
        return copy.purgeBlocked;
      default:
        return copy.actionError;
    }
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!accessToken || !canSubmit) return;
    setSubmitting(true);
    setActionError(null);

    try {
      const renamed = await renamePlatformOrganizationSlug(accessToken, organizationId, {
        slug: normalizedSlug,
        confirmation,
      });
      setResult(renamed);
      onRenamed(renamed);
    } catch (error) {
      setActionError(errorMessage(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[var(--scrim)] p-4" role="dialog" aria-modal="true" aria-label={copy.title}>
      <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto bg-[var(--surface)] p-6 shadow-xl">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-xl font-semibold text-[var(--text)]">{copy.title}</h2>
            <p className="mt-1 text-sm text-[var(--text-soft)]">{organization.organization.name}</p>
          </div>
          <button type="button" onClick={onClose} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
            {copy.close}
          </button>
        </div>

        <p className="mt-4 text-sm leading-6 text-[var(--text-soft)]">{formatSlugCopy(copy.intro, { slug: currentSlug })}</p>

        {result ? (
          <p className="mt-5 border-l-4 border-[var(--accent)] bg-[var(--panel-muted)] px-4 py-3 text-sm font-semibold text-[var(--text)]" role="status">
            {formatSlugCopy(copy.done, { path: result.canonical_path })}
          </p>
        ) : null}

        {impactQuery.isLoading ? <p className="mt-5 text-sm text-[var(--text-soft)]">{copy.loading}</p> : null}
        {impactQuery.isError ? (
          <p className="mt-5 border-l-4 border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] px-4 py-3 text-sm font-semibold text-[var(--danger)]">{copy.loadError}</p>
        ) : null}

        {impact && !result ? (
          <form className="mt-5 space-y-5" onSubmit={(event) => void submit(event)}>
            <dl className="grid gap-3 border-y border-[var(--border)] py-4 text-sm sm:grid-cols-2">
              <div>
                <dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.currentPath}</dt>
                <dd className="mt-1 break-all font-semibold text-[var(--text)]">{impact.canonical_path}</dd>
              </div>
              <div>
                <dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.newPath}</dt>
                <dd className="mt-1 break-all font-semibold text-[var(--text)]" data-testid="slug-new-path">
                  {slugValid ? `/org/${normalizedSlug}` : "-"}
                </dd>
              </div>
            </dl>

            <div>
              <label className="block text-sm font-medium text-[var(--text)]">
                <span className="mb-1.5 block">{copy.newSlugLabel}</span>
                <input
                  value={newSlug}
                  onChange={(event) => setNewSlug(event.target.value)}
                  className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2.5 outline-none focus:border-[var(--accent)]"
                  autoComplete="off"
                  spellCheck={false}
                  aria-describedby="organization-slug-help"
                  aria-invalid={newSlug.length > 0 && !slugValid}
                />
              </label>
              <p id="organization-slug-help" className="mt-1 text-xs text-[var(--text-soft)]">{copy.newSlugHelp}</p>
            </div>

            <section>
              <h3 className="text-sm font-semibold uppercase text-[var(--text-soft)]">{copy.impactTitle}</h3>
              <ul className="mt-2 list-disc space-y-1 pl-5 text-sm leading-6 text-[var(--text)]">
                <li>{formatSlugCopy(copy.activeMembers, { count: impact.active_member_count })}</li>
                <li>{formatSlugCopy(copy.pendingInvitations, { count: impact.pending_invitation_count })}</li>
                <li>{formatSlugCopy(copy.bookmarks, { slug: currentSlug })}</li>
                <li>{copy.reserved}</li>
              </ul>
              {impact.previous_slugs.length > 0 ? (
                <p className="mt-3 break-all text-xs text-[var(--text-soft)]">
                  {copy.previousSlugs}: {impact.previous_slugs.map((entry) => entry.slug).join(", ")}
                </p>
              ) : null}
            </section>

            {impact.purge_open ? (
              <p className="border-l-4 border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] px-4 py-3 text-sm font-semibold text-[var(--danger)]">{copy.purgeBlocked}</p>
            ) : null}

            <section className="border border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] p-4 text-[var(--text)]">
              <label className="block text-sm font-medium">
                <span className="mb-1.5 block">{formatSlugCopy(copy.confirmationLabel, { slug: currentSlug })}</span>
                <input
                  value={confirmation}
                  onChange={(event) => setConfirmation(event.target.value)}
                  className="w-full border border-[var(--danger)] bg-[var(--panel)] px-3 py-2.5 text-[var(--text)] outline-none focus:border-[var(--danger)]"
                  autoComplete="off"
                  spellCheck={false}
                />
              </label>
              {actionError ? <p className="mt-3 text-sm font-semibold text-[var(--danger)]" role="alert">{actionError}</p> : null}
              <div className="mt-3 flex flex-wrap gap-3">
                <button type="submit" disabled={!canSubmit} className="bg-[var(--danger)] px-4 py-2 text-sm font-semibold text-[var(--danger-contrast)] disabled:opacity-50">
                  {submitting ? copy.confirming : copy.confirm}
                </button>
                <button type="button" onClick={onClose} className="border border-[var(--danger)] px-4 py-2 text-sm font-semibold">
                  {copy.cancel}
                </button>
              </div>
            </section>
          </form>
        ) : null}
      </div>
    </div>
  );
}
