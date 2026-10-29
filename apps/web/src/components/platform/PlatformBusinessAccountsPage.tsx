"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  ACTIVATION_EMAIL_UNVERIFIED_CODE,
  PLATFORM_BUSINESS_KEY,
  activationEmailState,
  activationUrl,
  decideBusinessRequest,
  fetchBusinessQueue,
  issueActivationLink,
  revokeActivationLink,
  type ActivationRole,
  type BusinessAccountsQueue,
  type BusinessActivationLink,
  type BusinessRequest,
} from "@/api/business-accounts";
import { useSession } from "@/components/session-provider";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { BackLink } from "@/components/ui/BackLink";
import { withClock } from "@/lib/clock";

type DemoBusiness = BusinessAccountsQueue["demo_businesses"][number];

const inputClass = "min-h-10 w-full border-[1px] border-[var(--border)] bg-[var(--panel)] px-3 text-sm text-[var(--text)]";
const buttonClass = "min-h-10 px-4 text-sm font-semibold disabled:opacity-50";

/**
 * Platform console › Επαγγελματικοί λογαριασμοί (ADR-184): requests to turn
 * an account into a business or to activate one, and every business still
 * in demo mode with its activation link. ADR-205: a link goes only to an
 * account with a confirmed email («email not confirmed» badge otherwise),
 * and it is emailed to that account; the console shows how the email fared
 * and can send a new link, and the link can still be copied.
 */
export function PlatformBusinessAccountsPage() {
  const t = useTranslations("Business");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queue = useQuery({ queryKey: PLATFORM_BUSINESS_KEY, enabled: Boolean(token), queryFn: () => fetchBusinessQueue(token!) });
  const forbidden = queue.error instanceof ApiError && queue.error.status === 403;

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("console.back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("console.title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("console.subtitle")}</p>
      </header>
      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("console.forbidden")}</p> : null}
      {token && queue.data ? (
        <>
          <section className="mt-6 flex flex-col gap-3" aria-label={t("console.requests")}>
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("console.requests")}</h2>
            {queue.data.requests.length === 0 ? (
              <p className="text-sm text-[var(--text-soft)]">{t("console.noRequests")}</p>
            ) : (
              queue.data.requests.map((request) => <RequestCard key={request.id} token={token} request={request} />)
            )}
          </section>
          <section className="mt-8 flex flex-col gap-3" aria-label={t("console.demoBusinesses")}>
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("console.demoBusinesses")}</h2>
            {queue.data.demo_businesses.length === 0 ? (
              <p className="text-sm text-[var(--text-soft)]">{t("console.noDemoBusinesses")}</p>
            ) : (
              queue.data.demo_businesses.map((business) => (
                <DemoBusinessCard key={business.organization.id} token={token} business={business} />
              ))
            )}
          </section>
        </>
      ) : null}
    </main>
  );
}

function RoleSelect({ value, onChange }: { value: ActivationRole; onChange: (role: ActivationRole) => void }) {
  const t = useTranslations("Business");
  return (
    <Select className={inputClass} value={value} onValueChange={(role) => onChange(role as ActivationRole)} aria-label={t("console.role")}>
      <option value="owner">{t("role.owner")}</option>
      <option value="admin">{t("role.admin")}</option>
    </Select>
  );
}

function EmailNotConfirmed() {
  const t = useTranslations("VerifiedGates");
  return (
    <span
      className="inline-flex items-center border border-[var(--border)] bg-[var(--panel-muted)] px-2 py-0.5 text-xs font-semibold text-[var(--warning)]"
      title={t("vendor.emailNotConfirmedHint")}
    >
      {t("vendor.emailNotConfirmed")}
    </span>
  );
}

/** The console's error line: the unconfirmed-email refusal in its own words. */
function VendorError({ error }: { error: unknown }) {
  const t = useTranslations("VerifiedGates");
  const i18n = useUiTranslations();
  if (!error) return null;
  const unverified = error instanceof ApiError && error.payload.code === ACTIVATION_EMAIL_UNVERIFIED_CODE;
  return <ErrorNotice>{unverified ? t("vendor.emailNotConfirmedHint") : localizeError(error, i18n)}</ErrorNotice>;
}

function RequestCard({ token, request }: { token: string; request: BusinessRequest }) {
  const t = useTranslations("Business");
  const format = useFormatter();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");
  const [role, setRole] = useState<ActivationRole>("owner");
  const [issued, setIssued] = useState<BusinessActivationLink | null>(null);
  const decide = useMutation({
    mutationFn: (decision: "approve" | "decline") =>
      decideBusinessRequest(token, request.id, {
        decision,
        note: note.trim() || null,
        ...(request.kind === "activation" ? { role } : {}),
      }),
    onSuccess: (result) => {
      if (result.activation_link) setIssued(result.activation_link);
      void queryClient.invalidateQueries({ queryKey: PLATFORM_BUSINESS_KEY });
    },
  });
  const resend = useMutation({
    mutationFn: (link: BusinessActivationLink) =>
      issueActivationLink(token, link.organization_id, { role: link.role, user_id: link.user_id }),
    onSuccess: (link) => {
      setIssued(link);
      void queryClient.invalidateQueries({ queryKey: PLATFORM_BUSINESS_KEY });
    },
  });
  // ADR-205: an activation link needs the requester's confirmed email.
  const unconfirmed = request.kind === "activation" && request.requester_email_verified === false;

  return (
    <article className="flex flex-col gap-3 border border-[var(--border)] bg-[var(--panel)] p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <p className="text-base font-semibold text-[var(--text)]">{request.business_name}</p>
          <p className="text-xs text-[var(--text-soft)]">
            {t(`requestKind.${request.kind}`)} · {t(`kind.${request.business_kind}`)} · {request.requested_by ?? "—"} ·{" "}
            {format.dateTime(new Date(request.inserted_at), withClock(locale, { dateStyle: "medium", timeStyle: "short" }))}
          </p>
        </div>
        <span className="flex items-center gap-2 text-xs font-semibold text-[var(--text-soft)]">
          {request.requester_email_verified === false ? <EmailNotConfirmed /> : null}
          {t(`status.${request.status}`)}
        </span>
      </div>
      {[request.city, request.phone].filter(Boolean).length > 0 ? (
        <p className="text-sm text-[var(--text-soft)]">{[request.city, request.phone].filter(Boolean).join(" · ")}</p>
      ) : null}
      {request.message ? <p className="text-sm text-[var(--text)]">{request.message}</p> : null}
      {issued ? (
        <IssuedLink link={issued} resending={resend.isPending} onResend={() => resend.mutate(issued)} />
      ) : (
        <div className="grid gap-2 sm:grid-cols-[1fr_10rem_auto_auto] sm:items-end">
          <label className="text-xs font-semibold text-[var(--text-soft)]">
            {t("console.note")}
            <input className={`${inputClass} mt-1`} value={note} maxLength={500} onChange={(event) => setNote(event.target.value)} />
          </label>
          {request.kind === "activation" ? (
            <label className="text-xs font-semibold text-[var(--text-soft)]">
              {t("console.role")}
              <div className="mt-1"><RoleSelect value={role} onChange={setRole} /></div>
            </label>
          ) : (
            <span />
          )}
          <button
            type="button"
            className={`${buttonClass} bg-[var(--accent)] text-[var(--primary-contrast)]`}
            disabled={decide.isPending || unconfirmed}
            onClick={() => decide.mutate("approve")}
          >
            {request.kind === "activation" ? t("console.approveActivation") : t("console.approveConversion")}
          </button>
          <button
            type="button"
            className={`${buttonClass} border border-[var(--border)] text-[var(--text-soft)]`}
            disabled={decide.isPending}
            onClick={() => decide.mutate("decline")}
          >
            {t("console.decline")}
          </button>
        </div>
      )}
      <VendorError error={decide.error ?? resend.error} />
    </article>
  );
}

function DemoBusinessCard({ token, business }: { token: string; business: DemoBusiness }) {
  const t = useTranslations("Business");
  const format = useFormatter();
  const queryClient = useQueryClient();
  const [role, setRole] = useState<ActivationRole>("owner");
  const [userId, setUserId] = useState(business.owners[0]?.user_id ?? "");
  const [issued, setIssued] = useState<BusinessActivationLink | null>(null);
  const refresh = () => void queryClient.invalidateQueries({ queryKey: PLATFORM_BUSINESS_KEY });
  const issue = useMutation({
    mutationFn: (target: { role: ActivationRole; user_id: string | null }) =>
      issueActivationLink(token, business.organization.id, target),
    onSuccess: (link) => {
      setIssued(link);
      refresh();
    },
  });
  const revoke = useMutation({
    mutationFn: (id: string) => revokeActivationLink(token, id),
    onSuccess: () => {
      setIssued(null);
      refresh();
    },
  });
  const live = business.link && business.link.state === "live" ? business.link : null;
  const selected = business.owners.find((owner) => owner.user_id === userId);
  const unconfirmed = selected ? !selected.email_verified : false;

  return (
    <article className="flex flex-col gap-3 border border-[var(--border)] bg-[var(--panel)] p-4">
      <div>
        <p className="text-base font-semibold text-[var(--text)]">{business.organization.name}</p>
        <p className="text-xs text-[var(--text-soft)]">
          {t(`kind.${business.organization.provider_kind === "coach" ? "coach" : "gym"}`)} · /{business.organization.slug}
          {business.organization.demo_started_at
            ? ` · ${t("console.demoSince", { date: format.dateTime(new Date(business.organization.demo_started_at), { dateStyle: "medium" }) })}`
            : ""}
        </p>
      </div>
      {issued ? (
        <IssuedLink
          link={issued}
          resending={issue.isPending}
          onResend={() => {
            setRole(issued.role);
            setUserId(issued.user_id);
            issue.mutate({ role: issued.role, user_id: issued.user_id });
          }}
        />
      ) : null}
      {live && !issued ? (
        <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-[var(--text-soft)]">
          <span className="flex flex-col gap-1">
            <span>
              {t("console.liveLink", {
                name: live.nickname ?? "—",
                role: t(`role.${live.role}`),
                date: format.dateTime(new Date(live.expires_at), { dateStyle: "medium" }),
              })}
            </span>
            <EmailDelivery link={live} />
          </span>
          <button
            type="button"
            className={`${buttonClass} border border-[var(--border)] text-[var(--text-soft)]`}
            disabled={revoke.isPending}
            onClick={() => revoke.mutate(live.id)}
          >
            {t("console.revoke")}
          </button>
        </div>
      ) : null}
      {!issued ? (
        <div className="grid gap-2 sm:grid-cols-[1fr_10rem_auto] sm:items-end">
          <label className="text-xs font-semibold text-[var(--text-soft)]">
            {t("console.account")}
            <div className="mt-1">
              <Select className={inputClass} value={userId} onValueChange={setUserId} placeholder={t("console.pickAccount")}>
                {business.owners.map((owner) => (
                  <option key={owner.user_id} value={owner.user_id}>{owner.nickname ?? owner.user_id}</option>
                ))}
              </Select>
            </div>
            {unconfirmed ? <span className="mt-1 inline-flex"><EmailNotConfirmed /></span> : null}
          </label>
          <label className="text-xs font-semibold text-[var(--text-soft)]">
            {t("console.role")}
            <div className="mt-1"><RoleSelect value={role} onChange={setRole} /></div>
          </label>
          <button
            type="button"
            className={`${buttonClass} bg-[var(--accent)] text-[var(--primary-contrast)]`}
            disabled={issue.isPending || !userId || unconfirmed}
            onClick={() => issue.mutate({ role, user_id: userId || null })}
          >
            {live ? t("console.replaceLink") : t("console.issueLink")}
          </button>
        </div>
      ) : null}
      <VendorError error={issue.error ?? revoke.error} />
    </article>
  );
}

/** ADR-205: how the link's email to the account fared. */
function EmailDelivery({ link }: { link: BusinessActivationLink }) {
  const t = useTranslations("VerifiedGates");
  const state = activationEmailState(link.email_delivery);
  if (!state) return null;
  const color = state === "sent" ? "var(--success)" : state === "pending" ? "var(--text-soft)" : "var(--danger)";
  return (
    <span role="status" className="text-xs font-semibold" style={{ color }}>
      {t(`vendor.email.${state}`)}
    </span>
  );
}

function IssuedLink({
  link,
  onResend,
  resending,
}: {
  link: BusinessActivationLink;
  onResend: () => void;
  resending: boolean;
}) {
  const t = useTranslations("Business");
  const tv = useTranslations("VerifiedGates");
  const [copied, setCopied] = useState(false);
  const url = activationUrl(link.path);

  return (
    <div className="flex flex-col gap-2 border border-[var(--border)] bg-[var(--panel-muted)] p-3">
      <p className="text-xs font-semibold text-[var(--text-soft)]">
        {t("console.issued", { name: link.nickname ?? "—", role: t(`role.${link.role}`) })}
      </p>
      <div className="flex gap-2">
        <input readOnly value={url} className={inputClass} onFocus={(event) => event.currentTarget.select()} aria-label={t("console.linkLabel")} />
        <button
          type="button"
          className={`${buttonClass} border border-[var(--border)] text-[var(--text)]`}
          onClick={() => {
            void navigator.clipboard?.writeText(url).then(() => setCopied(true));
          }}
        >
          {copied ? t("console.copied") : t("console.copy")}
        </button>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <EmailDelivery link={link} />
        <button
          type="button"
          className={`${buttonClass} border border-[var(--border)] text-[var(--text-soft)]`}
          disabled={resending}
          onClick={onResend}
        >
          {tv("vendor.resend")}
        </button>
      </div>
      <p className="text-xs text-[var(--dim)]">{t("console.linkHint")}</p>
    </div>
  );
}
