"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import {
  changePlatformOrganizationLifecycle,
  changePlatformOrganizationSettings,
  deletePlatformOrganization,
  fetchPlatformOrganizationAccess,
  issuePlatformOrganizationInvitation,
  listPlatformOrganizations,
  provisionPlatformOrganization,
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
import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { platformOrganizationsCopy } from "@/i18n/platform-organizations";

const defaultForm: ProvisionOrganizationInput = {
  name: "",
  slug: "",
  timezone: "Europe/Athens",
  default_locale: "el",
  invitation_lifetime_seconds: 168 * 60 * 60,
  initial_owner_email: "",
  brand_name: "",
  brand_logo_url: "",
  brand_primary_color: "#1f6f5f",
};

const membershipRoles: OrganizationMembershipRole[] = ["owner", "admin", "coach", "member", "athlete"];

export function PlatformOrganizationsPage() {
  const locale = useUiLocale();
  const copy = platformOrganizationsCopy(locale);
  const { tokens } = useSession();
  const [form, setForm] = useState(defaultForm);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [invitation, setInvitation] = useState<ProvisionOrganizationResult | null>(null);
  const [copied, setCopied] = useState<"token" | "link" | null>(null);
  const [editing, setEditing] = useState<PlatformOrganization | null>(null);
  const [managingAccess, setManagingAccess] = useState<PlatformOrganization | null>(null);
  const [provisioningOpen, setProvisioningOpen] = useState(false);
  const [confirmingArchive, setConfirmingArchive] = useState<PlatformOrganization | null>(null);
  const [confirmingDelete, setConfirmingDelete] = useState<PlatformOrganization | null>(null);
  const [lifecycleSubmitting, setLifecycleSubmitting] = useState<string | null>(null);
  const [deleteSubmitting, setDeleteSubmitting] = useState<string | null>(null);

  const accessToken = tokens?.access_token;
  const organizationsQuery = useQuery({
    queryKey: ["platform-organizations", accessToken],
    queryFn: () => listPlatformOrganizations(accessToken!),
    enabled: Boolean(accessToken),
  });
  const organizations = organizationsQuery.data?.organizations ?? [];
  const forbidden = organizationsQuery.error instanceof ApiError && organizationsQuery.error.status === 403;

  async function provision(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!accessToken) return;
    setSubmitting(true);
    setError(null);

    try {
      const result = await provisionPlatformOrganization(accessToken, compact(form));
      setInvitation(result);
      setCopied(null);
      setForm(defaultForm);
      setProvisioningOpen(false);
      await organizationsQuery.refetch();
    } catch {
      setError(copy.provisionError);
    } finally {
      setSubmitting(false);
    }
  }

  async function updateLifecycle(organizationId: string, status: OrganizationStatus) {
    if (!accessToken) return;
    setError(null);
    setLifecycleSubmitting(`${organizationId}:${status}`);

    try {
      await changePlatformOrganizationLifecycle(accessToken, organizationId, status);
      await organizationsQuery.refetch();
      setConfirmingArchive(null);
    } catch {
      setError(copy.lifecycleError);
    } finally {
      setLifecycleSubmitting(null);
    }
  }

  async function saveSettings(settings: OrganizationSettings) {
    if (!accessToken || !editing) return;
    setError(null);

    try {
      await changePlatformOrganizationSettings(
        accessToken,
        editing.organization.id,
        settings,
      );
      await organizationsQuery.refetch();
      setEditing(null);
    } catch {
      setError(copy.settingsError);
    }
  }

  async function deleteOrganization(organizationId: string) {
    if (!accessToken) return;
    setError(null);
    setDeleteSubmitting(organizationId);

    try {
      await deletePlatformOrganization(accessToken, organizationId);
      await organizationsQuery.refetch();
      setConfirmingDelete(null);
    } catch {
      setError(copy.deleteError);
    } finally {
      setDeleteSubmitting(null);
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
        <button
          type="button"
          onClick={() => setProvisioningOpen(true)}
          className="bg-[var(--accent)] px-4 py-3 text-sm font-semibold text-white"
        >
          {copy.create}
        </button>
      </header>

      {error ? (
        <div className="mt-5 flex items-center justify-between gap-4 border-l-4 border-red-600 bg-red-50 px-4 py-3 text-sm text-red-900">
          <span>{error}</span>
          <button type="button" className="font-semibold underline" onClick={() => void organizationsQuery.refetch()}>
            {copy.retry}
          </button>
        </div>
      ) : null}

      {!error && organizationsQuery.isError && !forbidden ? (
        <div className="mt-5 border-l-4 border-red-600 bg-red-50 px-4 py-3 text-sm text-red-900">
          {copy.loadError}
        </div>
      ) : null}

      {invitation ? (
        <section className="mt-6 border border-amber-400 bg-amber-50 p-5 text-amber-950">
          <h2 className="text-lg font-semibold">{copy.copyTokenTitle}</h2>
          <p className="mt-1 text-sm">{copy.copyTokenWarning}</p>
          <p className="mt-4 text-xs font-semibold uppercase">{copy.ownerSetupLink}</p>
          <code className="mt-1 block break-all border border-amber-300 bg-white px-3 py-3 text-sm">
            {ownerSetupUrl(invitation.initial_owner_invitation.token)}
          </code>
          <code className="mt-4 block break-all border border-amber-300 bg-white px-3 py-3 text-sm">
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
              className="border border-amber-900 bg-amber-900 px-4 py-2 text-sm font-semibold text-white"
            >
              {copied === "token" ? copy.copied : copy.copyToken}
            </button>
            <button
              type="button"
              onClick={async () => {
                await navigator.clipboard.writeText(ownerSetupUrl(invitation.initial_owner_invitation.token));
                setCopied("link");
              }}
              className="border border-amber-900 bg-amber-900 px-4 py-2 text-sm font-semibold text-white"
            >
              {copied === "link" ? copy.copied : copy.copyOwnerSetupLink}
            </button>
            <button
              type="button"
              onClick={() => setInvitation(null)}
              className="border border-amber-900 px-4 py-2 text-sm font-semibold"
            >
              {copy.dismiss}
            </button>
          </div>
        </section>
      ) : null}

      <div className="mt-8">
        <section aria-labelledby="organization-list-title">
          <h2 id="organization-list-title" className="sr-only">{copy.title}</h2>
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
                    <span className="inline-flex border border-[var(--border)] bg-[var(--surface-muted)] px-3 py-1.5 text-sm font-semibold text-[var(--text)]">
                      {statusLabels[entry.organization.status]}
                    </span>
                  </div>
                  <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
                    <Detail label={copy.timezone} value={entry.settings?.timezone ?? "-"} />
                    <Detail label={copy.locale} value={entry.settings?.default_locale ?? "-"} />
                    <Detail label={copy.brandName} value={entry.settings?.brand_name ?? entry.organization.name} />
                  </dl>
                  <div className="mt-4 flex flex-wrap gap-3">
                    {entry.organization.status === "active" ? (
                      <Link
                        href="/admin"
                        className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold"
                        onClick={() => rememberSelectedOrganization(entry.organization.slug)}
                      >
                        {copy.open}
                      </Link>
                    ) : null}
                    <button type="button" onClick={() => setEditing(entry)} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
                      {copy.edit}
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
                        className="border border-red-700 px-3 py-2 text-sm font-semibold text-red-800"
                      >
                        {copy.archive}
                      </button>
                    ) : null}
                    <button
                      type="button"
                      onClick={() => setConfirmingDelete(entry)}
                      className="border border-red-900 bg-red-50 px-3 py-2 text-sm font-semibold text-red-900"
                    >
                      {copy.delete}
                    </button>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      </div>

      {editing?.settings ? (
        <SettingsDialog
          copy={copy}
          organization={editing}
          onCancel={() => setEditing(null)}
          onSave={saveSettings}
        />
      ) : null}
      {managingAccess ? (
        <AccessDialog
          accessToken={accessToken}
          copy={copy}
          organization={managingAccess}
          onCancel={() => setManagingAccess(null)}
        />
      ) : null}
      {provisioningOpen ? (
        <ProvisionDialog
          copy={copy}
          form={form}
          submitting={submitting}
          onCancel={() => setProvisioningOpen(false)}
          onChange={setForm}
          onSubmit={provision}
        />
      ) : null}
      {confirmingArchive ? (
        <ArchiveDialog
          copy={copy}
          organization={confirmingArchive}
          submitting={lifecycleSubmitting === `${confirmingArchive.organization.id}:archived`}
          onCancel={() => setConfirmingArchive(null)}
          onConfirm={() => void updateLifecycle(confirmingArchive.organization.id, "archived")}
        />
      ) : null}
      {confirmingDelete ? (
        <DeleteDialog
          copy={copy}
          organization={confirmingDelete}
          submitting={deleteSubmitting === confirmingDelete.organization.id}
          onCancel={() => setConfirmingDelete(null)}
          onConfirm={() => void deleteOrganization(confirmingDelete.organization.id)}
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

function ownerSetupUrl(token: string) {
  const path = `/set-admin?token=${encodeURIComponent(token)}`;
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
}

function rememberSelectedOrganization(slug: string) {
  try {
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, slug);
  } catch {}
}

function TextField({ label, value, onChange, type = "text", ...inputProps }: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
} & Pick<React.InputHTMLAttributes<HTMLInputElement>, "required" | "min">) {
  return (
    <label className="block text-sm font-medium text-[var(--text)]">
      <span className="mb-1.5 block">{label}</span>
      <input
        {...inputProps}
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2.5 outline-none focus:border-[var(--accent)]"
      />
    </label>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return <div><dt className="text-xs font-semibold uppercase text-[var(--text-soft)]">{label}</dt><dd className="mt-1 break-words text-[var(--text)]">{value}</dd></div>;
}

function AccessDialog({ accessToken, copy, organization, onCancel }: {
  accessToken: string | undefined;
  copy: ReturnType<typeof platformOrganizationsCopy>;
  organization: PlatformOrganization;
  onCancel: () => void;
}) {
  const [role, setRole] = useState<OrganizationMembershipRole>("member");
  const [email, setEmail] = useState("");
  const [lifetimeHours, setLifetimeHours] = useState("168");
  const [invitePending, setInvitePending] = useState(false);
  const [rolePending, setRolePending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [invitation, setInvitation] = useState<PlatformInvitationResult["invitation"] | null>(null);
  const [copied, setCopied] = useState<"token" | "link" | null>(null);

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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-label={copy.accessTitle}>
      <div className="max-h-[90vh] w-full max-w-3xl overflow-y-auto bg-[var(--surface)] p-6 shadow-xl">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-xl font-semibold text-[var(--text)]">{copy.accessTitle}</h2>
            <p className="mt-1 text-sm text-[var(--text-soft)]">{organization.organization.name}</p>
          </div>
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">{copy.cancel}</button>
        </div>

        {error ? <p className="mt-4 border-l-4 border-red-700 bg-red-50 px-4 py-3 text-sm font-semibold text-red-900">{error}</p> : null}
        {accessQuery.isError ? <p className="mt-4 border-l-4 border-red-700 bg-red-50 px-4 py-3 text-sm font-semibold text-red-900">{copy.accessError}</p> : null}

        <form className="mt-5 grid gap-3 border-y border-[var(--border)] py-5 sm:grid-cols-[1fr_1fr_1fr_auto]" onSubmit={invite}>
          <label className="text-sm font-medium text-[var(--text)]">
            <span className="mb-1.5 block">{copy.inviteRole}</span>
            <select
              className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2.5"
              value={role}
              onChange={(event) => setRole(event.target.value as OrganizationMembershipRole)}
            >
              {membershipRoles.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
            </select>
          </label>
          <TextField label={copy.inviteEmail} type="email" value={email} onChange={setEmail} />
          <TextField label={copy.inviteLifetime} type="number" min={1} value={lifetimeHours} required onChange={setLifetimeHours} />
          <button type="submit" disabled={invitePending} className="self-end bg-[var(--accent)] px-4 py-3 text-sm font-semibold text-white disabled:opacity-50">
            {invitePending ? copy.issuingInvite : copy.invite}
          </button>
        </form>

        {invitation ? (
          <section className="mt-4 border border-amber-400 bg-amber-50 p-4 text-amber-950">
            <p className="text-sm font-semibold">{copy.ownerSetupLink}</p>
            <code className="mt-2 block break-all border border-amber-300 bg-white px-3 py-2 text-sm">{ownerSetupUrl(invitation.token)}</code>
            <code className="mt-3 block break-all border border-amber-300 bg-white px-3 py-2 text-sm">{invitation.token}</code>
            <p className="mt-2 text-xs">{copy.expires}: {new Date(invitation.expires_at).toLocaleString()}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button type="button" onClick={async () => { await navigator.clipboard.writeText(invitation.token); setCopied("token"); }} className="border border-amber-900 px-3 py-2 text-sm font-semibold">{copied === "token" ? copy.copied : copy.copyToken}</button>
              <button type="button" onClick={async () => { await navigator.clipboard.writeText(ownerSetupUrl(invitation.token)); setCopied("link"); }} className="border border-amber-900 px-3 py-2 text-sm font-semibold">{copied === "link" ? copy.copied : copy.copyOwnerSetupLink}</button>
            </div>
          </section>
        ) : null}

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
                <select
                  className="w-full border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm"
                  disabled={rolePending === membership.id}
                  value={membership.role}
                  onChange={(event) => void changeRole(membership.id, event.target.value as OrganizationMembershipRole)}
                >
                  {membershipRoles.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
                </select>
              </label>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function ProvisionDialog({ copy, form, submitting, onCancel, onChange, onSubmit }: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  form: ProvisionOrganizationInput;
  submitting: boolean;
  onCancel: () => void;
  onChange: (form: ProvisionOrganizationInput) => void;
  onSubmit: (event: React.FormEvent<HTMLFormElement>) => Promise<void>;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-label={copy.create}>
      <form
        className="max-h-[90vh] w-full max-w-lg overflow-y-auto bg-[var(--surface)] p-6 shadow-xl"
        onSubmit={onSubmit}
      >
        <h2 className="text-xl font-semibold text-[var(--text)]">{copy.create}</h2>
        <div className="mt-5 space-y-4">
          <TextField label={copy.name} value={form.name} required onChange={(name) => onChange({ ...form, name })} />
          <TextField label={copy.slug} value={form.slug ?? ""} onChange={(slug) => onChange({ ...form, slug })} />
          <TextField label={copy.timezone} value={form.timezone} required onChange={(timezone) => onChange({ ...form, timezone })} />
          <TextField label={copy.locale} value={form.default_locale} required onChange={(default_locale) => onChange({ ...form, default_locale })} />
          <TextField
            label={copy.invitationLifetime}
            type="number"
            min={1}
            value={String(form.invitation_lifetime_seconds / 3600)}
            required
            onChange={(hours) => onChange({ ...form, invitation_lifetime_seconds: Number(hours) * 3600 })}
          />
          <TextField label={copy.ownerEmail} type="email" value={form.initial_owner_email ?? ""} onChange={(initial_owner_email) => onChange({ ...form, initial_owner_email })} />
          <TextField label={copy.brandName} value={form.brand_name ?? ""} onChange={(brand_name) => onChange({ ...form, brand_name })} />
          <TextField label={copy.brandLogo} type="url" value={form.brand_logo_url ?? ""} onChange={(brand_logo_url) => onChange({ ...form, brand_logo_url })} />
          <TextField label={copy.brandColor} value={form.brand_primary_color ?? ""} onChange={(brand_primary_color) => onChange({ ...form, brand_primary_color })} />
        </div>
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="submit" disabled={submitting} className="bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
            {submitting ? copy.provisioning : copy.provision}
          </button>
        </div>
      </form>
    </div>
  );
}

function ArchiveDialog({ copy, organization, submitting, onCancel, onConfirm }: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  organization: PlatformOrganization;
  submitting: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-label={copy.archiveTitle}>
      <div className="w-full max-w-md bg-[var(--surface)] p-6 shadow-xl">
        <h2 className="text-xl font-semibold text-[var(--text)]">{copy.archiveTitle}</h2>
        <p className="mt-2 font-semibold text-[var(--text)]">{organization.organization.name}</p>
        <p className="mt-3 text-sm leading-6 text-[var(--text-soft)]">{copy.archiveBody}</p>
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="button" disabled={submitting} onClick={onConfirm} className="bg-red-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
            {copy.archiveConfirm}
          </button>
        </div>
      </div>
    </div>
  );
}

function DeleteDialog({ copy, organization, submitting, onCancel, onConfirm }: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  organization: PlatformOrganization;
  submitting: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-label={copy.deleteTitle}>
      <div className="w-full max-w-md bg-[var(--surface)] p-6 shadow-xl">
        <h2 className="text-xl font-semibold text-[var(--text)]">{copy.deleteTitle}</h2>
        <p className="mt-2 font-semibold text-[var(--text)]">{organization.organization.name}</p>
        <p className="mt-3 text-sm leading-6 text-[var(--text-soft)]">{copy.deleteBody}</p>
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="button" disabled={submitting} onClick={onConfirm} className="bg-red-800 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
            {copy.deleteConfirm}
          </button>
        </div>
      </div>
    </div>
  );
}

function SettingsDialog({ copy, organization, onCancel, onSave }: {
  copy: ReturnType<typeof platformOrganizationsCopy>;
  organization: PlatformOrganization;
  onCancel: () => void;
  onSave: (settings: OrganizationSettings) => Promise<void>;
}) {
  const [settings, setSettings] = useState(organization.settings!);
  const [saving, setSaving] = useState(false);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-label={copy.settings}>
      <form
        className="max-h-[90vh] w-full max-w-lg overflow-y-auto bg-[var(--surface)] p-6 shadow-xl"
        onSubmit={async (event) => {
          event.preventDefault();
          setSaving(true);
          await onSave(settings);
          setSaving(false);
        }}
      >
        <h2 className="text-xl font-semibold text-[var(--text)]">{organization.organization.name}</h2>
        <div className="mt-5 space-y-4">
          <TextField label={copy.timezone} value={settings.timezone} required onChange={(timezone) => setSettings({ ...settings, timezone })} />
          <TextField label={copy.locale} value={settings.default_locale} required onChange={(default_locale) => setSettings({ ...settings, default_locale })} />
          <TextField label={copy.invitationLifetime} type="number" min={1} value={String(settings.invitation_lifetime_seconds / 3600)} required onChange={(hours) => setSettings({ ...settings, invitation_lifetime_seconds: Number(hours) * 3600 })} />
          <TextField label={copy.brandName} value={settings.brand_name ?? ""} onChange={(brand_name) => setSettings({ ...settings, brand_name })} />
          <TextField label={copy.brandLogo} type="url" value={settings.brand_logo_url ?? ""} onChange={(brand_logo_url) => setSettings({ ...settings, brand_logo_url })} />
          <TextField label={copy.brandColor} value={settings.brand_primary_color ?? ""} onChange={(brand_primary_color) => setSettings({ ...settings, brand_primary_color })} />
        </div>
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" onClick={onCancel} className="border border-[var(--border-strong)] px-4 py-2 text-sm font-semibold">{copy.cancel}</button>
          <button type="submit" disabled={saving} className="bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{saving ? copy.saving : copy.saveSettings}</button>
        </div>
      </form>
    </div>
  );
}
