"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  BULK_INVITE_MAX,
  bulkInvite,
  fetchJoinLink,
  invitationUrl,
  issueClientInvitation,
  joinUrl,
  listPendingInvitations,
  parseInviteAddresses,
  resendInvitation,
  revokeInvitation,
  updateJoinLink,
  type BulkInvitationResult,
  type ClientRole,
  type IssuedInvitation,
  type JoinLinkChange,
  type PendingInvitation,
} from "@/api/organizations";
import { LOCALE_NAMES, SUPPORTED_LOCALES, isAppLocale, type AppLocale } from "@/i18n/locales";
import { useSelectedMembershipRole } from "@/lib/membership-role";
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
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { formatClock } from "@/lib/clock";

type Tab = "link" | "bulk" | "public" | "pending";
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
  const emailT = useTranslations("InviteEmail");
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
    { id: "bulk", label: emailT("tabBulk") },
    { id: "public", label: t("tabPublic") },
    { id: "pending", label: t("tabPending", { count: pending.data?.length ?? 0 }) },
  ];

  if (!slug || !token) return null;

  return (
    <div>
      <div role="tablist" aria-label={t("inviteClients")} className="grid grid-cols-4 gap-1 rounded-xl p-1" style={{ background: "var(--panel-muted, var(--bg))" }}>
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
        {tab === "bulk" ? <BulkInvite t={t} slug={slug} token={token} /> : null}
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

/** ADR-209: the box's language, the default of an invitation email. */
function useBoxEmailLocale(): { boxLocale: AppLocale; demo: boolean } {
  const { membership } = useSelectedMembershipRole();
  const uiLocale = useUiLocale();
  const stored = membership?.settings?.default_locale;
  const boxLocale = isAppLocale(stored) ? stored : isAppLocale(uiLocale) ? uiLocale : "en";
  return { boxLocale, demo: membership?.organization.activation === "demo" };
}

/** ADR-184: a box in demo mode invites and emails nobody; say why instead of a form. */
function DemoNotice() {
  const emailT = useTranslations("InviteEmail");
  return (
    <p role="note" className="rounded-xl p-3 text-sm leading-6" style={{ border: "1px solid var(--border)", background: "var(--panel-muted, var(--bg))", color: "var(--text-soft)" }}>
      {emailT("demoNotice")}
    </p>
  );
}

function EmailLocalePicker({ value, onChange, boxLocale }: { value: AppLocale; onChange: (locale: AppLocale) => void; boxLocale: AppLocale }) {
  const emailT = useTranslations("InviteEmail");
  return (
    <label className="block text-sm" style={{ color: "var(--text)" }}>
      <span className="font-semibold">{emailT("languageLabel")}</span>
      <Select
        value={value}
        onValueChange={(next) => isAppLocale(next) && onChange(next)}
        className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
        style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {SUPPORTED_LOCALES.map((locale) => (
          <option key={locale} value={locale}>
            {locale === boxLocale ? emailT("boxLanguage", { language: LOCALE_NAMES[locale] }) : LOCALE_NAMES[locale]}
          </option>
        ))}
      </Select>
    </label>
  );
}

/** ADR-209: email errors named in the invite screens, else the shared API message. */
function inviteErrorMessage(error: unknown, emailT: Translate, uiT: Translate) {
  const code = error instanceof ApiError ? error.payload.code : undefined;
  const known = ["invalid_address", "suppressed", "throttled", "over_budget", "invitation_email_required", "too_many_invitation_emails", "invitation_email_cap_reached", "invitation_not_emailed", "business_not_activated"];
  if (code && known.includes(code)) return emailT(`errors.${code}`, { max: BULK_INVITE_MAX });
  return localizeError(error, uiT);
}

function useInviteKind() {
  const invitableStaff = useInvitableStaffRoles();
  const [kind, setKind] = useState<"client" | "staff">("client");
  const [role, setRole] = useState<ClientRole>("member");
  const [staff, setStaff] = useState<StaffInvite>({ roles: [], scope: null });
  const staffInvite = kind === "staff" && invitableStaff.length > 0;
  const staffIncomplete =
    staffInvite && (staff.roles.length === 0 || (Array.isArray(staff.scope) && staff.scope.length === 0));
  return { invitableStaff, kind, setKind, role, setRole, staff, setStaff, staffInvite, staffIncomplete, body: staffInvite ? staffInvitationBody(staff) : { role } };
}

function InviteKindFields({ t, token, invite }: { t: Translate; token: string; invite: ReturnType<typeof useInviteKind> }) {
  const branchT = useTranslations("BranchScope");
  return (
    <>
      {invite.invitableStaff.length > 0 ? (
        <div role="radiogroup" aria-label={t("joinsAs")} className="grid grid-cols-2 gap-1 rounded-xl p-1" style={{ background: "var(--panel-muted, var(--bg))" }}>
          {(["client", "staff"] as const).map((option) => (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={invite.kind === option}
              onClick={() => invite.setKind(option)}
              className="rounded-lg px-3 py-2 text-sm font-semibold"
              style={invite.kind === option ? { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" } : { color: "var(--muted)" }}
            >
              {option === "client" ? branchT("kindClient") : branchT("kindStaff")}
            </button>
          ))}
        </div>
      ) : null}
      {invite.staffInvite ? (
        <StaffInviteFields token={token} value={invite.staff} onChange={invite.setStaff} />
      ) : (
        <RolePicker t={t} value={invite.role} onChange={invite.setRole} />
      )}
    </>
  );
}

function LifetimePicker({ t, value, onChange }: { t: Translate; value: (typeof LIFETIMES)[number]; onChange: (days: (typeof LIFETIMES)[number]) => void }) {
  return (
    <label className="block text-sm" style={{ color: "var(--text)" }}>
      <span className="font-semibold">{t("validFor")}</span>
      <Select
        value={value}
        onValueChange={(next) => onChange(Number(next) as (typeof LIFETIMES)[number])}
        className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
        style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {LIFETIMES.map((days) => (
          <option key={days} value={days}>{t("days", { count: days })}</option>
        ))}
      </Select>
    </label>
  );
}

function PersonalInvite({ t, slug, token }: { t: Translate; slug: string; token: string }) {
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const invite = useInviteKind();
  const branchT = useTranslations("BranchScope");
  const emailT = useTranslations("InviteEmail");
  const { boxLocale, demo } = useBoxEmailLocale();
  const [email, setEmail] = useState("");
  const [emailLocale, setEmailLocale] = useState<AppLocale | null>(null);
  const [days, setDays] = useState<(typeof LIFETIMES)[number]>(7);
  const [issued, setIssued] = useState<IssuedInvitation | null>(null);
  const uiT = useTranslations("Ui");
  const address = email.trim();

  const issue = useMutation({
    mutationFn: () =>
      issueClientInvitation(token, slug, {
        ...invite.body,
        lifetime_seconds: days * 86_400,
        // ADR-209: with an address the invitation goes by email; its token stays in the email.
        ...(address ? { intended_email: address, send_email: true, email_locale: emailLocale ?? boxLocale } : {}),
      }),
    onSuccess: (result) => {
      setIssued(result);
      void queryClient.invalidateQueries({ queryKey: ["pending-invitations", slug] });
    },
  });

  if (demo) return <DemoNotice />;

  const expiry = (value: string) => formatClock(new Date(value), locale, { dateStyle: "medium", timeStyle: "short" });

  if (issued?.email) {
    return (
      <div className="space-y-3" role="status">
        <p className="text-sm font-semibold" style={{ color: "var(--success, var(--primary))" }}>
          {emailT("sentTo", { email: issued.email })}
        </p>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{emailT("sentHint", { date: expiry(issued.expires_at) })}</p>
        <button type="button" className="text-sm font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => { setIssued(null); setEmail(""); }}>
          {emailT("sendAnother")}
        </button>
      </div>
    );
  }

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
          {t("singleUse", { date: expiry(issued.expires_at) })}
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
      <InviteKindFields t={t} token={token} invite={invite} />
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
        <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{address ? emailT("emailSendHint") : emailT("emailLinkHint")}</span>
      </label>
      {address ? <EmailLocalePicker value={emailLocale ?? boxLocale} onChange={setEmailLocale} boxLocale={boxLocale} /> : null}
      <LifetimePicker t={t} value={days} onChange={setDays} />
      {issue.error ? <ErrorNotice>{inviteErrorMessage(issue.error, emailT, uiT)}</ErrorNotice> : null}
      <button type="submit" disabled={issue.isPending || invite.staffIncomplete} className="w-full rounded-xl px-4 py-3 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--text)", color: "var(--bg)" }}>
        {issue.isPending ? (address ? emailT("sending") : t("creating")) : address ? emailT("send") : t("createLink")}
      </button>
    </form>
  );
}

/** ADR-209: one invitation and email per pasted (or CSV) address. */
function BulkInvite({ t, slug, token }: { t: Translate; slug: string; token: string }) {
  const queryClient = useQueryClient();
  const invite = useInviteKind();
  const emailT = useTranslations("InviteEmail");
  const uiT = useTranslations("Ui");
  const { boxLocale, demo } = useBoxEmailLocale();
  const [text, setText] = useState("");
  const [emailLocale, setEmailLocale] = useState<AppLocale | null>(null);
  const [days, setDays] = useState<(typeof LIFETIMES)[number]>(7);
  const [result, setResult] = useState<BulkInvitationResult | null>(null);
  const parsed = parseInviteAddresses(text);
  const tooMany = parsed.emails.length > BULK_INVITE_MAX;

  const send = useMutation({
    mutationFn: () =>
      bulkInvite(token, slug, {
        ...invite.body,
        emails: parsed.emails,
        lifetime_seconds: days * 86_400,
        email_locale: emailLocale ?? boxLocale,
      }),
    onSuccess: (data) => {
      setResult(data);
      void queryClient.invalidateQueries({ queryKey: ["pending-invitations", slug] });
    },
  });

  if (demo) return <DemoNotice />;

  if (result) {
    const failed = result.results.filter((row) => row.error);
    return (
      <div className="space-y-3">
        <p role="status" className="text-sm font-semibold" style={{ color: "var(--success, var(--primary))" }}>
          {emailT("bulkDone", { sent: result.sent })}
        </p>
        {failed.length ? (
          <div className="space-y-1">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{emailT("bulkFailed", { count: failed.length })}</p>
            <ul className="space-y-0.5 text-xs" style={{ color: "var(--muted)" }}>
              {failed.map((row) => (
                <li key={row.email}>{row.email}: {emailT.has(`errors.${row.error}`) ? emailT(`errors.${row.error}`, { max: BULK_INVITE_MAX }) : emailT("errors.other")}</li>
              ))}
            </ul>
          </div>
        ) : null}
        {result.skipped.length ? (
          <p className="text-xs" style={{ color: "var(--muted)" }}>{emailT("bulkSkipped", { values: result.skipped.join(", ") })}</p>
        ) : null}
        <button type="button" className="text-sm font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => { setResult(null); setText(""); }}>
          {emailT("sendAnother")}
        </button>
      </div>
    );
  }

  async function readCsv(file: File | undefined) {
    if (!file) return;
    const content = await file.text();
    setText((current) => (current.trim() ? `${current}\n${content}` : content));
  }

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        send.mutate();
      }}
    >
      <InviteKindFields t={t} token={token} invite={invite} />
      <label className="block text-sm" style={{ color: "var(--text)" }}>
        <span className="font-semibold">{emailT("bulkLabel")}</span>
        <textarea
          value={text}
          onChange={(event) => setText(event.target.value)}
          rows={5}
          autoComplete="off"
          className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
          style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{emailT("bulkHint", { max: BULK_INVITE_MAX })}</span>
      </label>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <label className="cursor-pointer rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {emailT("chooseCsv")}
          <input type="file" accept=".csv,text/csv,text/plain" className="sr-only" onChange={(event) => void readCsv(event.target.files?.[0])} />
        </label>
        <span aria-live="polite" className="text-xs" style={{ color: tooMany ? "var(--danger)" : "var(--muted)" }}>
          {tooMany ? emailT("errors.too_many_invitation_emails", { max: BULK_INVITE_MAX }) : emailT("bulkCount", { count: parsed.emails.length })}
        </span>
      </div>
      {parsed.emails.length ? <EmailLocalePicker value={emailLocale ?? boxLocale} onChange={setEmailLocale} boxLocale={boxLocale} /> : null}
      <LifetimePicker t={t} value={days} onChange={setDays} />
      {send.error ? <ErrorNotice>{inviteErrorMessage(send.error, emailT, uiT)}</ErrorNotice> : null}
      <button
        type="submit"
        disabled={send.isPending || invite.staffIncomplete || parsed.emails.length === 0 || tooMany}
        className="w-full rounded-xl px-4 py-3 text-sm font-semibold disabled:opacity-50"
        style={{ background: "var(--text)", color: "var(--bg)" }}
      >
        {send.isPending ? emailT("sending") : emailT("bulkSend", { count: parsed.emails.length })}
      </button>
    </form>
  );
}

/** ADR-216: one join link per client role, both usable at once; the visitor never picks the role. */
function PublicJoinLink({ t, slug, token }: { t: Translate; slug: string; token: string }) {
  const queryClient = useQueryClient();
  const uiT = useTranslations("Ui");
  const joinLink = useQuery({ queryKey: ["join-link", slug], queryFn: () => fetchJoinLink(token, slug) });
  const save = useMutation({
    mutationFn: (body: JoinLinkChange) => updateJoinLink(token, slug, body),
    onSuccess: (data) => {
      queryClient.setQueryData(["join-link", slug], data);
      void queryClient.invalidateQueries({ queryKey: ["admin-onboarding"] });
    },
  });

  if (joinLink.isPending) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>;
  if (joinLink.error) return <ErrorNotice>{localizeError(joinLink.error, uiT)}</ErrorNotice>;

  // A partial answer must not take the whole settings hub down: a missing link reads as off.
  const data = joinLink.data;

  return (
    <div className="space-y-4">
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("publicIntro")}</p>
      <JoinLinkCard t={t} slug={slug} role="member" enabled={data?.member?.enabled ?? false} save={save} />
      {/* ADR-255: the athlete link is off by default and few boxes need it, so it sits under «Προχωρημένα». */}
      <AdvancedDisclosure count={1} testId="join-link-advanced">
        <JoinLinkCard t={t} slug={slug} role="athlete" enabled={data?.athlete?.enabled ?? false} athleteKey={data?.athlete?.key} save={save} />
      </AdvancedDisclosure>
      <p className="text-xs" style={{ color: "var(--muted)" }}>{t("publicStaffNote")}</p>
      {save.error ? <ErrorNotice>{localizeError(save.error, uiT)}</ErrorNotice> : null}
    </div>
  );
}

function JoinLinkCard({
  t,
  slug,
  role,
  enabled,
  athleteKey,
  save,
}: {
  t: Translate;
  slug: string;
  role: ClientRole;
  enabled: boolean;
  athleteKey?: string | null;
  save: { mutate: (body: JoinLinkChange) => void; isPending: boolean };
}) {
  const [confirmRotate, setConfirmRotate] = useState(false);
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  const url = joinUrl(origin, { slug, athleteKey: role === "athlete" ? athleteKey : null });
  const title = t(`publicLinks.${role}.title`);
  const live = enabled && (role === "member" || Boolean(athleteKey));

  return (
    <section aria-label={title} data-join-link={role} className="space-y-3 rounded-xl p-3" style={{ border: "1px solid var(--border)" }}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</p>
          <p className="mt-0.5 text-xs leading-5" style={{ color: "var(--muted)" }}>{t(`publicLinks.${role}.hint`)}</p>
        </div>
        <button
          type="button"
          role="switch"
          aria-checked={enabled}
          aria-label={title}
          disabled={save.isPending}
          onClick={() => save.mutate({ role, enabled: !enabled })}
          className="relative h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-50"
          style={{ background: enabled ? "var(--success, var(--primary))" : "var(--border-strong, var(--border))" }}
        >
          <span className="absolute top-1 h-5 w-5 rounded-full bg-[var(--control-knob)] transition-all" style={{ insetInlineStart: enabled ? "1.5rem" : "0.25rem" }} />
        </button>
      </div>
      {live ? (
        <>
          <ShareBox t={t} url={url} message={t(`publicLinks.${role}.message`, { url })} subject={t("joinSubject")} />
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("publicWarning", { role: t(`roles.${role}`) })}</p>
          {role === "athlete" ? (
            confirmRotate ? (
              <div role="group" aria-label={t("rotateKey")} className="space-y-2 rounded-xl p-3" style={{ background: "var(--panel-muted, var(--bg))" }}>
                <p className="text-xs leading-5" style={{ color: "var(--text-soft)" }}>{t("rotateKeyHint")}</p>
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={save.isPending}
                    onClick={() => {
                      save.mutate({ role, rotate_key: true });
                      setConfirmRotate(false);
                    }}
                    className="rounded-lg px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                    style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                  >
                    {t("confirmRotate")}
                  </button>
                  <button
                    type="button"
                    onClick={() => setConfirmRotate(false)}
                    className="rounded-lg px-3 py-1.5 text-xs font-semibold"
                    style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    {t("keep")}
                  </button>
                </div>
              </div>
            ) : (
              <button type="button" onClick={() => setConfirmRotate(true)} className="text-xs font-semibold underline" style={{ color: "var(--primary)" }}>
                {t("rotateKey")}
              </button>
            )
          ) : null}
        </>
      ) : (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("publicOff")}</p>
      )}
    </section>
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
  const emailT = useTranslations("InviteEmail");
  const [resent, setResent] = useState<string | null>(null);
  // ADR-209: a resend re-issues the invitation; the old link stops working.
  const resend = useMutation({
    mutationFn: (id: string) => resendInvitation(token, slug, id),
    onSuccess: (invitation) => {
      setResent(invitation.email ?? null);
      void queryClient.invalidateQueries({ queryKey: ["pending-invitations", slug] });
    },
  });

  if (pending.isPending) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>;
  if (!pending.data?.length) return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("noPending")}</p>;

  return (
    <div className="space-y-2">
    {resend.error ? <ErrorNotice>{inviteErrorMessage(resend.error, emailT, uiT)}</ErrorNotice> : null}
    {resent && !resend.error ? <p role="status" className="text-xs" style={{ color: "var(--success, var(--primary))" }}>{emailT("resent", { email: resent })}</p> : null}
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
            {invitation.email ? (
              <p className="flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--text-soft)" }}>
                <span className="break-all">{invitation.email}</span>
                {invitation.delivery_status ? <DeliveryBadge status={invitation.delivery_status} /> : null}
              </p>
            ) : null}
            <p className="text-xs" style={{ color: "var(--muted)" }}>
              {t("expires", { date: formatClock(new Date(invitation.expires_at), locale, { dateStyle: "medium", timeStyle: "short" }) })}
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
            <div className="flex gap-2">
              {invitation.email ? (
                <button type="button" onClick={() => resend.mutate(invitation.id)} disabled={resend.isPending} className="rounded-lg px-3 py-1.5 text-xs font-semibold disabled:opacity-50" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                  {emailT("resend")}
                </button>
              ) : null}
              <button type="button" onClick={() => setConfirming(invitation.id)} className="rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                {t("revoke")}
              </button>
            </div>
          )}
        </li>
      ))}
    </ul>
    </div>
  );
}

type DeliveryStatus = NonNullable<PendingInvitation["delivery_status"]>;

/** ADR-209: where the invitation email is: queued, sent, failed, bounced or suppressed. */
function DeliveryBadge({ status }: { status: DeliveryStatus }) {
  const emailT = useTranslations("InviteEmail");
  const problem = status === "failed" || status === "bounced" || status === "suppressed";
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={problem
        ? { background: "color-mix(in srgb, var(--danger) 14%, transparent)", color: "var(--danger)" }
        : { background: "var(--panel-muted, var(--bg))", color: status === "sent" ? "var(--success, var(--primary))" : "var(--muted)" }}
    >
      {emailT(`status.${status}`)}
    </span>
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
