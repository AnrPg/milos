"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import {
  connectOutcome,
  connectsWithOneButton,
  disconnectPaymentAccount,
  dismissPackagesNotice,
  fetchPaymentAccount,
  isConnected,
  pickableProviders,
  providerName,
  PURPOSE_KEYS,
  DEFAULT_OPTIONS,
  DEFAULT_PROVIDER,
  savePaymentOptions,
  startPaymentConnect,
  type ConnectOutcome,
  type PaymentAccountStatus,
  type PaymentOptionsUpdate,
  type PaymentProvider,
  type PaymentPurposes,
  type OnlineSalesSummary,
} from "@/api/online-payments";
import { fetchAdminSettings, updateAdminSettings } from "@/api/settings";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import Link from "next/link";
import { FRESHNESS } from "@/lib/query-policy";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

import { PaymentKeysForm } from "./PaymentKeysForm";
import { paymentErrorText } from "./payment-errors";

export const PAYMENT_ACCOUNT_KEY = ["admin", "payments", "account"] as const;
const SETTINGS_KEY = ["admin", "settings"] as const;

/** Grace days offered in «Περίοδος χάριτος» (Finance's `subscription_grace_days`, 0–60). */
const GRACE_CHOICES = [0, 1, 2, 3, 5, 7, 10, 14, 21, 30];

type Sheet = { provider: PaymentProvider; mode: "redirect" | "keys" } | null;

/**
 * Ρυθμίσεις › Πληρωμές (mockup s3, option B; ADR-246/260/261). Before the
 * business connects, one card offers «Σύνδεση με Viva» (or Stripe); a
 * provider that connects with one button sends the owner to its page, the
 * others ask for API keys. Once connected: the provider, one sentence on
 * what box members pay online with «Αλλαγή» for the five switches, and
 * «Προχωρημένα» with the failure policy, the keys and «Αποσύνδεση».
 */
export function OnlinePaymentsSettings({ token }: { token: string }) {
  const t = useTranslations("OnlinePayments");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  const [sheet, setSheet] = useState<Sheet>(null);
  const [outcome, setOutcome] = useState<ConnectOutcome | null>(null);

  const accountQuery = useQuery({
    queryKey: PAYMENT_ACCOUNT_KEY,
    queryFn: () => fetchPaymentAccount(token),
    staleTime: FRESHNESS.reference,
  });

  // ADR-261: the provider sends the owner back with `connect=ok|<code>`;
  // say what happened once and take the code out of the address.
  const connectCode = searchParams.get("connect");
  const tab = searchParams.get("tab");
  useEffect(() => {
    if (tab === "payments") document.getElementById("payments")?.scrollIntoView({ block: "start" });
    if (!connectCode) return;
    const result = connectOutcome(connectCode);
    queueMicrotask(() => setOutcome(result));
    void queryClient.invalidateQueries({ queryKey: PAYMENT_ACCOUNT_KEY });
    const params = new URLSearchParams(searchParams.toString());
    params.delete("connect");
    const query = params.toString();
    router.replace(`${pathname}${query ? `?${query}` : ""}`, { scroll: false });
  }, [connectCode, tab, pathname, queryClient, router, searchParams]);

  const connectMutation = useMutation({
    mutationFn: (provider: PaymentProvider) => startPaymentConnect(token, provider, "live"),
    onSuccess: ({ url }) => window.location.assign(url),
    onError: () => setSheet(null),
  });

  const status = accountQuery.data;

  if (accountQuery.isLoading) {
    return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  }
  if (accountQuery.isError || !status) {
    return <ErrorNotice>{paymentErrorText(accountQuery.error, t, ui)}</ErrorNotice>;
  }

  const providers = pickableProviders(status);
  const choose = (provider: PaymentProvider) => {
    setOutcome(null);
    if (connectsWithOneButton(status, provider, "live")) {
      setSheet({ provider, mode: "redirect" });
      connectMutation.mutate(provider);
    } else {
      setSheet({ provider, mode: "keys" });
    }
  };

  const outcomeNotice =
    outcome && outcome !== "ok" ? (
      <ErrorNotice>{t(`connect_${outcome}`)}</ErrorNotice>
    ) : null;

  if (!isConnected(status)) {
    return (
      <div className="space-y-4" data-testid="online-payments">
        {outcomeNotice}
        {sheet?.mode === "redirect" ? (
          <RedirectCard provider={sheet.provider} />
        ) : sheet?.mode === "keys" ? (
          <Card>
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="font-semibold" style={{ color: "var(--text)" }}>{t("keysFor", { provider: providerName(sheet.provider) })}</p>
                <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{t("keysForHint", { provider: providerName(sheet.provider) })}</p>
              </div>
              <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setSheet(null)}>
                {t("back")}
              </button>
            </div>
            <PaymentKeysForm token={token} status={status} provider={sheet.provider} lockProvider onSaved={() => setSheet(null)} />
          </Card>
        ) : (
          <OfferCard providers={providers} onChoose={choose} />
        )}
        {connectMutation.isError ? <ErrorNotice>{paymentErrorText(connectMutation.error, t, ui)}</ErrorNotice> : null}
        <Advanced hint={t("advancedHintKeys")}>
          <PaymentKeysForm token={token} status={status} provider={providers[0] ?? DEFAULT_PROVIDER} />
        </Advanced>
      </div>
    );
  }

  return (
    <ConnectedView
      token={token}
      status={status}
      justConnected={outcome === "ok"}
      notice={outcomeNotice}
    />
  );
}

function Card({ children, dashed = false }: { children: ReactNode; dashed?: boolean }) {
  return (
    <div
      className="space-y-3 rounded-[1.5rem] p-5"
      style={{ background: "var(--panel-muted)", border: `1px ${dashed ? "dashed" : "solid"} var(--border)` }}
    >
      {children}
    </div>
  );
}

function ProviderMark({ provider }: { provider: string }) {
  return (
    <span
      aria-hidden="true"
      className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-sm font-bold"
      style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}
    >
      {providerName(provider).slice(0, 1)}
    </span>
  );
}

function CardIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="h-6 w-6 shrink-0" fill="none" stroke="currentColor" strokeWidth="1.6" style={{ color: "var(--primary)" }}>
      <rect x="2.5" y="5" width="19" height="14" rx="2.5" />
      <path d="M2.5 9.5h19M6.5 15h4" strokeLinecap="round" />
    </svg>
  );
}

function OfferCard({ providers, onChoose }: { providers: PaymentProvider[]; onChoose: (provider: PaymentProvider) => void }) {
  const t = useTranslations("OnlinePayments");
  const [first, ...others] = providers;
  return (
    <Card>
      <div className="flex items-start gap-3">
        <CardIcon />
        <div>
          <p className="font-semibold" style={{ color: "var(--text)" }}>{t("offerTitle")}</p>
          <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{t("offerHint")}</p>
        </div>
      </div>
      {first ? (
        <div className="flex flex-wrap items-center gap-3">
          <button
            type="button"
            className="rounded-full px-5 py-2.5 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            onClick={() => onChoose(first)}
          >
            {t("connectWith", { provider: providerName(first) })}
          </button>
          {others.length > 0 ? (
            <span className="text-sm" style={{ color: "var(--dim)" }}>
              {t("or")}{" "}
              {others.map((provider, index) => (
                <span key={provider}>
                  {index > 0 ? ", " : null}
                  <button type="button" className="font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => onChoose(provider)}>
                    {providerName(provider)}
                  </button>
                </span>
              ))}
            </span>
          ) : null}
        </div>
      ) : null}
    </Card>
  );
}

function RedirectCard({ provider }: { provider: PaymentProvider }) {
  const t = useTranslations("OnlinePayments");
  return (
    <Card dashed>
      <div className="flex flex-col items-center gap-2 py-2 text-center" role="status">
        <p className="font-semibold" style={{ color: "var(--text)" }}>{t("redirectTitle", { provider: providerName(provider) })}</p>
        <p className="max-w-[46ch] text-sm" style={{ color: "var(--dim)" }}>{t("redirectHint")}</p>
      </div>
    </Card>
  );
}

function Advanced({ hint, children }: { hint: string; children: ReactNode }) {
  const t = useTranslations("OnlinePayments");
  const [open, setOpen] = useState(false);
  return (
    <div className="rounded-[1.5rem]" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <button type="button" aria-expanded={open} className="flex w-full items-center justify-between gap-3 p-5 text-start" onClick={() => setOpen((value) => !value)}>
        <span>
          <span className="block font-semibold" style={{ color: "var(--text)" }}>{t("advanced")}</span>
          <span className="block text-sm" style={{ color: "var(--dim)" }}>{hint}</span>
        </span>
        <span aria-hidden="true" className="text-sm" style={{ color: "var(--dim)" }}>{open ? "▴" : "▾"}</span>
      </button>
      {open ? <div className="space-y-1 border-t px-5 pb-5 pt-2" style={{ borderColor: "var(--border)" }}>{children}</div> : null}
    </div>
  );
}

/** One setting: name, one-line explanation, its control at the end. */
function SettingRow({ title, hint, children }: { title: string; hint: string; children?: ReactNode }) {
  return (
    <div className="flex items-center gap-3 border-b py-3 last:border-b-0" style={{ borderColor: "var(--border)" }}>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</p>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</p>
      </div>
      {children}
    </div>
  );
}

/** «Τα μέλη box πληρώνουν online …»: the switched-on purposes as one sentence. */
export function onlineSentence(purposes: PaymentPurposes, t: (key: string, values?: Record<string, string>) => string, locale: string): string {
  const shown = PURPOSE_KEYS.filter((key) => key !== "autopay" && purposes[key]).map((key) => t(`purpose_${key}_inline`));
  let first: string;
  if (shown.length === 0) {
    first = t("sentenceNothing");
  } else {
    let list: string;
    try {
      list = new Intl.ListFormat(locale, { type: "conjunction" }).format(shown);
    } catch {
      list = shown.join(", ");
    }
    first = t("sentence", { list });
  }
  return `${first} ${purposes.autopay ? t("autoOn") : t("autoOff")}`;
}

function ConnectedView({
  token,
  status,
  justConnected,
  notice,
}: {
  token: string;
  status: PaymentAccountStatus;
  justConnected: boolean;
  notice: ReactNode;
}) {
  const t = useTranslations("OnlinePayments");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const account = status.account!;
  const provider = providerName(account.provider);
  const options = account.options ?? DEFAULT_OPTIONS;
  const [editing, setEditing] = useState(false);
  const [confirming, setConfirming] = useState(false);

  const optionsMutation = useMutation({
    mutationFn: (update: PaymentOptionsUpdate) => savePaymentOptions(token, update),
    onSuccess: (next) => queryClient.setQueryData(PAYMENT_ACCOUNT_KEY, next),
  });

  const settingsQuery = useQuery({ queryKey: SETTINGS_KEY, queryFn: () => fetchAdminSettings(token) });
  const graceMutation = useMutation({
    mutationFn: (days: number) => updateAdminSettings(token, { finance: { subscription_grace_days: days } }),
    onSuccess: (data) => queryClient.setQueryData(SETTINGS_KEY, data),
  });
  const graceDays = settingsQuery.data?.finance?.subscription_grace_days;
  const graceChoices = graceDays === undefined || GRACE_CHOICES.includes(graceDays) ? GRACE_CHOICES : [...GRACE_CHOICES, graceDays].sort((a, b) => a - b);

  const disconnectMutation = useMutation({
    mutationFn: () => disconnectPaymentAccount(token),
    onSuccess: (next) => {
      queryClient.setQueryData(PAYMENT_ACCOUNT_KEY, next);
      setConfirming(false);
    },
  });

  return (
    <div className="space-y-4" data-testid="online-payments">
      {justConnected ? (
        <p
          role="status"
          className="rounded-2xl px-4 py-3 text-sm font-medium"
          style={{ background: "color-mix(in srgb, var(--success) 14%, transparent)", border: "1px solid var(--success)", color: "var(--text)" }}
        >
          {t("connect_ok")}
        </p>
      ) : null}
      {notice}
      {account.packages_notice ? <PackagesOpenedNotice token={token} count={account.packages_notice.count} /> : null}

      <Card>
        <div className="flex items-center gap-3">
          <ProviderMark provider={account.provider} />
          <div className="min-w-0 flex-1">
            <p className="font-semibold" style={{ color: "var(--text)" }}>{t("connected", { provider })}</p>
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              {t("connectedHint", { provider })}
              {account.environment === "test" ? ` · ${t("testMode")}` : ""}
            </p>
            <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
              {t("methodsHint", { provider })}
            </p>
          </div>
          <span className="rounded-full px-3 py-1 text-xs font-semibold" style={SPARK_ACTIVE_STYLE}>
            ✓ {t("statusActive")}
          </span>
        </div>
      </Card>

      {status.online_sales && status.online_sales.packages > 0 ? <SoldOnlineNudge summary={status.online_sales} /> : null}

      <Card>
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("whatTitle")}</p>
        {editing ? (
          <div>
            {PURPOSE_KEYS.map((key) => (
              <SettingRow key={key} title={t(`purpose_${key}`)} hint={t(`purpose_${key}_hint`)}>
                <Toggle
                  label={t(`purpose_${key}`)}
                  checked={options.purposes[key]}
                  disabled={optionsMutation.isPending}
                  onChange={(value) => optionsMutation.mutate({ purposes: { [key]: value } })}
                />
              </SettingRow>
            ))}
            <div className="flex justify-end pt-3">
              <button
                type="button"
                className="rounded-full px-5 py-2 text-sm font-semibold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                onClick={() => setEditing(false)}
              >
                {t("done")}
              </button>
            </div>
          </div>
        ) : (
          <div className="flex items-start gap-3">
            <p className="flex-1 text-sm leading-6" style={{ color: "var(--text)" }} data-testid="online-sentence">
              {onlineSentence(options.purposes, t, locale)}
            </p>
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setEditing(true)}>
              {t("change")}
            </button>
          </div>
        )}
        {optionsMutation.isError ? <ErrorNotice variant="field">{paymentErrorText(optionsMutation.error, t, ui)}</ErrorNotice> : null}
      </Card>

      <Advanced hint={t("advancedHint")}>
        <SettingRow title={t("retries")} hint={t("retriesHint")}>
          <span className="rounded-xl px-3 py-1.5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
            3
          </span>
        </SettingRow>
        <SettingRow title={t("notifyMember")} hint={t("notifyMemberHint")}>
          <Toggle
            label={t("notifyMember")}
            checked={options.notify_member}
            disabled={optionsMutation.isPending}
            onChange={(value) => optionsMutation.mutate({ notify_member: value })}
          />
        </SettingRow>
        <SettingRow title={t("grace")} hint={t("graceHint")}>
          {graceDays === undefined ? null : (
            <Select
              aria-label={t("grace")}
              value={String(graceDays)}
              disabled={graceMutation.isPending}
              onValueChange={(value: string) => graceMutation.mutate(Number(value))}
              className="min-w-[7.5rem]"
            >
              {graceChoices.map((days) => (
                <option key={days} value={String(days)}>
                  {t("graceDays", { count: days })}
                </option>
              ))}
            </Select>
          )}
        </SettingRow>
        {graceMutation.isError ? <ErrorNotice variant="field">{paymentErrorText(graceMutation.error, t, ui)}</ErrorNotice> : null}
        <SettingRow title={t("notifyStaff")} hint={t("notifyStaffHint")}>
          <Toggle
            label={t("notifyStaff")}
            checked={options.notify_staff}
            disabled={optionsMutation.isPending}
            onChange={(value) => optionsMutation.mutate({ notify_staff: value })}
          />
        </SettingRow>

        <div className="border-b py-3" style={{ borderColor: "var(--border)" }}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("keysTitle")}</p>
          <p className="mb-3 text-xs leading-5" style={{ color: "var(--dim)" }}>{t("keysHint")}</p>
          <PaymentKeysForm token={token} status={status} provider={account.provider} />
        </div>

        <SettingRow title={t("disconnectTitle", { provider })} hint={t("disconnectHint")}>
          <button
            type="button"
            className="rounded-full px-4 py-1.5 text-sm font-semibold"
            style={{ background: "var(--danger-surface)", border: "1px solid var(--danger-border)", color: "var(--danger-strong)" }}
            onClick={() => setConfirming(true)}
          >
            {t("disconnect")}
          </button>
        </SettingRow>
      </Advanced>

      {confirming ? (
        <Dialog
          variant="center"
          size="sm"
          title={t("disconnectConfirmTitle", { provider })}
          onClose={() => setConfirming(false)}
          dismissible={!disconnectMutation.isPending}
          error={disconnectMutation.isError ? paymentErrorText(disconnectMutation.error, t, ui) : undefined}
          footer={
            <div className="flex justify-end gap-2">
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={() => setConfirming(false)}>
                {t("cancel")}
              </button>
              <button
                type="button"
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                disabled={disconnectMutation.isPending}
                onClick={() => disconnectMutation.mutate()}
              >
                {t("disconnect")}
              </button>
            </div>
          }
        >
          <p className="text-sm" style={{ color: "var(--text)" }}>{t("disconnectConfirmBody")}</p>
        </Dialog>
      ) : null}
    </div>
  );
}

const PACKAGES_HREF = "/admin/finance?tab=packages";

/** ADR-271: «Τα N πακέτα σου πωλούνται τώρα online · Αλλαγή», once after the first connection. */
function PackagesOpenedNotice({ token, count }: { token: string; count: number }) {
  const t = useTranslations("SoldOnline");
  const tp = useTranslations("OnlinePayments");
  const ui = useUiTranslations();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const dismiss = useMutation({
    mutationFn: () => dismissPackagesNotice(token),
    onSuccess: (next) => queryClient.setQueryData(PAYMENT_ACCOUNT_KEY, next),
  });
  return (
    <div
      role="status"
      className="flex flex-wrap items-center gap-3 rounded-2xl px-4 py-3 text-sm"
      style={{ background: "color-mix(in srgb, var(--success) 14%, transparent)", border: "1px solid var(--success)", color: "var(--text)" }}
      data-testid="packages-opened-notice"
    >
      <span className="min-w-0 flex-1 font-medium">{t("noticeOpened", { count })}</span>
      <Link href={adminHref(PACKAGES_HREF, slug)} className="font-semibold" style={{ color: "var(--primary)" }}>
        {t("noticeChange")}
      </Link>
      <button
        type="button"
        aria-label={t("noticeClose")}
        className="rounded-full px-2 text-base leading-none"
        style={{ color: "var(--dim)" }}
        disabled={dismiss.isPending}
        onClick={() => dismiss.mutate()}
      >
        ×
      </button>
      {dismiss.isError ? (
        <div className="w-full">
          <ErrorNotice variant="field">{paymentErrorText(dismiss.error, tp, ui)}</ErrorNotice>
        </div>
      ) : null}
    </div>
  );
}

/** «Πωλούνται online: N από M πακέτα συνδρομής» with a link to the list; nothing is edited here (ADR-271). */
function SoldOnlineNudge({ summary }: { summary: OnlineSalesSummary }) {
  const t = useTranslations("SoldOnline");
  const slug = useOrganizationSlug();
  const none = summary.sold_online === 0;
  const hint = none ? t("payNoneHint") : summary.sold_online >= summary.packages ? t("payAll") : t("payCountHint");
  return (
    <div
      className="flex flex-wrap items-center gap-3 rounded-[1.5rem] p-5"
      style={{
        background: "var(--panel-muted)",
        border: none ? "1px solid color-mix(in srgb, var(--warning) 55%, transparent)" : "1px solid var(--border)",
      }}
      data-testid="sold-online-nudge"
    >
      <div className="min-w-0 flex-1">
        <p className="font-semibold" style={{ color: "var(--text)" }}>
          {none ? t("payNone") : t("payCount", { count: summary.sold_online, total: summary.packages })}
        </p>
        <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{hint}</p>
      </div>
      <Link href={adminHref(PACKAGES_HREF, slug)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
        {t("packagesLink")} ›
      </Link>
    </div>
  );
}
