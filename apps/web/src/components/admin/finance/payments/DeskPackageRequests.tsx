"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import type { ReceivedPayment } from "@/api/finance";
import {
  COLLECT_METHODS,
  collectPackageRequest,
  deskPackageRequestsKey,
  fetchDeskPackageRequests,
  type CollectPaymentMethod,
  type DeskPackageRequest,
} from "@/api/package-requests";
import { holdDateLabel } from "@/components/payments/desk-payment";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { ReceivedView } from "./ReceivePaymentDialog";

/*
 * ADR-291 (mockup «Υποδοχή · Εκκρεμότητες»): «Περιμένουν πληρωμή», the
 * packages people asked for in the app. Each row names the person and opens
 * their account; «Είσπραξη» records the money and starts the package today.
 */

export function useDeskPackageRequests(locationIds: string | undefined, enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  return useQuery({
    queryKey: deskPackageRequestsKey(slug ?? "none", locationIds ?? null),
    enabled: Boolean(token && slug && enabled),
    queryFn: () => fetchDeskPackageRequests(token!, slug!, locationIds ?? null),
    retry: false,
  });
}

/** The person a row is for, as a link to their account. */
export function PersonLink({ userId, name, handle }: { userId: string | null | undefined; name: string; handle?: string | null }) {
  const slug = useOrganizationSlug();
  if (!userId) return <span className="font-semibold" style={{ color: "var(--text)" }}>{name}</span>;
  return (
    <Link
      href={adminHref(`/admin/users/${encodeURIComponent(userId)}`, slug)}
      className="font-semibold underline-offset-2 hover:underline"
      style={{ color: "var(--text)" }}
      data-testid="queue-person-link"
    >
      {name}
      {handle ? <span className="font-normal" style={{ color: "var(--muted)" }}> @{handle}</span> : null}
    </Link>
  );
}

export function DeskPackageRequestRows({ rows, empty }: { rows: DeskPackageRequest[]; empty?: ReactNode }) {
  const t = useTranslations("DeskPay");
  const locale = useUiLocale();
  const [collecting, setCollecting] = useState<DeskPackageRequest | null>(null);

  return (
    <>
      {rows.length === 0 ? empty : null}
      {rows.map((row, index) => {
        const amount = new Intl.NumberFormat(locale, { style: "currency", currency: row.currency }).format(row.price_cents / 100);
        const name = row.person?.display_name || row.person?.handle || t("someone");
        return (
          <div
            key={row.id}
            className="flex flex-wrap items-center justify-between gap-x-5 gap-y-3 px-6 py-4 text-sm"
            style={{ borderBottom: index === rows.length - 1 ? "none" : "1px solid var(--border)" }}
            data-testid={`desk-request-${row.id}`}
          >
            <span className="flex min-w-0 flex-[1_1_16rem] items-center gap-3">
              <Avatar url={row.person?.avatar_url ?? null} name={name} />
              <span className="flex min-w-0 flex-col">
                <PersonLink userId={row.user_id} name={name} handle={row.person?.handle} />
                <span className="text-xs" style={{ color: "var(--muted)" }}>
                  {t("askedOn", { date: new Date(row.requested_at).toLocaleDateString(locale, { day: "numeric", month: "short" }) })}
                </span>
              </span>
            </span>
            <span className="flex min-w-0 flex-[1_1_12rem] flex-col">
              <span className="font-semibold" style={{ color: "var(--text)" }}>{row.package_name} · {amount}</span>
              <span className="text-xs" style={{ color: "var(--muted)" }}>
                {t("removedIn", { days: row.days_left, date: holdDateLabel(locale, row.hold_until) })}
              </span>
            </span>
            <button
              type="button"
              onClick={() => setCollecting(row)}
              className="min-h-11 rounded-2xl px-4 text-sm font-bold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              data-testid={`desk-collect-${row.id}`}
            >
              {t("collect", { amount })}
            </button>
          </div>
        );
      })}
      {collecting ? <CollectDialog request={collecting} onClose={() => setCollecting(null)} /> : null}
    </>
  );
}

function Avatar({ url, name }: { url: string | null; name: string }) {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={url} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
  ) : (
    <span aria-hidden="true" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-xs font-extrabold" style={{ background: "var(--panel-muted)", color: "var(--text)" }}>
      {initials}
    </span>
  );
}

/** «Είσπραξη»: how the money was handed over, then the box's receipt or invoice. */
function CollectDialog({ request, onClose }: { request: DeskPackageRequest; onClose: () => void }) {
  const t = useTranslations("DeskPay");
  const tReceive = useTranslations("ReceivePayment");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [method, setMethod] = useState<CollectPaymentMethod>("cash");
  const [received, setReceived] = useState<ReceivedPayment | null>(null);
  const name = request.person?.display_name || request.person?.handle || t("someone");
  const money = (cents: number, currency = request.currency) =>
    new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100);

  const mutation = useMutation({
    mutationFn: () => collectPackageRequest(tokens!.access_token, slug!, request.id, { payment_method: method }),
    onSuccess: async (result) => {
      setReceived(result.received as unknown as ReceivedPayment);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "users", request.user_id, "finance"] }),
      ]);
    },
  });

  if (received) return <ReceivedView received={received} nickname={name} money={money} onClose={onClose} />;

  return (
    <Dialog
      onClose={onClose}
      title={t("collectTitle")}
      description={name}
      size="sm"
      variant="center"
      dismissible={!mutation.isPending}
      error={mutation.isError ? localizeError(mutation.error, i18n) : undefined}
      testId="desk-collect"
      footer={
        <div className="flex w-full gap-2">
          <DialogButton onClick={onClose}>{t("close")}</DialogButton>
          <DialogButton tone="primary" disabled={mutation.isPending} onClick={() => mutation.mutate()} testId="desk-collect-confirm">
            {t("collect", { amount: money(request.price_cents) })}
          </DialogButton>
        </div>
      }
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text)" }}>
          <b>{request.package_name}</b> · {money(request.price_cents)}
        </p>
        <div role="radiogroup" aria-label={tReceive("method")} className="flex flex-wrap gap-2">
          {COLLECT_METHODS.map((option) => {
            const on = option === method;
            return (
              <button
                key={option}
                type="button"
                role="radio"
                aria-checked={on}
                onClick={() => setMethod(option)}
                className="min-h-11 rounded-full px-3.5 text-sm font-semibold"
                style={
                  on
                    ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
                    : { background: "transparent", color: "var(--text-soft)", border: "1px solid var(--border)" }
                }
              >
                {tReceive(`method_${option}`)}
              </button>
            );
          })}
        </div>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("collectHint")}</p>
      </div>
    </Dialog>
  );
}
