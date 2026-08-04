"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import {
  changePlatformOrganizationLifecycle,
  changePlatformOrganizationSettings,
  listPlatformOrganizations,
  provisionPlatformOrganization,
  type OrganizationSettings,
  type OrganizationStatus,
  type PlatformOrganization,
  type ProvisionOrganizationInput,
  type ProvisionOrganizationResult,
} from "@/api/platform-organizations";
import { ApiError } from "@/api/client";
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

    try {
      await changePlatformOrganizationLifecycle(accessToken, organizationId, status);
      await organizationsQuery.refetch();
    } catch {
      setError(copy.lifecycleError);
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
      <header className="border-b border-[var(--border)] pb-5">
        <h1 className="text-3xl font-semibold text-[var(--text)]">{copy.title}</h1>
        <p className="mt-1 text-sm text-[var(--text-soft)]">{copy.subtitle}</p>
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

      <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(280px,360px)_minmax(0,1fr)]">
        <section aria-labelledby="provision-title">
          <h2 id="provision-title" className="text-lg font-semibold text-[var(--text)]">
            {copy.create}
          </h2>
          <form className="mt-4 space-y-4" onSubmit={provision}>
            <TextField label={copy.name} value={form.name} required onChange={(name) => setForm({ ...form, name })} />
            <TextField label={copy.slug} value={form.slug ?? ""} onChange={(slug) => setForm({ ...form, slug })} />
            <TextField label={copy.timezone} value={form.timezone} required onChange={(timezone) => setForm({ ...form, timezone })} />
            <TextField label={copy.locale} value={form.default_locale} required onChange={(default_locale) => setForm({ ...form, default_locale })} />
            <TextField
              label={copy.invitationLifetime}
              type="number"
              min={1}
              value={String(form.invitation_lifetime_seconds / 3600)}
              required
              onChange={(hours) => setForm({ ...form, invitation_lifetime_seconds: Number(hours) * 3600 })}
            />
            <TextField label={copy.ownerEmail} type="email" value={form.initial_owner_email ?? ""} onChange={(initial_owner_email) => setForm({ ...form, initial_owner_email })} />
            <TextField label={copy.brandName} value={form.brand_name ?? ""} onChange={(brand_name) => setForm({ ...form, brand_name })} />
            <TextField label={copy.brandLogo} type="url" value={form.brand_logo_url ?? ""} onChange={(brand_logo_url) => setForm({ ...form, brand_logo_url })} />
            <TextField label={copy.brandColor} value={form.brand_primary_color ?? ""} onChange={(brand_primary_color) => setForm({ ...form, brand_primary_color })} />
            <button
              type="submit"
              disabled={submitting}
              className="w-full bg-[var(--accent)] px-4 py-3 text-sm font-semibold text-white disabled:opacity-50"
            >
              {submitting ? copy.provisioning : copy.provision}
            </button>
          </form>
        </section>

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
                    <select
                      aria-label={copy.status}
                      value={entry.organization.status}
                      onChange={(event) => void updateLifecycle(entry.organization.id, event.target.value as OrganizationStatus)}
                      className="border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm"
                    >
                      {Object.entries(statusLabels).map(([status, label]) => <option key={status} value={status}>{label}</option>)}
                    </select>
                  </div>
                  <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
                    <Detail label={copy.timezone} value={entry.settings?.timezone ?? "-"} />
                    <Detail label={copy.locale} value={entry.settings?.default_locale ?? "-"} />
                    <Detail label={copy.brandName} value={entry.settings?.brand_name ?? entry.organization.name} />
                  </dl>
                  <div className="mt-4 flex flex-wrap gap-3">
                    <Link href={entry.canonical_path} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
                      {copy.open}
                    </Link>
                    <button type="button" onClick={() => setEditing(entry)} className="border border-[var(--border-strong)] px-3 py-2 text-sm font-semibold">
                      {copy.edit}
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
