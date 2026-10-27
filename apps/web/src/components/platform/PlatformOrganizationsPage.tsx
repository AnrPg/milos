"use client";

import Link from "next/link";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  changePlatformOrganizationLifecycle,
  changePlatformOrganizationSettings,
  fetchPlatformOrganizationAccess,
  issuePlatformOrganizationInvitation,
  listPlatformOrganizations,
  provisionPlatformOrganization,
  renamePlatformOrganization,
  fetchOwnerInvitationDeliveries,
  sendOwnerInvitationEmail,
  type OwnerInvitationDelivery,
  updatePlatformOrganizationMembershipRole,
  type OrganizationMembershipRole,
  type OrganizationSettings,
  type OrganizationStatus,
  type PlatformOrganization,
  type PlatformInvitationResult,
  type ProvisionOrganizationInput,
  type ProvisionOrganizationResult,
} from "@/api/platform-organizations";
import { ApiError } from "@/api/client";
import { useOrganizationMemberships } from "@/lib/membership-role";
import { platformLogoApi } from "@/api/organization-branding";
import { TenantLogoUploader } from "@/components/branding/TenantLogoUploader";
import { OrganizationPurgeDialog } from "@/components/platform/OrganizationPurgeDialog";
import { OrganizationSlugRenameDialog } from "@/components/platform/OrganizationSlugRenameDialog";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { platformOrganizationPurgeCopy } from "@/i18n/platform-organization-purge";
import { platformOrganizationSlugCopy } from "@/i18n/platform-organization-slug";
import { platformOrganizationsCopy } from "@/i18n/platform-organizations";
import { membershipWorkspaceHref, rememberSelectedOrganization } from "@/lib/organization-slug";
import { Dialog } from "@/components/ui/Dialog";
import { FieldError } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, formErrorsFrom, invalidFieldProps, type FormErrors } from "@/lib/form-errors";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { LOCALE_NAMES, SUPPORTED_LOCALES, isAppLocale } from "@/i18n/locales";

const defaultForm: ProvisionOrganizationInput = {
  name: "",
  slug: "",
  timezone: "Europe/Athens",
  default_locale: "el",
  invitation_lifetime_seconds: 168 * 60 * 60,
  initial_owner_email: "",
  brand_name: "",
  brand_logo_url: "",
};

const membershipRoles: OrganizationMembershipRole[] = ["owner", "admin", "coach", "member", "athlete"];

type GeneratedInvitation = PlatformInvitationResult["invitation"] & {
  id: string;
  intended_email: string | null;
  issued_at: string;
};

/** ADR-214: the fields of the vendor's organisation forms, as the API names them. */
const ORGANIZATION_FIELDS = [
  "name",
  "slug",
  "timezone",
  "default_locale",
  "invitation_lifetime_seconds",
  "initial_owner_email",
  "brand_name",
  "brand_logo_url",
] as const;
type OrganizationField = (typeof ORGANIZATION_FIELDS)[number];

export function PlatformOrganizationsPage() {
  const locale = useUiLocale();
  const i18n = useUiTranslations();
  // ADR-214: what the open dialog's last save got wrong, shown inside it.
  const [dialogErrors, setDialogErrors] = useState<FormErrors<OrganizationField> | null>(null);
  const copy = platformOrganizationsCopy(locale);
  const purgeCopy = platformOrganizationPurgeCopy(locale);
  const slugCopy = platformOrganizationSlugCopy(locale);
  const tResets = useTranslations("passwordResets");
  const tBusiness = useTranslations("Business");
  const { tokens } = useSession();
  const [form, setForm] = useState(defaultForm);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [invitation, setInvitation] = useState<ProvisionOrganizationResult | null>(null);
  const [invitationEmail, setInvitationEmail] = useState<string | null>(null);
  const [copied, setCopied] = useState<"token" | "link" | null>(null);
  const [sendingEmail, setSendingEmail] = useState(false);
  const [emailSendError, setEmailSendError] = useState<string | null>(null);
  const [emailLocale, setEmailLocale] = useState<string>("el");
  const [emailDelivery, setEmailDelivery] = useState<OwnerInvitationDelivery | null>(null);
  const [editing, setEditing] = useState<PlatformOrganization | null>(null);
  const [managingAccess, setManagingAccess] = useState<PlatformOrganization | null>(null);
  const [provisioningOpen, setProvisioningOpen] = useState(false);
  const [confirmingArchive, setConfirmingArchive] = useState<PlatformOrganization | null>(null);
  const [reviewingPurge, setReviewingPurge] = useState<PlatformOrganization | null>(null);
  const [renamingSlug, setRenamingSlug] = useState<PlatformOrganization | null>(null);
  const [lifecycleSubmitting, setLifecycleSubmitting] = useState<string | null>(null);
  const [generatedInvitationsByOrg, setGeneratedInvitationsByOrg] = useState<
    Record<string, GeneratedInvitation[]>
  >({});
  const [expandedInvitationHistory, setExpandedInvitationHistory] = useState<Record<string, boolean>>({});

  const accessToken = tokens?.access_token;
  const organizationsQuery = useQuery({
    queryKey: ["platform-organizations", accessToken],
    queryFn: () => listPlatformOrganizations(accessToken!),
    enabled: Boolean(accessToken),
  });
  const organizations = organizationsQuery.data?.organizations ?? [];
  const unconfirmedZones = organizations.filter(zoneUnconfirmed).length;
  const forbidden = organizationsQuery.error instanceof ApiError && organizationsQuery.error.status === 403;

  // A vendor who also holds a real membership somewhere (owner/admin/coach/
  // member/athlete) needs a way back into that tenant's own workspace -
  // provisioning/settings here don't substitute for actually using the app
  // as a member. /admin requires a genuine membership row server-side, so
  // this list - not "every active org" - is what's actually openable.
  const myMembershipsQuery = useOrganizationMemberships();
  const myMemberships = useMemo(() => myMembershipsQuery.data ?? [], [myMembershipsQuery.data]);
  const myMembershipByOrgId = useMemo(
    () => new Map(myMemberships.map((entry) => [entry.organization.id, entry])),
    [myMemberships],
  );

  async function provision(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!accessToken) return;
    setSubmitting(true);
    setDialogErrors(null);

    try {
      const result = await provisionPlatformOrganization(accessToken, compact(form));
      setInvitation(result);
      setInvitationEmail(form.initial_owner_email ?? null);
      setCopied(null);
      setEmailDelivery(null);
      setEmailSendError(null);
      setEmailLocale(emailLocaleFor(result.settings?.default_locale ?? form.default_locale));
      setForm(defaultForm);
      setProvisioningOpen(false);
      rememberGeneratedInvitation(result.organization.id, {
        ...result.initial_owner_invitation,
        id: `${result.organization.id}:${result.initial_owner_invitation.token}`,
        intended_email: form.initial_owner_email || null,
        issued_at: new Date().toISOString(),
      });
      await organizationsQuery.refetch();
    } catch (reason) {
      setDialogErrors(formErrorsFrom(reason, i18n, ORGANIZATION_FIELDS, { fallback: copy.provisionError }));
    } finally {
      setSubmitting(false);
    }
  }

  function rememberGeneratedInvitation(organizationId: string, generatedInvitation: GeneratedInvitation) {
    setGeneratedInvitationsByOrg((current) => ({
      ...current,
      [organizationId]: [generatedInvitation, ...(current[organizationId] ?? [])],
    }));
  }

  // ADR-210: the email is queued, not sent in the request; while it waits,
  // the console reads its delivery status again.
  const deliveriesQuery = useQuery({
    queryKey: ["owner-invitation-deliveries", invitation?.initial_owner_invitation.id, accessToken],
    queryFn: () =>
      fetchOwnerInvitationDeliveries(
        accessToken!,
        invitation!.organization.id,
        invitation!.initial_owner_invitation.id,
      ),
    enabled: Boolean(accessToken && invitation && emailDelivery),
    refetchInterval: (query) => {
      const latest = query.state.data?.deliveries[0];
      return latest && (latest.status === "queued" || latest.status === "deferred") ? 5000 : false;
    },
  });
  const latestDelivery = deliveriesQuery.data?.deliveries[0] ?? emailDelivery;

  async function sendInvitationEmail(resend = false) {
    if (!accessToken || !invitation || !invitationEmail) return;
    setSendingEmail(true);
    setEmailSendError(null);

    try {
      const result = await sendOwnerInvitationEmail(accessToken, invitation.organization.id, {
        email: invitationEmail,
        token: invitation.initial_owner_invitation.token,
        locale: emailLocale,
        resend,
      });
      setEmailDelivery(result.delivery);
      if (emailDelivery) await deliveriesQuery.refetch();
    } catch (failure) {
      setEmailSendError(sendEmailErrorText(failure, copy));
    } finally {
      setSendingEmail(false);
    }
  }

  async function updateLifecycle(organizationId: string, status: OrganizationStatus) {
    if (!accessToken) return;
    setError(null);
    setDialogErrors(null);
    setLifecycleSubmitting(`${organizationId}:${status}`);

    try {
      await changePlatformOrganizationLifecycle(accessToken, organizationId, status);
      await organizationsQuery.refetch();
      setConfirmingArchive(null);
    } catch {
      // The archive dialog shows it; a status change without one, the page.
      if (status === "archived") setDialogErrors({ fields: {}, message: copy.lifecycleError });
      else setError(copy.lifecycleError);
    } finally {
      setLifecycleSubmitting(null);
    }
  }

  async function saveSettings(name: string, settings: OrganizationSettings) {
    if (!accessToken || !editing) return;
    setDialogErrors(null);

    try {
      if (name !== editing.organization.name) {
        await renamePlatformOrganization(accessToken, editing.organization.id, name);
      }
      // The logo is managed by its own upload/remove endpoints (ADR-121);
      // never echo a possibly stale brand_logo_url back through settings.
      const editableSettings: Partial<OrganizationSettings> = { ...settings };
      delete editableSettings.brand_logo_url;
      delete editableSettings.brand_logo_uploaded;
      await changePlatformOrganizationSettings(
        accessToken,
        editing.organization.id,
        editableSettings,
      );
      await organizationsQuery.refetch();
      setEditing(null);
    } catch (reason) {
      setDialogErrors(formErrorsFrom(reason, i18n, ORGANIZATION_FIELDS, { fallback: copy.settingsError }));
    }
  }

  const statusLabels = useMemo<Record<OrganizationStatus, string>>(
    () => ({ active: copy.active, suspended: copy.suspended, archived: copy.archived }),
    [copy],
  );

  if (organizationsQuery.isLoading) {
    return <main className="mx-auto w-full max-w-7xl px-4 py-10 text-sm">{copy.loading}</main>;
  }

  if (forbidden) {
    return (
      <main className="mx-auto w-full max-w-3xl px-4 py-12">
        <h1 className="text-2xl font-semibold text-[var(--text)]">{copy.title}</h1>
        <p className="mt-4 text-[var(--text-soft)]">{copy.forbidden}</p>
      </main>
    );
  }

  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <header className="flex flex-col justify-between gap-4 border-b border-[var(--border)] pb-5 sm:flex-row sm:items-end">
        <div>
          <h1 className="text-3xl font-semibold text-[var(--text)]">{copy.title}</h1>
          <p className="mt-1 text-sm text-[var(--text-soft)]">{copy.subtitle}</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link
            href="/platform/tag-suggestions"
            className="border border-[var(--border)] px-4 py-3 text-sm font-semibold text-[var(--text-soft)]"
          >
            {copy.tagSuggestions}
          </Link>
          <Link
            href="/platform/business-accounts"
            className="border border-[var(--border)] px-4 py-3 text-sm font-semibold text-[var(--text-soft)]"
          >
            {tBusiness("console.title")}
          </Link>
          <Link
            href="/platform/plans"
            className="border border-[var(--border)] px-4 py-3 text-sm font-semibold text-[var(--text-soft)]"
          >
            {copy.plans}
          </Link>
          <Link
            href="/platform/password-resets"
            className="border border-[var(--border)] px-4 py-3 text-sm font-semibold text-[var(--text-soft)]"
          >
            {tResets("logButton")}
          </Link>
          <button
            type="button"
            onClick={() => setProvisioningOpen(true)}
            className="bg-[var(--accent)] px-4 py-3 text-sm font-semibold text-[var(--primary-contrast)]"
          >
            {copy.create}
          </button>
        </div>
      </header>

      {error ? (
        <ErrorNotice
          className="mt-5"
          action={
            <button type="button" className="font-semibold underline" onClick={() => void organizationsQuery.refetch()}>
              {copy.retry}
            </button>
          }
        >
          {error}
        </ErrorNotice>
      ) : null}

      {!error && organizationsQuery.isError && !forbidden ? (
        <ErrorNotice className="mt-5">
          {copy.loadError}
        </ErrorNotice>
      ) : null}

      {invitation ? (
        <section className="mt-6 border border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] bg-[color-mix(in_srgb,var(--warning)_10%,var(--panel))] p-5 text-[var(--text)]">
          <h2 className="text-lg font-semibold">{copy.copyTokenTitle}</h2>
          <p className="mt-1 text-sm">{copy.copyTokenWarning}</p>
          <p className="mt-4 text-xs font-semibold uppercase">{copy.ownerSetupLink}</p>
          <code className="mt-1 block break-all border border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] bg-[var(--panel)] px-3 py-3 text-sm">
            {ownerSetupUrl(invitation.initial_owner_invitation.token)}
          </code>
          <code className="mt-4 block break-all border border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] bg-[var(--panel)] px-3 py-3 text-sm">
            {invitation.initial_owner_invitation.token}
          </code>
          <p className="mt-2 text-xs">
            {copy.expires}: {new Date(invitation.initial_owner_invitation.expires_at).toLocaleString(locale)}
          </p>
          <div className="mt-4 flex flex-wrap gap-3">
            <button
              type="button"
              onClick={async () => {
                await navigator.clipboard.writeText(invitation.initial_owner_invitation.token);
                setCopied("token");
              }}
              className="border border-[var(--warning)] bg-[var(--warning)] px-4 py-2 text-sm font-semibold text-[var(--warning-contrast)]"
            >
              {copied === "token" ? copy.copied : copy.copyToken}
            </button>
            <button
              type="button"
              onClick={async () => {
                await navigator.clipboard.writeText(ownerSetupUrl(invitation.initial_owner_invitation.token));
                setCopied("link");
              }}
              className="border border-[var(--warning)] bg-[var(--warning)] px-4 py-2 text-sm font-semibold text-[var(--warning-contrast)]"
            >
              {copied === "link" ? copy.copied : copy.copyOwnerSetupLink}
            </button>
            <button
              type="button"
              onClick={() => setInvitation(null)}
              className="border border-[var(--warning)] px-4 py-2 text-sm font-semibold"
            >
              {copy.dismiss}
            </button>
          </div>
          {invitationEmail ? (
            <div className="mt-4 flex flex-col gap-3 border-t border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] pt-4">
              <div className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-xs font-semibold uppercase">
                  {copy.emailLanguage}
                  <Select
                    className="min-w-40 border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm normal-case"
                    value={emailLocale}
                    disabled={sendingEmail}
                    onValueChange={setEmailLocale}
                  >
                    {SUPPORTED_LOCALES.map((entry) => <option key={entry} value={entry}>{LOCALE_NAMES[entry]}</option>)}
                  </Select>
                </label>
                <button
                  type="button"
                  disabled={sendingEmail}
                  onClick={() => void sendInvitationEmail(Boolean(latestDelivery))}
                  className="border border-[var(--warning)] bg-[var(--warning)] px-4 py-2 text-sm font-semibold text-[var(--warning-contrast)] disabled:opacity-60"
                >
                  {sendingEmail
                    ? copy.sendingEmail
                    : latestDelivery
                      ? copy.resendEmail
                      : `${copy.sendEmail} ${invitationEmail}`}
                </button>
              </div>
              {latestDelivery ? (
                <p className="flex flex-wrap items-center gap-2 text-sm" role="status" data-testid="owner-invitation-delivery">
                  <span className="font-semibold">{copy.deliveryStatus}:</span>
                  <span>{deliveryStatusText(latestDelivery, copy)}</span>
                  <span className="text-xs text-[var(--text-soft)]">
                    {invitationEmail} · {new Date(latestDelivery.sent_at ?? latestDelivery.inserted_at).toLocaleString(locale)}
                  </span>
                  <button type="button" className="text-xs font-semibold underline" onClick={() => void deliveriesQuery.refetch()}>
                    {copy.refreshDelivery}
                  </button>
                </p>
              ) : null}
              {emailSendError ? <ErrorNotice variant="field">{emailSendError}</ErrorNotice> : null}
            </div>
          ) : null}
        </section>
      ) : null}

      {myMemberships.length > 0 ? (
        <section className="mt-8" aria-labelledby="my-memberships-title">
          <h2 id="my-memberships-title" className="text-sm font-semibold uppercase tracking-[0.18em] text-[var(--dim)]">
            {copy.myMemberships}
          </h2>
          <div className="mt-3 flex flex-wrap gap-3">
            {myMemberships.map((membership) => (
              <Link
                key={membership.id}
                href={membershipWorkspaceHref(membership)}
                onClick={() => rememberSelectedOrganization(membership.organization.slug)}
                className="flex items-center gap-2 border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold text-[var(--text)]"
              >
                {membership.organization.name}
                <span className="text-xs font-normal uppercase tracking-[0.1em] text-[var(--dim)]">
                  {membership.role}
                </span>
              </Link>
            ))}
          </div>
        </section>
      ) : null}

      <div className="mt-8">
        <section aria-labelledby="organization-list-title">
          <h2 id="organization-list-title" className="sr-only">{copy.title}</h2>
          {unconfirmedZones > 0 ? (
            <p className="mb-3 text-sm text-[var(--warning)]">
              {copy.timezoneUnconfirmedCount.replace("{count}", String(unconfirmedZones))}
            </p>
          ) : null}
          {organizations.length === 0 ? (
            <p className="border-t border-[var(--border)] py-8 text-sm text-[var(--text-soft)]">{copy.empty}</p>
          ) : (
            <div className="divide-y divide-[var(--border)] border-y border-[var(--border)]">
              {organizations.map((entry) => (
                <article key={entry.organization.id} className="py-5">
                  <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                    <div className="min-w-0">
                      <h3 className="truncate text-lg font-semibold text-[var(--text)]">{entry.organization.name}</h3>
                      <p className="mt-1 break-all text-sm text-[var(--text-soft)]">{entry.canonical_path}</p>
                    </div>
                    <div className="flex shrink-0 flex-wrap items-center gap-2">
                      {entry.pending_registration ? (
                        <span className="inline-flex border border-[var(--primary)] bg-[var(--panel-muted)] px-3 py-1.5 text-sm font-semibold text-[var(--primary)]">
                          {copy.pendingRegistration}
                        </span>
                      ) : null}
                      <span className="inline-flex border border-[var(--border)] bg-[var(--panel-muted)] px-3 py-1.5 text-sm font-semibold text-[var(--text)]">
                        {statusLabels[entry.organization.status]}
                      </span>
                    </div>
                  </div>
                  <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
                    <div>
                      <Detail label={copy.timezone} value={entry.settings?.timezone ?? "-"} />
                      {zoneUnconfirmed(entry) ? (
                        <span className="mt-1 inline-flex border border-[var(--warning)] px-2 py-0.5 text-xs font-semibold text-[var(--warning)]" title={copy.timezoneUnconfirmedTitle}>
                          {copy.timezoneUnconfirmed}
                        </span>
                      ) : null}
                    </div>
                    <Detail label={copy.locale} value={entry.settings?.default_locale ?? "-"} />
                    <Detail label={copy.brandName} value={entry.settings?.brand_name ?? entry.organization.name} />
                  </dl>
                  <div className="mt-4 flex flex-wrap gap-3">
                    {entry.organization.status === "active" && myMembershipByOrgId.has(entry.organization.id) ? (
                      <Link
                        href={membershipWorkspaceHref(myMembershipByOrgId.get(entry.organization.id)!)}
                        className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold"
                        onClick={() => rememberSelectedOrganization(entry.organization.slug)}
                      >
                        {copy.open}
                      </Link>
                    ) : null}
                    <button type="button" onClick={() => setEditing(entry)} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
                      {copy.edit}
                    </button>
                    <button type="button" onClick={() => setRenamingSlug(entry)} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
                      {slugCopy.open}
                    </button>
                    <button type="button" onClick={() => setManagingAccess(entry)} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
                      {copy.manageAccess}
                    </button>
                    {entry.organization.status === "active" ? (
                      <button
                        type="button"
                        disabled={lifecycleSubmitting === `${entry.organization.id}:suspended`}
                        onClick={() => void updateLifecycle(entry.organization.id, "suspended")}
                        className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold disabled:opacity-50"
                      >
                        {copy.suspend}
                      </button>
                    ) : (
                      <button
                        type="button"
                        disabled={lifecycleSubmitting === `${entry.organization.id}:active`}
                        onClick={() => void updateLifecycle(entry.organization.id, "active")}
                        className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold disabled:opacity-50"
                      >
                        {copy.activate}
                      </button>
                    )}
                    {entry.organization.status !== "archived" ? (
                      <button
                        type="button"
                        onClick={() => setConfirmingArchive(entry)}
                        className="border border-[var(--danger)] px-3 py-2 text-sm font-semibold text-[var(--danger)]"
                      >
                        {copy.archive}
                      </button>
                    ) : null}
                    {/* Deleting always goes through export, backup and purge (the dialog explains each step). */}
                    <button
                      type="button"
                      onClick={() => setReviewingPurge(entry)}
                      className="border border-[var(--danger)] bg-[color-mix(in_srgb,var(--danger)_10%,var(--panel))] px-3 py-2 text-sm font-semibold text-[var(--danger)]"
                    >
                      {purgeCopy.open}
                    </button>
                  </div>
                  <GeneratedInvitationsList
                    copy={copy}
                    invitations={generatedInvitationsByOrg[entry.organization.id] ?? []}
                    expanded={Boolean(expandedInvitationHistory[entry.organization.id])}
                    locale={locale}
                    onToggle={() =>
                      setExpandedInvitationHistory((current) => ({
                        ...current,
                        [entry.organization.id]: !current[entry.organization.id],
                      }))
                    }
                  />
                </article>
              ))}
            </div>
          )}
        </section>
      </div>

      {editing?.settings ? (
        <SettingsDialog
          accessToken={accessToken}
          copy={copy}
          organization={editing}
          errors={dialogErrors}
          onCancel={() => {
            setEditing(null);
            setDialogErrors(null);
          }}
          onLogoChanged={() => void organizationsQuery.refetch()}
          onSave={saveSettings}
        />
      ) : null}
      {managingAccess ? (
        <AccessDialog
          accessToken={accessToken}
          copy={copy}
          generatedInvitations={generatedInvitationsByOrg[managingAccess.organization.id] ?? []}
          organization={managingAccess}
          onCancel={() => setManagingAccess(null)}
          onInvitationIssued={(generatedInvitation) =>
            rememberGeneratedInvitation(managingAccess.organization.id, generatedInvitation)
          }
        />
      ) : null}
      {provisioningOpen ? (
        <ProvisionDialog
          copy={copy}
          form={form}
          submitting={submitting}
          errors={dialogErrors}
          onCancel={() => {
            setProvisioningOpen(false);
            setDialogErrors(null);
          }}
          onChange={setForm}
          onSubmit={provision}
        />
      ) : null}
      {confirmingArchive ? (
        <ArchiveDialog
          copy={copy}
          organization={confirmingArchive}
          submitting={lifecycleSubmitting === `${confirmingArchive.organization.id}:archived`}
          error={dialogErrors?.message ?? null}
          onCancel={() => {
            setConfirmingArchive(null);
            setDialogErrors(null);
          }}
          onConfirm={() => void updateLifecycle(confirmingArchive.organization.id, "archived")}
        />
      ) : null}
      {reviewingPurge ? (
        <OrganizationPurgeDialog
          accessToken={accessToken}
          locale={locale}
          organization={reviewingPurge}
          onClose={() => setReviewingPurge(null)}
          onChanged={() => void organizationsQuery.refetch()}
        />
      ) : null}
      {renamingSlug ? (
        <OrganizationSlugRenameDialog
          accessToken={accessToken}
          locale={locale}
          organization={renamingSlug}
          onClose={() => setRenamingSlug(null)}
          onRenamed={() => {
            void organizationsQuery.refetch();
            void myMembershipsQuery.refetch();
          }}
        />
      ) : null}
    </main>
  );
}

function compact(input: ProvisionOrganizationInput): ProvisionOrganizationInput {
  return Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== "" && value !== undefined),
  ) as ProvisionOrganizationInput;
}

/** The email's language: the business's default when Palee speaks it, else Greek. */
function emailLocaleFor(defaultLocale: string | null | undefined) {
  return isAppLocale(defaultLocale) ? defaultLocale : "el";
}

function deliveryStatusText(delivery: OwnerInvitationDelivery, copy: ReturnType<typeof platformOrganizationsCopy>) {
  switch (delivery.status) {
    case "sent":
      return copy.deliverySent;
    case "deferred":
      return copy.deliveryDeferred;
    case "failed":
      return copy.deliveryFailed;
    case "suppressed":
      return copy.deliverySuppressed;
    default:
      return copy.deliveryQueued;
  }
}

function sendEmailErrorText(failure: unknown, copy: ReturnType<typeof platformOrganizationsCopy>) {
  const code = failure instanceof ApiError ? failure.payload.code : undefined;
  if (code === "throttled") return copy.sendEmailThrottled;
  if (code === "suppressed") return copy.sendEmailSuppressed;
  if (code === "invitation_email_mismatch") return copy.sendEmailMismatch;
  if (code === "invalid_invitation") return copy.sendEmailInvalid;
  return copy.sendEmailError;
}

function ownerSetupUrl(token: string) {
  const path = `/set-admin?token=${encodeURIComponent(token)}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
}

function invitationSetupUrl(invitation: Pick<PlatformInvitationResult["invitation"], "role" | "token">) {
  const route = invitation.role === "owner" || invitation.role === "admin" ? "/set-admin" : "/register";
  const path = `${route}?token=${encodeURIComponent(invitation.token)}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
}


function TextField({ label, value, onChange, type = "text", error, errorId, ...inputProps }: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  /** ADR-214: why the value is wrong, shown under the field (which turns red). */
  error?: string;
  errorId?: string;
} & Pick<React.InputHTMLAttributes<HTMLInputElement>, "required" | "min">) {
  const describedBy = errorId ?? `field-error-${label.replace(/\W+/g, "-").toLowerCase()}`;
  return (
    <label className="block text-sm font-medium text-[var(--text)]">
      <span className="mb-1.5 block">{label}</span>
      <input
        {...inputProps}
        {...invalidFieldProps(error, describedBy)}
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2.5 outline-none focus:border-[var(--accent)]"
        style={error ? { border: fieldBorder(error) } : undefined}
      />
      <FieldError id={describedBy}>{error}</FieldError>
    </label>
  );
}

/** ADR-179: a live gym whose clock is still a guess (inferred or default). */
function zoneUnconfirmed(entry: PlatformOrganization) {
  return entry.organization.status === "active" && entry.settings?.timezone_source !== "confirmed";
}

function Detail({ label, value }: { label: string; value: string }) {
  return <div><dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{label}</dt><dd className="mt-1 break-words text-[var(--text)]">{value}</dd></div>;
}

function AccessDialog({
  accessToken,
  copy,
  generatedInvitations,
  organization,
  onCancel,
  onInvitationIssued,
}: {
  accessToken: string | undefined;
  copy: ReturnType<typeof platformOrganizationsCopy>;
  generatedInvitations: GeneratedInvitation[];
  organization: PlatformOrganization;
  onCancel: () => void;
  onInvitationIssued: (generatedInvitation: GeneratedInvitation) => void;
}) {
  const [role, setRole] = useState<OrganizationMembershipRole>("admin");
  const [email, setEmail] = useState("");
  const [lifetimeHours, setLifetimeHours] = useState("168");
  const [invitePending, setInvitePending] = useState(false);
  const [rolePending, setRolePending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [invitation, setInvitation] = useState<PlatformInvitationResult["invitation"] | null>(null);
  const [copied, setCopied] = useState<"token" | "link" | null>(null);
  const [historyExpanded, setHistoryExpanded] = useState(false);

  const accessQuery = useQuery({
    queryKey: ["platform-organization-access", accessToken, organization.organization.id],
    enabled: Boolean(accessToken),
    queryFn: () => fetchPlatformOrganizationAccess(accessToken!, organization.organization.id),
  });

  async function invite(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!accessToken) return;
    setInvitePending(true);
    setError(null);

    try {
      const result = await issuePlatformOrganizationInvitation(accessToken, organization.organization.id, {
        role,
        intended_email: email.trim() || undefined,
        lifetime_seconds: Math.max(1, Number(lifetimeHours) || 168) * 3600,
      });
      setInvitation(result.invitation);
      onInvitationIssued({
        ...result.invitation,
        id: `${organization.organization.id}:${result.invitation.token}`,
        intended_email: email.trim() || null,
        issued_at: new Date().toISOString(),
      });
      setCopied(null);
      setEmail("");
    } catch {
      setError(copy.inviteError);
    } finally {
      setInvitePending(false);
    }
  }

  async function changeRole(membershipId: string, nextRole: OrganizationMembershipRole) {
    if (!accessToken) return;
    setRolePending(membershipId);
    setError(null);

    try {
      await updatePlatformOrganizationMembershipRole(
        accessToken,
        organization.organization.id,
        membershipId,
        nextRole,
      );
      await accessQuery.refetch();
    } catch {
      setError(copy.roleError);
    } finally {
      setRolePending(null);
    }
  }

  return (
    <Dialog
      onClose={onCancel}
      title={copy.accessTitle}
      ariaLabel={copy.accessTitle}
      description={organization.organization.name}
      size="3xl"
      variant="center"
      showClose={false}
      headerActions={<button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">{copy.cancel}</button>}
    >
        {error ? <ErrorNotice className="mt-4">{error}</ErrorNotice> : null}
        {accessQuery.isError ? <ErrorNotice className="mt-4">{copy.accessError}</ErrorNotice> : null}

        <form className="mt-5 grid gap-3 border-y border-[var(--border)] py-5 sm:grid-cols-[1fr_1fr_1fr_auto]" onSubmit={invite}>
          <label className="text-sm font-medium text-[var(--text)]">
            <span className="mb-1.5 block">{copy.inviteRole}</span>
            <Select
              className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2.5"
              value={role}
              onValueChange={(value) => setRole(value as OrganizationMembershipRole)}
            >
              {membershipRoles.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
            </Select>
          </label>
          <TextField label={copy.inviteEmail} type="email" value={email} onChange={setEmail} />
          <TextField label={copy.inviteLifetime} type="number" min={1} value={lifetimeHours} required onChange={setLifetimeHours} />
          <button type="submit" disabled={invitePending} className="self-end bg-[var(--accent)] px-4 py-3 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50">
            {invitePending ? copy.issuingInvite : copy.invite}
          </button>
        </form>

        {invitation ? (
          <section className="mt-4 border border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] bg-[color-mix(in_srgb,var(--warning)_10%,var(--panel))] p-4 text-[var(--text)]">
            <p className="text-sm font-semibold">{copy.ownerSetupLink}</p>
            <code className="mt-2 block break-all border border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] bg-[var(--panel)] px-3 py-2 text-sm">{invitationSetupUrl(invitation)}</code>
            <code className="mt-3 block break-all border border-[color-mix(in_srgb,var(--warning)_45%,var(--border))] bg-[var(--panel)] px-3 py-2 text-sm">{invitation.token}</code>
            <p className="mt-2 text-xs">{copy.expires}: {new Date(invitation.expires_at).toLocaleString()}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button type="button" onClick={async () => { await navigator.clipboard.writeText(invitation.token); setCopied("token"); }} className="border border-[var(--warning)] px-3 py-2 text-sm font-semibold">{copied === "token" ? copy.copied : copy.copyToken}</button>
              <button type="button" onClick={async () => { await navigator.clipboard.writeText(invitationSetupUrl(invitation)); setCopied("link"); }} className="border border-[var(--warning)] px-3 py-2 text-sm font-semibold">{copied === "link" ? copy.copied : copy.copyOwnerSetupLink}</button>
            </div>
          </section>
        ) : null}

        <GeneratedInvitationsList
          copy={copy}
          invitations={generatedInvitations}
          expanded={historyExpanded}
          onToggle={() => setHistoryExpanded((current) => !current)}
        />

        <div className="mt-5 divide-y divide-[var(--border)] border-y border-[var(--border)]">
          {accessQuery.isLoading ? <p className="py-5 text-sm text-[var(--text-soft)]">{copy.loading}</p> : null}
          {(accessQuery.data?.memberships ?? []).map((membership) => (
            <div key={membership.id} className="grid gap-3 py-4 sm:grid-cols-[1fr_10rem_12rem] sm:items-center">
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-[var(--text)]">{membership.user?.nickname ?? membership.user_id}</p>
                <p className="mt-1 text-xs text-[var(--text-soft)]">{copy.globalAccountType}: {membership.user?.role ?? "-"}</p>
              </div>
              <p className="text-sm text-[var(--text-soft)]">{membership.status}</p>
              <label className="text-xs font-semibold text-[var(--text-soft)]">
                <span className="mb-1 block">{copy.membershipRole}</span>
                <Select
                  className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm"
                  disabled={rolePending === membership.id}
                  value={membership.role}
                  onValueChange={(value) => void changeRole(membership.id, value as OrganizationMembershipRole)}
                >
                  {membershipRoles.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
                </Select>
              </label>
            </div>
          ))}
        </div>
    </Dialog>
  );
}

function GeneratedInvitationsList({
  copy,
  expanded,
  invitations,
  locale,
  onToggle,
}: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  expanded: boolean;
  invitations: GeneratedInvitation[];
  locale?: string;
  onToggle: () => void;
}) {
  if (invitations.length === 0) return null;

  return (
    <section className="mt-4 border border-[var(--border)] bg-[var(--panel-muted)] p-3">
      <button
        type="button"
        aria-expanded={expanded}
        onClick={onToggle}
        className="flex w-full items-center justify-between gap-3 text-left text-sm font-semibold text-[var(--text)]"
      >
        <span>{copy.generatedInvitations} ({invitations.length})</span>
        <span aria-hidden="true">{expanded ? "-" : "+"}</span>
      </button>
      {expanded ? (
        <div className="mt-3 space-y-2">
          {invitations.map((invitation) => (
            <details key={invitation.id} className="border border-[var(--border)] bg-[var(--surface)] px-3 py-2">
              <summary className="cursor-pointer text-sm font-semibold text-[var(--text)]">
                {invitation.role}
                {invitation.intended_email ? ` · ${invitation.intended_email}` : ""}
              </summary>
              <dl className="mt-3 grid gap-3 text-xs sm:grid-cols-2">
                <Detail label={copy.role} value={invitation.role} />
                <Detail label={copy.intendedEmail} value={invitation.intended_email ?? "-"} />
                <Detail label={copy.issued} value={new Date(invitation.issued_at).toLocaleString(locale)} />
                <Detail label={copy.expires} value={new Date(invitation.expires_at).toLocaleString(locale)} />
              </dl>
              <p className="mt-3 text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.setupLink}</p>
              <code className="mt-1 block break-all border border-[var(--border)] bg-[var(--panel-muted)] px-3 py-2 text-xs">
                {invitationSetupUrl(invitation)}
              </code>
              <p className="mt-3 text-xs font-semibold uppercase text-[var(--text-soft)]">{copy.token}</p>
              <code className="mt-1 block break-all border border-[var(--border)] bg-[var(--panel-muted)] px-3 py-2 text-xs">
                {invitation.token}
              </code>
            </details>
          ))}
        </div>
      ) : null}
    </section>
  );
}

function ProvisionDialog({ copy, form, submitting, errors, onCancel, onChange, onSubmit }: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  form: ProvisionOrganizationInput;
  submitting: boolean;
  errors: FormErrors<OrganizationField> | null;
  onCancel: () => void;
  onChange: (form: ProvisionOrganizationInput) => void;
  onSubmit: (event: React.FormEvent<HTMLFormElement>) => Promise<void>;
}) {
  return (
    <Dialog
      onClose={onCancel}
      title={copy.create}
      closeLabel={copy.cancel}
      ariaLabel={copy.create}
      size="lg"
      variant="center"
      error={errors?.message}
      onSubmit={onSubmit}
      footer={
        <div className="w-full flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="submit" disabled={submitting} className="bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50">
            {submitting ? copy.provisioning : copy.provision}
          </button>
        </div>
      }
    >
        <div className="space-y-4">
          <TextField label={copy.name} error={errors?.fields.name} value={form.name} required onChange={(name) => onChange({ ...form, name })} />
          <TextField label={copy.slug} error={errors?.fields.slug} value={form.slug ?? ""} onChange={(slug) => onChange({ ...form, slug })} />
          <TextField label={copy.timezone} error={errors?.fields.timezone} value={form.timezone} required onChange={(timezone) => onChange({ ...form, timezone })} />
          <TextField label={copy.locale} error={errors?.fields.default_locale} value={form.default_locale} required onChange={(default_locale) => onChange({ ...form, default_locale })} />
          <TextField
            label={copy.invitationLifetime}
            error={errors?.fields.invitation_lifetime_seconds}
            type="number"
            min={1}
            value={String(form.invitation_lifetime_seconds / 3600)}
            required
            onChange={(hours) => onChange({ ...form, invitation_lifetime_seconds: Number(hours) * 3600 })}
          />
          <TextField label={copy.ownerEmail} error={errors?.fields.initial_owner_email} type="email" required value={form.initial_owner_email ?? ""} onChange={(initial_owner_email) => onChange({ ...form, initial_owner_email })} />
          <TextField label={copy.brandName} error={errors?.fields.brand_name} value={form.brand_name ?? ""} onChange={(brand_name) => onChange({ ...form, brand_name })} />
          <TextField label={copy.brandLogo} error={errors?.fields.brand_logo_url} type="url" value={form.brand_logo_url ?? ""} onChange={(brand_logo_url) => onChange({ ...form, brand_logo_url })} />
        </div>
    </Dialog>
  );
}

function ArchiveDialog({ copy, organization, submitting, error, onCancel, onConfirm }: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  organization: PlatformOrganization;
  submitting: boolean;
  error: string | null;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <Dialog
      onClose={onCancel}
      title={copy.archiveTitle}
      closeLabel={copy.cancel}
      ariaLabel={copy.archiveTitle}
      size="md"
      variant="center"
      error={error}
      footer={
        <div className="w-full flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="button" disabled={submitting} onClick={onConfirm} className="bg-[var(--danger)] px-4 py-2 text-sm font-semibold text-[var(--danger-contrast)] disabled:opacity-50">
            {copy.archiveConfirm}
          </button>
        </div>
      }
    >
        <p className="font-semibold text-[var(--text)]">{organization.organization.name}</p>
        <p className="mt-3 text-sm leading-6 text-[var(--text-soft)]">{copy.archiveBody}</p>
    </Dialog>
  );
}

function SettingsDialog({ accessToken, copy, organization, errors, onCancel, onSave, onLogoChanged }: {
  accessToken: string | undefined;
  copy: ReturnType<typeof platformOrganizationsCopy>;
  organization: PlatformOrganization;
  errors: FormErrors<OrganizationField> | null;
  onCancel: () => void;
  onSave: (name: string, settings: OrganizationSettings) => Promise<void>;
  onLogoChanged: () => void;
}) {
  const [name, setName] = useState(organization.organization.name);
  const [settings, setSettings] = useState(organization.settings!);
  const [saving, setSaving] = useState(false);
  const logoApi = useMemo(
    () => (accessToken ? platformLogoApi(accessToken, organization.organization.id) : null),
    [accessToken, organization.organization.id],
  );

  return (
    <Dialog
      onClose={onCancel}
      title={organization.organization.name}
      closeLabel={copy.cancel}
      ariaLabel={copy.settings}
      size="lg"
      variant="center"
      error={errors?.message}
      onSubmit={async (event) => {
          event.preventDefault();
          setSaving(true);
          await onSave(name, settings);
          setSaving(false);
        }}
      footer={
        <div className="w-full flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="submit" disabled={saving} className="bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50">{saving ? copy.saving : copy.saveSettings}</button>
        </div>
      }
    >
        <div className="space-y-4">
          <TextField label={copy.name} error={errors?.fields.name} value={name} required onChange={setName} />
          <TextField label={copy.timezone} error={errors?.fields.timezone} value={settings.timezone} required onChange={(timezone) => setSettings({ ...settings, timezone })} />
          <TextField label={copy.locale} error={errors?.fields.default_locale} value={settings.default_locale} required onChange={(default_locale) => setSettings({ ...settings, default_locale })} />
          <TextField label={copy.invitationLifetime} error={errors?.fields.invitation_lifetime_seconds} type="number" min={1} value={String(settings.invitation_lifetime_seconds / 3600)} required onChange={(hours) => setSettings({ ...settings, invitation_lifetime_seconds: Number(hours) * 3600 })} />
          <TextField label={copy.brandName} error={errors?.fields.brand_name} value={settings.brand_name ?? ""} onChange={(brand_name) => setSettings({ ...settings, brand_name })} />
          {logoApi ? (
            <div>
              <span className="text-sm font-semibold text-[var(--text)]">{copy.brandLogoUpload}</span>
              <div className="mt-2">
                <TenantLogoUploader
                  api={logoApi}
                  currentUrl={settings.brand_logo_url}
                  uploaded={Boolean(settings.brand_logo_uploaded)}
                  onChange={(branding) => {
                    setSettings((current) => ({
                      ...current,
                      brand_logo_url: branding.brand_logo_url ?? null,
                      brand_logo_uploaded: branding.brand_logo_uploaded,
                    }));
                    onLogoChanged();
                  }}
                />
              </div>
            </div>
          ) : null}
        </div>
    </Dialog>
  );
}
