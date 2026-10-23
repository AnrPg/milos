"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  fetchJoinLink,
  invitationUrl,
  issueClientInvitation,
  joinUrl,
  listPendingInvitations,
  revokeInvitation,
  updateJoinLink,
  type ClientRole,
  type IssuedInvitation,
} from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { localizeError, semanticLabel } from "@/i18n/presentation";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import {
  StaffInviteFields,
  staffInvitationBody,
  useInvitableStaffRoles,
  type StaffInvite,
} from "@/components/invites/StaffInviteFields";

type Tab = "link" | "public" | "pending";
type Translate = ReturnType<typeof useTranslations>;

const LIFETIMES = [1, 3, 7] as const;

/** Opens the invite dialog. Used on the dashboard, users page and onboarding. */
export function InviteClientsButton({
  variant = "primary",
  label,
  className = "",
}: {
  variant?: "primary" | "secondary";
  label?: string;
  className?: string;
}) {
  const t = useTranslations("Invites");
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold ${className}`}
        style={
          variant === "primary"
            ? { background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }
            : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
        }
      >
        <span aria-hidden="true">＋</span>
        {label ?? t("inviteClients")}
      </button>
      {open ? <InviteClientsDialog onClose={() => setOpen(false)} /> : null}
    </>
  );
}

export function InviteClientsDialog({ onClose, initialTab = "link" }: { onClose: () => void; initialTab?: Tab }) {
  const t = useTranslations("Invites");

  return (
    <Dialog
      onClose={onClose}
      title={t("inviteClients")}
      titleId="invite-clients-title"
      description={t("dialogIntro")}
      closeLabel={t("close")}
      size="xl"
    >
        
        <div className="">
          <ClientAccessTabs initialTab={initialTab} />
        </div>
    </Dialog>
  );
}

/** Settings → App configuration section: the same tools, inline. */
export function ClientAccessPanel() {
  const t = useTranslations("Invites");

  return (
    <section id="client-access" className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("clientAccess")}</h2>
      <p className="mt-1 max-w-2xl text-sm leading-6" style={{ color: "var(--muted)" }}>{t("clientAccessIntro")}</p>
      <div className="mt-4">
        <ClientAccessTabs initialTab="public" />
      </div>
    </section>
  );
}

function ClientAccessTabs({ initialTab }: { initialTab: Tab }) {
  const t = useTranslations("Invites");
  const [tab, setTab] = useState<Tab>(initialTab);
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const pending = useQuery({
    queryKey: ["pending-invitations", slug],
    enabled: Boolean(token && slug),
    queryFn: () => listPendingInvitations(token!, slug!),
  });

  const tabs: { id: Tab; label: string }[] = [
    { id: "link", label: t("tabPersonal") },
    { id: "public", label: t("tabPublic") },
    { id: "pending", label: t("tabPending", { count: pending.data?.length ?? 0 }) },
  ];

  if (!slug || !token) return null;

  return (
    <div>
      <div role="tablist" aria-label={t("inviteClients")} className="grid grid-cols-3 gap-1 rounded-xl p-1" style={{ background: "var(--panel-muted, var(--bg))" }}>
        {tabs.map((item) => (
          <button
            key={item.id}
            type="button"
            role="tab"
            aria-selected={tab === item.id}
            onClick={() => setTab(item.id)}
            className="rounded-lg px-2 py-2 text-xs font-semibold sm:text-sm"
            style={tab === item.id ? { background: "var(--panel)", color: "var(--text)", boxShadow: "var(--shadow-sm)" } : { color: "var(--muted)" }}
          >
            {item.label}
          </button>
        ))}
      </div>
      <div className="mt-4" role="tabpanel">
        {tab === "link" ? <PersonalInvite t={t} slug={slug} token={token} /> : null}
        {tab === "public" ? <PublicJoinLink t={t} slug={slug} token={token} /> : null}
        {tab === "pending" ? <PendingInvitations t={t} slug={slug} token={token} /> : null}
      </div>
    </div>
  );
}

function RolePicker({ t, value, onChange }: { t: Translate; value: ClientRole; onChange: (role: ClientRole) => void }) {
  return (
    <fieldset>
      <legend className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("joinsAs")}</legend>
      <div className="mt-2 grid grid-cols-2 gap-2">
        {(["member", "athlete"] as const).map((role) => (
          <label
            key={role}
            className="cursor-pointer rounded-xl p-3 text-sm"
            style={{
              border: value === role ? "1.5px solid var(--primary)" : "1px solid var(--border)",
              background: value === role ? "color-mix(in srgb, var(--primary) 10%, transparent)" : "transparent",
            }}
          >
            <input type="radio" name="invite-role" value={role} checked={value === role} onChange={() => onChange(role)} className="sr-only" />
            <span className="block font-semibold" style={{ color: "var(--text)" }}>{t(`roles.${role}`)}</span>
            <span className="mt-0.5 block text-xs" style={{ color: "var(--muted)" }}>{t(`roleHints.${role}`)}</span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

function PersonalInvite({ t, slug, token }: { t: Translate; slug: string; token: string }) {
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [role, setRole] = useState<ClientRole>("member");
  // ADR-186: staff links carry a role set and branches.
  const invitableStaff = useInvitableStaffRoles();
  const branchT = useTranslations("BranchScope");
  const [kind, setKind] = useState<"client" | "staff">("client");
  const [staff, setStaff] = useState<StaffInvite>({ roles: [], scope: null });
  const staffInvite = kind === "staff" && invitableStaff.length > 0;
  const staffIncomplete =
    staffInvite && (staff.roles.length === 0 || (Array.isArray(staff.scope) && staff.scope.length === 0));
  const [email, setEmail] = useState("");
  const [days, setDays] = useState<(typeof LIFETIMES)[number]>(7);
  const [issued, setIssued] = useState<IssuedInvitation | null>(null);
  const uiT = useTranslations("Ui");

  const issue = useMutation({
    mutationFn: () =>
      issueClientInvitation(token, slug, {
        ...(staffInvite ? staffInvitationBody(staff) : { role }),
        lifetime_seconds: days * 86_400,
        intended_email: email.trim() || undefined,
      }),
    onSuccess: (result) => {
      setIssued(result);
      void queryClient.invalidateQueries({ queryKey: ["pending-invitations", slug] });
    },
  });

  if (issued) {
    const url = invitationUrl(window.location.origin, issued);
    const issuedRoles = issued.roles?.length ? issued.roles : [issued.role];
    const clientLink = issuedRoles.every((item) => item === "member" || item === "athlete");
    return (
      <div className="space-y-3">
        <p className="text-sm font-semibold" style={{ color: "var(--success, var(--primary))" }}>
          {clientLink
            ? t("linkReady", { role: t(`roles.${issued.role === "athlete" ? "athlete" : "member"}`) })
            : branchT("staffLinkReady", { roles: issuedRoles.map((item) => semanticLabel(item, uiT)).join(", ") })}
        </p>
        <ShareBox t={t} url={url} message={t("inviteMessage", { organization: issued.organization.name, url })} subject={t("inviteSubject", { organization: issued.organization.name })} />
        <p className="text-xs" style={{ color: "var(--muted)" }}>
          {t("singleUse", { date: new Date(issued.expires_at).toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" }) })}
        </p>
        <button type="button" className="text-sm font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => { setIssued(null); setEmail(""); }}>
          {t("createAnother")}
        </button>
      </div>
    );
  }

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        issue.mutate();
      }}
    >
      {invitableStaff.length > 0 ? (
        <div role="radiogroup" aria-label={t("joinsAs")} className="grid grid-cols-2 gap-1 rounded-xl p-1" style={{ background: "var(--panel-muted, var(--bg))" }}>
          {(["client", "staff"] as const).map((option) => (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={kind === option}
              onClick={() => setKind(option)}
              className="rounded-lg px-3 py-2 text-sm font-semibold"
              style={kind === option ? { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" } : { color: "var(--muted)" }}
            >
              {option === "client" ? branchT("kindClient") : branchT("kindStaff")}
            </button>
          ))}
        </div>
      ) : null}
      {staffInvite ? (
        <StaffInviteFields token={token} value={staff} onChange={setStaff} />
      ) : (
        <RolePicker t={t} value={role} onChange={setRole} />
      )}
      <label className="block text-sm" style={{ color: "var(--text)" }}>
        <span className="font-semibold">{t("emailOptional")}</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          autoComplete="off"
          className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
          style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{t("emailHint")}</span>
      </label>
      <label className="block text-sm" style={{ color: "var(--text)" }}>
        <span className="font-semibold">{t("validFor")}</span>
        <Select
          value={days}
          onValueChange={(value) => setDays(Number(value) as (typeof LIFETIMES)[number])}
          className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
          style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {LIFETIMES.map((value) => (
            <option key={value} value={value}>{t("days", { count: value })}</option>
          ))}
        </Select>
      </label>
      {issue.error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(issue.error, uiT)}</p> : null}
      <button type="submit" disabled={issue.isPending || staffIncomplete} className="w-full rounded-xl px-4 py-3 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--text)", color: "var(--bg)" }}>
        {issue.isPending ? t("creating") : t("createLink")}
      </button>
    </form>
  );
}

function PublicJoinLink({ t, slug, token }: { t: Translate; slug: string; token: string }) {
  const queryClient = useQueryClient();
  const uiT = useTranslations("Ui");
  const joinLink = useQuery({ queryKey: ["join-link", slug], queryFn: () => fetchJoinLink(token, slug) });
  const save = useMutation({
    mutationFn: (body: { enabled?: boolean; role?: ClientRole }) => updateJoinLink(token, slug, body),
    onSuccess: (data) => {
      queryClient.setQueryData(["join-link", slug], data);
      void queryClient.invalidateQueries({ queryKey: ["admin-onboarding"] });
    },
  });
  const origin = typeof window === "undefined" ? "" : window.location.origin;

  if (joinLink.isPending) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>;
  if (joinLink.error) return <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(joinLink.error, uiT)}</p>;

  const data = joinLink.data!;
  const url = joinUrl(origin, slug);

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4 rounded-xl p-3" style={{ border: "1px solid var(--border)" }}>
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("publicTitle")}</p>
          <p className="mt-0.5 text-xs leading-5" style={{ color: "var(--muted)" }}>{t("publicHint")}</p>
        </div>
        <button
          type="button"
          role="switch"
          aria-checked={data.enabled}
          aria-label={t("publicTitle")}
          disabled={save.isPending}
          onClick={() => save.mutate({ enabled: !data.enabled })}
          className="relative h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-50"
          style={{ background: data.enabled ? "var(--success, var(--primary))" : "var(--border-strong, var(--border))" }}
        >
          <span className="absolute top-1 h-5 w-5 rounded-full bg-[var(--control-knob)] transition-all" style={{ insetInlineStart: data.enabled ? "1.5rem" : "0.25rem" }} />
        </button>
      </div>
      <RolePicker t={t} value={data.role as ClientRole} onChange={(role) => save.mutate({ role })} />
      {data.enabled ? (
        <>
          <ShareBox t={t} url={url} message={t("joinMessage", { url })} subject={t("joinSubject")} />
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("publicWarning", { role: t(`roles.${data.role as ClientRole}`) })}</p>
        </>
      ) : (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("publicOff")}</p>
      )}
      {save.error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(save.error, uiT)}</p> : null}
    </div>
  );
}

function PendingInvitations({ t, slug, token }: { t: Translate; slug: string; token: string }) {
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState<string | null>(null);
  const uiT = useTranslations("Ui");
  const pending = useQuery({ queryKey: ["pending-invitations", slug], queryFn: () => listPendingInvitations(token, slug) });
  const revoke = useMutation({
    mutationFn: (id: string) => revokeInvitation(token, slug, id),
    onSuccess: () => {
      setConfirming(null);
      void queryClient.invalidateQueries({ queryKey: ["pending-invitations", slug] });
    },
  });

  if (pending.isPending) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>;
  if (!pending.data?.length) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("noPending")}</p>;

  return (
    <ul className="divide-y" style={{ borderColor: "var(--border)" }}>
      {pending.data.map((invitation) => (
        <li key={invitation.id} className="flex flex-wrap items-center justify-between gap-2 py-3">
          <div>
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              {invitation.role === "athlete" || invitation.role === "member"
                ? t(`roles.${invitation.role}`)
                : (invitation.roles?.length ? invitation.roles : [invitation.role]).map((item) => semanticLabel(item, uiT)).join(", ")}
              {invitation.email_bound ? (
                <span className="ms-2 rounded-full px-2 py-0.5 text-[11px]" style={{ background: "var(--panel-muted, var(--bg))", color: "var(--muted)" }}>{t("emailBound")}</span>
              ) : null}
            </p>
            <p className="text-xs" style={{ color: "var(--muted)" }}>
              {t("expires", { date: new Date(invitation.expires_at).toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" }) })}
            </p>
          </div>
          {confirming === invitation.id ? (
            <div className="flex gap-2">
              <button type="button" onClick={() => revoke.mutate(invitation.id)} disabled={revoke.isPending} className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>
                {t("confirmRevoke")}
              </button>
              <button type="button" onClick={() => setConfirming(null)} className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                {t("keep")}
              </button>
            </div>
          ) : (
            <button type="button" onClick={() => setConfirming(invitation.id)} className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("revoke")}
            </button>
          )}
        </li>
      ))}
    </ul>
  );
}

function ShareBox({ t, url, message, subject }: { t: Translate; url: string; message: string; subject: string }) {
  const [copied, setCopied] = useState(false);
  const canShare = typeof navigator !== "undefined" && typeof navigator.share === "function";

  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <input readOnly value={url} aria-label={t("linkLabel")} onFocus={(event) => event.currentTarget.select()} className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm" style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }} />
        <button type="button" onClick={() => void copy()} className="shrink-0 rounded-xl px-4 py-2 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }}>
          {copied ? t("copied") : t("copy")}
        </button>
      </div>
      <p aria-live="polite" className="sr-only">{copied ? t("copied") : ""}</p>
      <div className="flex flex-wrap gap-2">
        {canShare ? (
          <button type="button" onClick={() => void navigator.share({ title: subject, text: message, url }).catch(() => undefined)} className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("share")}
          </button>
        ) : null}
        <a href={`mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(message)}`} className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {t("email")}
        </a>
        <a href={`https://wa.me/?text=${encodeURIComponent(message)}`} target="_blank" rel="noopener noreferrer" className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {t("whatsapp")}
        </a>
      </div>
    </div>
  );
}
