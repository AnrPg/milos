"use client";







import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { SemanticLabel } from "@/components/semantic-label";
import Link from "next/link";
import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  applyCreditToPayment,
  applyCreditToInvoice,
  assignFinancePackage,
  createFinanceInvoice,
  createManualCredit,
  fetchFinanceMember,
  fetchFinancePackages,
  fetchPromotionCampaigns,
  fetchPromotionCodes,
  generateRenewalInvoice,
  getInvoiceDownloadUrl,
  getInvoiceUploadUrl,
  issueFinanceInvoice,
  recordFinancePayment,
  redeemPromotion,
  reverseCreditLedgerEntry,
  reverseFinancePayment,
  updateFinanceMember,
  updateFinanceInvoice,
  voidFinanceInvoice,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function dateField(record: FinanceRecord | null | undefined, key: string) {
  return field(record, key).slice(0, 10);
}

function money(uiLocale: string, cents: unknown) {
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(Number(cents ?? 0) / 100);
}

function euroInputValue(cents: unknown) {
  return (Number(cents ?? 0) / 100).toFixed(2);
}

export function AdminFinanceMemberProfile({ userId }: { userId: string }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const token = tokens?.access_token;
  const [membershipOverrides, setMembershipOverrides] = useState<
    Partial<{
      user_type_snapshot: string;
      status: string;
      signup_source: string;
      starts_on: string;
      expires_on: string;
      notes: string;
    }>
  >({});
  const [assignmentForm, setAssignmentForm] = useState({ membership_package_id: "", starts_on: "", ends_on: "" });
  const [paymentForm, setPaymentForm] = useState({
    amount: "0",
    payment_method: "cash",
    payment_status: "paid",
    paid_on: "",
    finance_invoice_id: "",
    notes: "",
  });
  const [invoiceForm, setInvoiceForm] = useState({
    amount: "0",
    description: "",
    due_date: "",
    service_period_start: "",
    service_period_end: "",
    membership_package_subscription_id: "",
  });
  const [renewalForm, setRenewalForm] = useState({
    membership_package_subscription_id: "",
    service_period_start: "",
    service_period_end: "",
    due_date: "",
  });
  const [redemptionForm, setRedemptionForm] = useState({ promotion_code: "", promotion_campaign_id: "" });
  const [creditForm, setCreditForm] = useState({ amount: "0", description: "" });
  const [applyCreditForm, setApplyCreditForm] = useState({ payment_id: "", amount: "0", description: "" });
  const [applyInvoiceCreditForm, setApplyInvoiceCreditForm] = useState({ invoice_id: "", amount: "0", description: "" });
  const [paymentReversalForm, setPaymentReversalForm] = useState({ payment_id: "", amount: "0", reason: "" });
  const [creditReversalForm, setCreditReversalForm] = useState({ credit_ledger_entry_id: "", amount: "0", reason: "" });

  const enabled = Boolean(token);

  const memberQuery = useQuery({
    queryKey: ["admin", "finance", "member", userId],
    enabled,
    queryFn: async () => fetchFinanceMember(token!, userId),
  });

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled,
    queryFn: async () => fetchFinancePackages(token!),
  });

  const campaignsQuery = useQuery({
    queryKey: ["admin", "finance", "promotions"],
    enabled,
    queryFn: async () => fetchPromotionCampaigns(token!),
  });

  const selectedCampaignId = redemptionForm.promotion_campaign_id;
  const codesQuery = useQuery({
    queryKey: ["admin", "finance", "promotions", selectedCampaignId, "codes"],
    enabled: enabled && Boolean(selectedCampaignId),
    queryFn: async () => fetchPromotionCodes(token!, selectedCampaignId),
  });

  const membership = memberQuery.data?.membership ?? null;
  const packages = packagesQuery.data?.packages ?? [];
  const campaigns = campaignsQuery.data?.promotion_campaigns ?? [];
  const codes = codesQuery.data?.promotion_codes ?? [];
  const payments = memberQuery.data?.payments ?? [];
  const creditablePayments = payments.filter((payment) =>
    ["paid", "pending"].includes(field(payment, "payment_status")),
  );
  const reversiblePayments = payments.filter(
    (payment) => ["paid", "waived"].includes(field(payment, "payment_status")) && Number(payment.net_amount_cents ?? 0) > 0,
  );
  const invoices = memberQuery.data?.invoices ?? [];
  const payableInvoices = invoices.filter((invoice) => {
    const status = field(invoice, "status");
    const balanceDue = typeof invoice.balance_due_cents === "number" ? invoice.balance_due_cents : 0;
    return ["issued", "partially_paid", "overdue"].includes(status) && balanceDue > 0;
  });
  const creditLedgerEntries = memberQuery.data?.credit_ledger_entries ?? [];
  const reversibleCreditEntries = creditLedgerEntries.filter(
    (entry) =>
      ["application", "invoice_offset"].includes(field(entry, "entry_type")) &&
      Number(entry.remaining_reversible_cents ?? 0) > 0,
  );
  const packageSubscriptions = memberQuery.data?.package_subscriptions ?? [];
  const activePackages = packages.filter((item) => item.active !== false);
  const today = new Date().toISOString().slice(0, 10);
  const renewableSubscriptions = packageSubscriptions.filter((subscription) => {
    const startsOn = field(subscription, "starts_on");
    const endsOn = field(subscription, "ends_on");
    return field(subscription, "status") === "active" && (!startsOn || startsOn <= today) && (!endsOn || endsOn >= today);
  });
  const selectedRenewalSubscription = renewableSubscriptions.find(
    (subscription) => field(subscription, "id") === renewalForm.membership_package_subscription_id,
  );
  const customRenewal = field(selectedRenewalSubscription, "billing_period_snapshot") === "custom";
  const creditBalance = memberQuery.data?.credit_balance ?? 0;
  const entitlement = memberQuery.data?.entitlement;
  const membershipForm = {
    user_type_snapshot: membershipOverrides.user_type_snapshot ?? field(membership, "user_type_snapshot", "member"),
    status: membershipOverrides.status ?? field(membership, "status", "active"),
    signup_source: membershipOverrides.signup_source ?? field(membership, "signup_source", "admin_created"),
    starts_on: membershipOverrides.starts_on ?? dateField(membership, "starts_on"),
    expires_on: membershipOverrides.expires_on ?? dateField(membership, "expires_on"),
    notes: membershipOverrides.notes ?? field(membership, "notes"),
  };

  const invalidateMember = async () => {
    await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    await queryClient.invalidateQueries({ queryKey: ["admin", "search"] });
  };

  const updateMembershipMutation = useMutation({
    mutationFn: async () =>
      updateFinanceMember(token!, userId, {
        user_type_snapshot: membershipForm.user_type_snapshot,
        status: membershipForm.status,
        signup_source: membershipForm.signup_source,
        starts_on: membershipForm.starts_on || null,
        expires_on: membershipForm.expires_on || null,
        notes: membershipForm.notes,
      }),
    onSuccess: invalidateMember,
  });

  const assignPackageMutation = useMutation({
    mutationFn: async () =>
      assignFinancePackage(token!, userId, {
        membership_package_id: assignmentForm.membership_package_id,
        starts_on: assignmentForm.starts_on || null,
        ends_on: assignmentForm.ends_on || null,
        status: "active",
      }),
    onSuccess: invalidateMember,
  });

  const recordPaymentMutation = useMutation({
    mutationFn: async () =>
      recordFinancePayment(token!, userId, {
        amount_cents: Math.round(Number(paymentForm.amount || 0) * 100),
        payment_method: paymentForm.payment_method,
        payment_status: paymentForm.payment_status,
        paid_on: paymentForm.paid_on || null,
        finance_invoice_id: paymentForm.finance_invoice_id || null,
        notes: paymentForm.notes,
      }),
    onSuccess: async () => {
      setPaymentForm({
        amount: "0",
        payment_method: "cash",
        payment_status: "paid",
        paid_on: "",
        finance_invoice_id: "",
        notes: "",
      });
      await invalidateMember();
    },
  });

  const createInvoiceMutation = useMutation({
    mutationFn: async () =>
      createFinanceInvoice(token!, userId, {
        amount_cents: Math.round(Number(invoiceForm.amount || 0) * 100),
        description: invoiceForm.description,
        due_date: invoiceForm.due_date || null,
        service_period_start: invoiceForm.service_period_start || null,
        service_period_end: invoiceForm.service_period_end || null,
        membership_package_subscription_id: invoiceForm.membership_package_subscription_id || undefined,
      }),
    onSuccess: async () => {
      setInvoiceForm({
        amount: "0",
        description: "",
        due_date: "",
        service_period_start: "",
        service_period_end: "",
        membership_package_subscription_id: "",
      });
      await invalidateMember();
    },
  });

  const renewalInvoiceMutation = useMutation({
    mutationFn: async () =>
      generateRenewalInvoice(token!, userId, {
        membership_package_subscription_id: renewalForm.membership_package_subscription_id || undefined,
        service_period_start: renewalForm.service_period_start || null,
        service_period_end: renewalForm.service_period_end || null,
        due_date: renewalForm.due_date || null,
      }),
    onSuccess: async () => {
      setRenewalForm({
        membership_package_subscription_id: "",
        service_period_start: "",
        service_period_end: "",
        due_date: "",
      });
      await invalidateMember();
    },
  });

  const issueInvoiceMutation = useMutation({
    mutationFn: async (invoiceId: string) => issueFinanceInvoice(token!, invoiceId, {}),
    onSuccess: invalidateMember,
  });

  const voidInvoiceMutation = useMutation({
    mutationFn: async (invoiceId: string) => voidFinanceInvoice(token!, invoiceId, {}),
    onSuccess: invalidateMember,
  });

  const redeemMutation = useMutation({
    mutationFn: async () =>
      redeemPromotion(token!, userId, {
        promotion_code: redemptionForm.promotion_code,
      }),
    onSuccess: async () => {
      setRedemptionForm({ promotion_code: "", promotion_campaign_id: "" });
      await invalidateMember();
    },
  });

  const createCreditMutation = useMutation({
    mutationFn: async () =>
      createManualCredit(token!, userId, {
        amount_cents: Math.round(Number(creditForm.amount || 0) * 100),
        description: creditForm.description,
        request_id: crypto.randomUUID(),
      }),
    onSuccess: async () => {
      setCreditForm({ amount: "0", description: "" });
      await invalidateMember();
    },
  });

  const applyCreditMutation = useMutation({
    mutationFn: async () =>
      applyCreditToPayment(token!, userId, applyCreditForm.payment_id, {
        amount_cents: Math.round(Number(applyCreditForm.amount || 0) * 100),
        description: applyCreditForm.description,
        request_id: crypto.randomUUID(),
      }),
    onSuccess: async () => {
      setApplyCreditForm({ payment_id: "", amount: "0", description: "" });
      await invalidateMember();
    },
  });

  const applyInvoiceCreditMutation = useMutation({
    mutationFn: async () =>
      applyCreditToInvoice(token!, userId, applyInvoiceCreditForm.invoice_id, {
        amount_cents: Math.round(Number(applyInvoiceCreditForm.amount || 0) * 100),
        description: applyInvoiceCreditForm.description,
        request_id: crypto.randomUUID(),
      }),
    onSuccess: async () => {
      setApplyInvoiceCreditForm({ invoice_id: "", amount: "0", description: "" });
      await invalidateMember();
    },
  });

  const reversePaymentMutation = useMutation({
    mutationFn: async () =>
      reverseFinancePayment(token!, userId, paymentReversalForm.payment_id, {
        amount_cents: Math.round(Number(paymentReversalForm.amount || 0) * 100),
        reason: paymentReversalForm.reason,
        request_id: crypto.randomUUID(),
      }),
    onSuccess: async () => {
      setPaymentReversalForm({ payment_id: "", amount: "0", reason: "" });
      await invalidateMember();
    },
  });

  const reverseCreditMutation = useMutation({
    mutationFn: async () =>
      reverseCreditLedgerEntry(token!, userId, creditReversalForm.credit_ledger_entry_id, {
        amount_cents: Math.round(Number(creditReversalForm.amount || 0) * 100),
        reason: creditReversalForm.reason,
        request_id: crypto.randomUUID(),
      }),
    onSuccess: async () => {
      setCreditReversalForm({ credit_ledger_entry_id: "", amount: "0", reason: "" });
      await invalidateMember();
    },
  });

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-6xl space-y-6">
        <Link className="text-sm font-bold text-[var(--primary)]" href="/admin/finance">
          {i18n("backToFinance2de0820")}
        </Link>
        <section className="rounded-[2rem] border border-[var(--border)] bg-[var(--panel)] p-8">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">{i18n("memberFinanceProfile6f16152")}</p>
          <h1 className="mt-3 break-all text-3xl font-black md:text-4xl">{userId}</h1>
          <p className="mt-2 text-sm text-[var(--muted)]">
            {i18n("statusbae7d5b")} {membership ? <SemanticLabel value={field(membership, "status")} /> : i18n("noMembershipb174349")} {i18n("type3d87766")} <SemanticLabel value={field(membership, "user_type_snapshot", "unknown")} />
          </p>
          <div className="mt-5 inline-flex rounded-full bg-[var(--text)] px-5 py-3 text-sm font-black text-[var(--primary-contrast)]">
            {i18n("availableCredit245f0e1")} {money(uiLocale, creditBalance)}
          </div>
          <div className="mt-3 inline-flex rounded-full bg-[color-mix(in_srgb,var(--success)_18%,transparent)] px-5 py-3 text-sm font-black text-[var(--success)]">
            {i18n("entitlement8994749")} <SemanticLabel value={field(entitlement, "status", "inactive")} /> · {entitlement ? <SemanticLabel value={field(entitlement, "source")} /> : i18n("notEvaluated4bb5e31")}
          </div>
        </section>

        <section className="grid gap-6 xl:grid-cols-2">
          <Panel title={i18n("membershipProfile57ffeba")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                updateMembershipMutation.mutate();
              }}
            >
              <Select
                label={i18n("userType0bea7a8")}
                value={membershipForm.user_type_snapshot}
                options={["member", "athlete"]}
                onChange={(user_type_snapshot) =>
                  setMembershipOverrides({ ...membershipOverrides, user_type_snapshot })
                }
              />
              <Select
                label={i18n("statusbae7d5b")}
                value={membershipForm.status}
                options={["active", "expiring", "expired", "cancelled", "paused", "trial", "comped"]}
                onChange={(status) => setMembershipOverrides({ ...membershipOverrides, status })}
              />
              <Select
                label={i18n("signupSource69d3a02")}
                value={membershipForm.signup_source}
                options={["direct", "referral", "promo", "admin_created", "migrated", "imported"]}
                onChange={(signup_source) => setMembershipOverrides({ ...membershipOverrides, signup_source })}
              />
              <div className="grid gap-3 md:grid-cols-2">
                <Input
                  label={i18n("startsOn6d888f7")}
                  required={false}
                  type="date"
                  value={membershipForm.starts_on}
                  onChange={(starts_on) => setMembershipOverrides({ ...membershipOverrides, starts_on })}
                />
                <Input
                  label={i18n("expiresOn549cabe")}
                  required={false}
                  type="date"
                  value={membershipForm.expires_on}
                  onChange={(expires_on) => setMembershipOverrides({ ...membershipOverrides, expires_on })}
                />
              </div>
              <Input
                label={i18n("notes7044004")}
                required={false}
                value={membershipForm.notes}
                onChange={(notes) => setMembershipOverrides({ ...membershipOverrides, notes })}
              />
              <SubmitButton pending={updateMembershipMutation.isPending}>{i18n("saveMembership592a509")}</SubmitButton>
              <ErrorText error={updateMembershipMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("assignPackage37b3330")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                assignPackageMutation.mutate();
              }}
            >
              <Select
                label={i18n("package7431e3d")}
                value={assignmentForm.membership_package_id}
                options={activePackages.map((item) => field(item, "id"))}
                optionLabel={(id) => field(activePackages.find((item) => field(item, "id") === id), "name", id)}
                onChange={(membership_package_id) => setAssignmentForm({ ...assignmentForm, membership_package_id })}
              />
              <div className="grid gap-3 md:grid-cols-2">
                <Input label={i18n("startsOn6d888f7")} required={false} type="date" value={assignmentForm.starts_on} onChange={(starts_on) => setAssignmentForm({ ...assignmentForm, starts_on })} />
                <Input label={i18n("endsOn5c262f3")} required={false} type="date" value={assignmentForm.ends_on} onChange={(ends_on) => setAssignmentForm({ ...assignmentForm, ends_on })} />
              </div>
              <SubmitButton pending={assignPackageMutation.isPending}>{i18n("assignPackage37b3330")}</SubmitButton>
              <ErrorText error={assignPackageMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("recordPayment86e5632")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                recordPaymentMutation.mutate();
              }}
            >
              <Input label={i18n("amountInEure238d40")} type="number" value={paymentForm.amount} onChange={(amount) => setPaymentForm({ ...paymentForm, amount })} />
              <Select
                label={i18n("paymentMethod0e55fb3")}
                value={paymentForm.payment_method}
                options={["cash", "bank_transfer", "card_manual", "other"]}
                onChange={(payment_method) => setPaymentForm({ ...paymentForm, payment_method })}
              />
              <Select
                label={i18n("paymentStatus9dfea40")}
                value={paymentForm.payment_status}
                options={["paid", "pending", "refunded", "failed", "waived"]}
                onChange={(payment_status) => setPaymentForm({ ...paymentForm, payment_status })}
              />
              <Input label={i18n("paidOnfca3213")} required={false} type="date" value={paymentForm.paid_on} onChange={(paid_on) => setPaymentForm({ ...paymentForm, paid_on })} />
              <Select
                label={i18n("invoicef9f3881")}
                value={paymentForm.finance_invoice_id}
                options={payableInvoices.map((invoice) => field(invoice, "id"))}
                optionLabel={(id) => {
                  const invoice = payableInvoices.find((item) => field(item, "id") === id);
                  return (field(invoice, "invoice_number", id)) + i18n("due6e49fc0") + (money(uiLocale, invoice?.balance_due_cents));
                }}
                required={false}
                onChange={(finance_invoice_id) => {
                  const invoice = payableInvoices.find((item) => field(item, "id") === finance_invoice_id);
                  const balanceDue =
                    typeof invoice?.balance_due_cents === "number" ? invoice.balance_due_cents : null;

                  setPaymentForm({
                    ...paymentForm,
                    finance_invoice_id,
                    amount: balanceDue !== null ? euroInputValue(balanceDue) : paymentForm.amount,
                  });
                }}
              />
              <Input label={i18n("notes7044004")} required={false} value={paymentForm.notes} onChange={(notes) => setPaymentForm({ ...paymentForm, notes })} />
              <SubmitButton pending={recordPaymentMutation.isPending}>{i18n("recordPayment86e5632")}</SubmitButton>
              <ErrorText error={recordPaymentMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("createInvoicea0567cf")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                createInvoiceMutation.mutate();
              }}
            >
              <Input label={i18n("amountInEure238d40")} type="number" value={invoiceForm.amount} onChange={(amount) => setInvoiceForm({ ...invoiceForm, amount })} />
              <Select
                label={i18n("packageSubscriptionbf929b7")}
                value={invoiceForm.membership_package_subscription_id}
                options={packageSubscriptions.map((subscription) => field(subscription, "id"))}
                optionLabel={(id) => {
                  const subscription = packageSubscriptions.find((item) => field(item, "id") === id);
                  return (field(subscription, "package_code_snapshot", id)) + " · " + (money(uiLocale, subscription?.price_cents_snapshot));
                }}
                required={false}
                onChange={(membership_package_subscription_id) => {
                  const subscription = packageSubscriptions.find(
                    (item) => field(item, "id") === membership_package_subscription_id,
                  );
                  const priceCents =
                    typeof subscription?.price_cents_snapshot === "number" ? subscription.price_cents_snapshot : null;
                  const code = field(subscription, "package_code_snapshot");

                  setInvoiceForm({
                    ...invoiceForm,
                    membership_package_subscription_id,
                    amount: priceCents !== null ? euroInputValue(priceCents) : invoiceForm.amount,
                    description: code ? i18n("package5544677") + (code) : invoiceForm.description,
                  });
                }}
              />
              <Input label={i18n("description55f8ebc")} value={invoiceForm.description} onChange={(description) => setInvoiceForm({ ...invoiceForm, description })} />
              <Input label={i18n("dueDate4c1aeeb")} required={false} type="date" value={invoiceForm.due_date} onChange={(due_date) => setInvoiceForm({ ...invoiceForm, due_date })} />
              <div className="grid gap-3 md:grid-cols-2">
                <Input label={i18n("serviceStarts2bacd5f")} required={false} type="date" value={invoiceForm.service_period_start} onChange={(service_period_start) => setInvoiceForm({ ...invoiceForm, service_period_start })} />
                <Input label={i18n("serviceEnds3f37b6c")} required={false} type="date" value={invoiceForm.service_period_end} onChange={(service_period_end) => setInvoiceForm({ ...invoiceForm, service_period_end })} />
              </div>
              <SubmitButton pending={createInvoiceMutation.isPending}>{i18n("createDraftInvoice1ef1fa2")}</SubmitButton>
              <ErrorText error={createInvoiceMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("generateRenewalInvoice9242ec6")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                renewalInvoiceMutation.mutate();
              }}
            >
              <Select
                label={i18n("packageSubscriptionbf929b7")}
                value={renewalForm.membership_package_subscription_id}
                options={renewableSubscriptions.map((subscription) => field(subscription, "id"))}
                optionLabel={(id) => {
                  const subscription = renewableSubscriptions.find((item) => field(item, "id") === id);
                  return (field(subscription, "package_code_snapshot", id)) + " · " + (money(uiLocale, subscription?.price_cents_snapshot));
                }}
                required={false}
                onChange={(membership_package_subscription_id) =>
                  setRenewalForm({ ...renewalForm, membership_package_subscription_id })
                }
              />
              <Input label={i18n("periodStarts631c384")} required={false} type="date" value={renewalForm.service_period_start} onChange={(service_period_start) => setRenewalForm({ ...renewalForm, service_period_start })} />
              <Input label={i18n("customPeriodEndsece7b1c")} required={customRenewal} type="date" value={renewalForm.service_period_end} onChange={(service_period_end) => setRenewalForm({ ...renewalForm, service_period_end })} />
              <Input label={i18n("dueDate4c1aeeb")} required={false} type="date" value={renewalForm.due_date} onChange={(due_date) => setRenewalForm({ ...renewalForm, due_date })} />
              <SubmitButton pending={renewalInvoiceMutation.isPending}>{i18n("generateRenewalInvoice9242ec6")}</SubmitButton>
              <ErrorText error={renewalInvoiceMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("redeemPromotiona0fb02e")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                redeemMutation.mutate();
              }}
            >
              <Select
                label={i18n("campaign69390e1")}
                value={redemptionForm.promotion_campaign_id}
                options={campaigns.map((campaign) => field(campaign, "id"))}
                optionLabel={(id) => field(campaigns.find((campaign) => field(campaign, "id") === id), "name", id)}
                onChange={(promotion_campaign_id) =>
                  setRedemptionForm({ ...redemptionForm, promotion_campaign_id, promotion_code: "" })
                }
              />
              <Select
                label={i18n("promotionCode392b639")}
                value={redemptionForm.promotion_code}
                options={codes.map((code) => field(code, "code"))}
                optionLabel={(code) => code}
                disabled={!redemptionForm.promotion_campaign_id}
                onChange={(promotion_code) => setRedemptionForm({ ...redemptionForm, promotion_code })}
              />
              <SubmitButton pending={redeemMutation.isPending} disabled={!redemptionForm.promotion_code}>
                {i18n("redeemPromotiona0fb02e")}
              </SubmitButton>
              <ErrorText error={redeemMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("grantManualCreditfa7b548")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                createCreditMutation.mutate();
              }}
            >
              <Input
                label={i18n("creditAmountInEur4d8a0bf")}
                type="number"
                value={creditForm.amount}
                onChange={(amount) => setCreditForm({ ...creditForm, amount })}
              />
              <Input
                label={i18n("description55f8ebc")}
                required={false}
                value={creditForm.description}
                onChange={(description) => setCreditForm({ ...creditForm, description })}
              />
              <SubmitButton pending={createCreditMutation.isPending}>{i18n("grantCredit5abca43")}</SubmitButton>
              <ErrorText error={createCreditMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("applyCreditToPaymente722003")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                applyCreditMutation.mutate();
              }}
            >
              <p className="rounded-2xl bg-[var(--panel)] p-4 text-sm font-bold text-[var(--muted)]">
                {i18n("availableCreditcca6998")} {money(uiLocale, creditBalance)}
              </p>
              <Select
                label={i18n("paymentb41a92b")}
                value={applyCreditForm.payment_id}
                options={creditablePayments.map((payment) => field(payment, "id"))}
                optionLabel={(id) => {
                  const payment = creditablePayments.find((item) => field(item, "id") === id);
                  return (money(uiLocale, payment?.amount_cents)) + " · " + (field(payment, "payment_status", "payment"));
                }}
                disabled={creditablePayments.length === 0 || creditBalance <= 0}
                onChange={(payment_id) => setApplyCreditForm({ ...applyCreditForm, payment_id })}
              />
              <Input
                label={i18n("creditAmountInEur4d8a0bf")}
                type="number"
                value={applyCreditForm.amount}
                onChange={(amount) => setApplyCreditForm({ ...applyCreditForm, amount })}
              />
              <Input
                label={i18n("description55f8ebc")}
                required={false}
                value={applyCreditForm.description}
                onChange={(description) => setApplyCreditForm({ ...applyCreditForm, description })}
              />
              <SubmitButton
                pending={applyCreditMutation.isPending}
                disabled={!applyCreditForm.payment_id || creditBalance <= 0}
              >
                {i18n("applyCredita939533")}
              </SubmitButton>
              <ErrorText error={applyCreditMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("applyCreditToInvoicef94ae1a")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                applyInvoiceCreditMutation.mutate();
              }}
            >
              <p className="rounded-2xl bg-[var(--panel)] p-4 text-sm font-bold text-[var(--muted)]">
                {i18n("availableCreditcca6998")} {money(uiLocale, creditBalance)}
              </p>
              <Select
                label={i18n("invoicef9f3881")}
                value={applyInvoiceCreditForm.invoice_id}
                options={invoices.map((invoice) => field(invoice, "id"))}
                optionLabel={(id) => {
                  const invoice = invoices.find((item) => field(item, "id") === id);
                  return (field(invoice, "invoice_number", id)) + i18n("due6e49fc0") + (money(uiLocale, invoice?.balance_due_cents));
                }}
                disabled={invoices.length === 0 || creditBalance <= 0}
                onChange={(invoice_id) => setApplyInvoiceCreditForm({ ...applyInvoiceCreditForm, invoice_id })}
              />
              <Input
                label={i18n("creditAmountInEur4d8a0bf")}
                type="number"
                value={applyInvoiceCreditForm.amount}
                onChange={(amount) => setApplyInvoiceCreditForm({ ...applyInvoiceCreditForm, amount })}
              />
              <Input
                label={i18n("description55f8ebc")}
                required={false}
                value={applyInvoiceCreditForm.description}
                onChange={(description) => setApplyInvoiceCreditForm({ ...applyInvoiceCreditForm, description })}
              />
              <SubmitButton
                pending={applyInvoiceCreditMutation.isPending}
                disabled={!applyInvoiceCreditForm.invoice_id || creditBalance <= 0}
              >
                {i18n("applyCreditToInvoicef94ae1a")}
              </SubmitButton>
              <ErrorText error={applyInvoiceCreditMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("refundOrReversePayment9d232b2")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                reversePaymentMutation.mutate();
              }}
            >
              <Select
                label={i18n("paymentb41a92b")}
                value={paymentReversalForm.payment_id}
                options={reversiblePayments.map((payment) => field(payment, "id"))}
                optionLabel={(id) => {
                  const payment = reversiblePayments.find((item) => field(item, "id") === id);
                  return (money(uiLocale, payment?.net_amount_cents)) + i18n("remainingd475cb2") + (field(payment, "payment_method", "payment"));
                }}
                disabled={reversiblePayments.length === 0}
                onChange={(payment_id) => {
                  const payment = reversiblePayments.find((item) => field(item, "id") === payment_id);
                  setPaymentReversalForm({
                    ...paymentReversalForm,
                    payment_id,
                    amount: euroInputValue(payment?.net_amount_cents),
                  });
                }}
              />
              <Input
                label={i18n("refundAmountInEuraa86270")}
                type="number"
                value={paymentReversalForm.amount}
                onChange={(amount) => setPaymentReversalForm({ ...paymentReversalForm, amount })}
              />
              <Input
                label={i18n("reasonf219cc0")}
                required={false}
                value={paymentReversalForm.reason}
                onChange={(reason) => setPaymentReversalForm({ ...paymentReversalForm, reason })}
              />
              <SubmitButton pending={reversePaymentMutation.isPending} disabled={!paymentReversalForm.payment_id}>
                {i18n("recordRefundc86cbda")}
              </SubmitButton>
              <ErrorText error={reversePaymentMutation.error} />
            </form>
          </Panel>

          <Panel title={i18n("restoreAppliedCredit2444b29")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                reverseCreditMutation.mutate();
              }}
            >
              <Select
                label={i18n("creditEntryb1266d7")}
                value={creditReversalForm.credit_ledger_entry_id}
                options={reversibleCreditEntries.map((entry) => field(entry, "id"))}
                optionLabel={(id) => {
                  const entry = reversibleCreditEntries.find((item) => field(item, "id") === id);
                  return (money(uiLocale, entry?.remaining_reversible_cents)) + i18n("remainingd475cb2") + (field(entry, "entry_type", "credit"));
                }}
                disabled={reversibleCreditEntries.length === 0}
                onChange={(credit_ledger_entry_id) => {
                  const entry = reversibleCreditEntries.find((item) => field(item, "id") === credit_ledger_entry_id);
                  setCreditReversalForm({
                    ...creditReversalForm,
                    credit_ledger_entry_id,
                    amount: euroInputValue(entry?.remaining_reversible_cents),
                  });
                }}
              />
              <Input
                label={i18n("creditToRestoreInEurdf3aed1")}
                type="number"
                value={creditReversalForm.amount}
                onChange={(amount) => setCreditReversalForm({ ...creditReversalForm, amount })}
              />
              <Input
                label={i18n("reasonf219cc0")}
                required={false}
                value={creditReversalForm.reason}
                onChange={(reason) => setCreditReversalForm({ ...creditReversalForm, reason })}
              />
              <SubmitButton pending={reverseCreditMutation.isPending} disabled={!creditReversalForm.credit_ledger_entry_id}>
                {i18n("restoreCredit479133c")}
              </SubmitButton>
              <ErrorText error={reverseCreditMutation.error} />
            </form>
          </Panel>
        </section>

        <section className="grid gap-6 xl:grid-cols-5">
          <InvoiceHistory
            rows={invoices}
            token={token!}
            issuePending={issueInvoiceMutation.isPending}
            voidPending={voidInvoiceMutation.isPending}
            onIssue={(id) => issueInvoiceMutation.mutate(id)}
            onVoid={(id) => voidInvoiceMutation.mutate(id)}
            onRefresh={invalidateMember}
          />
          <History title={i18n("packageSubscriptions09a33f1")} rows={memberQuery.data?.package_subscriptions ?? []} primary="package_code_snapshot" secondary="status" />
          <History title={i18n("payments44357ae")} rows={memberQuery.data?.payments ?? []} primary="payment_status" secondary="amount_cents" moneySecondary />
          <History title={i18n("paymentReversals0f3a7be")} rows={memberQuery.data?.payment_reversals ?? []} primary="reversal_type" secondary="amount_cents" moneySecondary />
          <History title={i18n("promoRedemptions7408919")} rows={memberQuery.data?.promotion_redemptions ?? []} primary="discount_type_snapshot" secondary="discount_value_snapshot" />
          <History title={i18n("creditLedgerc2e8688")} rows={creditLedgerEntries} primary="entry_type" secondary="amount_cents" moneySecondary />
        </section>
      </div>
    </main>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-[1.8rem] border border-[var(--border)] bg-[var(--panel)] p-6">
      <h2 className="text-xl font-black">{title}</h2>
      <div className="mt-4">{children}</div>
    </section>
  );
}

function Input({
  label,
  value,
  onChange,
  required = true,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  type?: string;
}) {
  
  return (
    <label className="block space-y-1 text-sm font-semibold">
      <span>{label}</span>
      <input
        className="w-full rounded-2xl border border-[var(--border)] px-4 py-3"
        required={required}
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function Select({
  label,
  value,
  options,
  onChange,
  optionLabel,
  disabled = false,
  required = true,
}: {
  label: string;
  value: string;
  options: string[];
  onChange: (value: string) => void;
  optionLabel?: (value: string) => string;
  disabled?: boolean;
  required?: boolean;
}) {
  const i18n = useUiTranslations();
  return (
    <label className="block space-y-1 text-sm font-semibold">
      <span>{label}</span>
      <select
        className="w-full rounded-2xl border border-[var(--border)] px-4 py-3"
        required={required}
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="" disabled={required}>
          {required ? i18n("select8598222") + (label.toLowerCase()) : i18n("no816c52f") + (label.toLowerCase())}
        </option>
        {options.map((option) => (
          <option key={option} value={option}>
            {optionLabel ? optionLabel(option) : option}
          </option>
        ))}
      </select>
    </label>
  );
}

function InvoiceHistory({
  rows,
  token,
  issuePending,
  voidPending,
  onIssue,
  onVoid,
  onRefresh,
}: {
  rows: FinanceRecord[];
  token: string;
  issuePending: boolean;
  voidPending: boolean;
  onIssue: (id: string) => void;
  onVoid: (id: string) => void;
  onRefresh: () => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  return (
    <section className="rounded-[1.8rem] border border-[var(--border)] bg-[var(--panel)] p-6 xl:col-span-4">
      <h2 className="text-xl font-black">{i18n("invoices35f8f37")}</h2>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        {rows.length === 0 ? <p className="text-sm text-[var(--muted)]">{i18n("noInvoicesacd181b")}</p> : null}
        {rows.map((row) => {
          const id = field(row, "id");
          const status = field(row, "status");

          return (
            <div key={id} className="rounded-2xl border border-[var(--border)] p-4 space-y-3">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-black">{field(row, "invoice_number", id)}</p>
                  <p className="text-sm text-[var(--muted)]">
                    <SemanticLabel value={status} /> {i18n("totald6cf831")} {money(uiLocale, row.total_cents)} {i18n("due6e49fc0")} {money(uiLocale, row.balance_due_cents)}
                  </p>
                  <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[var(--primary)]">
                    {i18n("due30cdf73")} {field(row, "due_date", i18n("notSetef374c5"))}
                  </p>
                </div>
                <div className="flex gap-2">
                  {status === "draft" ? (
                    <button
                      className="rounded-full bg-[var(--text)] px-4 py-2 text-xs font-bold text-[var(--primary-contrast)] disabled:opacity-50"
                      disabled={issuePending}
                      type="button"
                      onClick={() => onIssue(id)}
                    >
                      {i18n("issue73781a1")}
                    </button>
                  ) : null}
                  {status !== "void" && status !== "paid" ? (
                    <button
                      className="rounded-full border border-[var(--danger)] px-4 py-2 text-xs font-bold text-[var(--danger)] disabled:opacity-50"
                      disabled={voidPending}
                      type="button"
                      onClick={() => onVoid(id)}
                    >
                      {i18n("void207c7c0")}
                    </button>
                  ) : null}
                </div>
              </div>
              <InvoiceFileActions invoice={row} token={token} onRefresh={onRefresh} />
            </div>
          );
        })}
      </div>
    </section>
  );
}

function InvoiceFileActions({
  invoice,
  token,
  onRefresh,
}: {
  invoice: FinanceRecord;
  token: string;
  onRefresh: () => void;
}) {
  const i18n = useUiTranslations();
  const invoiceId = field(invoice, "id");
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editDueDate, setEditDueDate] = useState(field(invoice, "due_date"));
  const [editNotes, setEditNotes] = useState(field(invoice, "notes"));
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const invoiceParams = (invoice.params as Record<string, string> | null) ?? {};
  const hasFile = Boolean(invoiceParams.file_key);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setUploadError(null);
    try {
      const { upload_url, content_type } = await getInvoiceUploadUrl(
        token,
        invoiceId,
        file.name,
        file.type || "application/octet-stream",
      );
      const res = await fetch(upload_url, {
        method: "PUT",
        headers: { "Content-Type": content_type },
        body: file,
      });
      if (!res.ok) throw new Error(i18n("uploadFailed7c67e1c") + (res.status));
      onRefresh();
    } catch (err) {
      setUploadError(err instanceof Error ? localizeError(err, i18n) : i18n("uploadFailedad0d060"));
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function handleDownload() {
    setDownloading(true);
    try {
      const { download_url, file_name } = await getInvoiceDownloadUrl(token, invoiceId);
      const a = document.createElement("a");
      a.href = download_url;
      a.download = file_name;
      a.target = "_blank";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    } finally {
      setDownloading(false);
    }
  }

  async function handleSaveEdit() {
    setSaving(true);
    setSaveError(null);
    try {
      await updateFinanceInvoice(token, invoiceId, {
        due_date: editDueDate || undefined,
        notes: editNotes || undefined,
      });
      setEditing(false);
      onRefresh();
    } catch (err) {
      setSaveError(err instanceof Error ? localizeError(err, i18n) : i18n("saveFailed0a44446"));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-3">
      {/* Prominent notes display */}
      {!editing && (
        <div className="rounded-xl bg-[var(--panel)] border border-[var(--border)] px-3 py-2 space-y-0.5">
          {field(invoice, "notes") ? (
            <p className="text-sm font-semibold text-[var(--text)]">{field(invoice, "notes")}</p>
          ) : (
            <p className="text-xs italic text-[var(--dim)]">{i18n("noDescriptionf354c94")}</p>
          )}
          <div className="flex items-center justify-between">
            <p className="text-xs font-medium text-[var(--primary)]">
              {i18n("due7513f96")} {field(invoice, "due_date") || i18n("notSetef374c5")}
            </p>
            <button
              type="button"
              onClick={() => { setEditing(true); setSaveError(null); }}
              className="text-xs text-[var(--muted)] hover:text-[var(--text)] transition-colors"
            >
              {i18n("edit5301648")}
            </button>
          </div>
        </div>
      )}

      {/* Inline edit form */}
      {editing && (
        <div className="rounded-xl bg-[var(--panel)] border border-[var(--border)] px-3 py-3 space-y-2">
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em] text-[var(--muted)]">
              {i18n("description55f8ebc")}
            </label>
            <input
              type="text"
              value={editNotes}
              onChange={(e) => setEditNotes(e.target.value)}
              placeholder={i18n("invoiceDescription4d26246")}
              className="w-full rounded-lg border border-[var(--border)] bg-[var(--panel)] px-3 py-1.5 text-sm text-[var(--text)]"
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em] text-[var(--muted)]">
              {i18n("dueDate4c1aeeb")}
            </label>
            <input
              type="date"
              value={editDueDate}
              onChange={(e) => setEditDueDate(e.target.value)}
              className="w-full rounded-lg border border-[var(--border)] bg-[var(--panel)] px-3 py-1.5 text-sm text-[var(--text)]"
            />
          </div>
          {saveError && <p className="text-xs text-[var(--danger)]">{saveError}</p>}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={handleSaveEdit}
              disabled={saving}
              className="rounded-full bg-[var(--text)] px-4 py-1.5 text-xs font-bold text-[var(--primary-contrast)] disabled:opacity-50"
            >
              {saving ? i18n("saving56a2285") : i18n("saveefc007a")}
            </button>
            <button
              type="button"
              onClick={() => setEditing(false)}
              className="rounded-full border border-[var(--border)] px-4 py-1.5 text-xs font-semibold text-[var(--muted)] hover:bg-[var(--bg)]"
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>
        </div>
      )}

      {/* File actions */}
      <div className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <input ref={fileInputRef} type="file" accept="image/*,.pdf" className="hidden" onChange={handleFileChange} />
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            disabled={uploading}
            className="rounded-full border border-[var(--border)] bg-[var(--bg)] px-3 py-1 text-xs font-semibold text-[var(--muted)] hover:bg-[var(--border)] disabled:opacity-50 transition-colors"
          >
            {uploading ? i18n("uploadingd921a79") : hasFile ? i18n("replaceFile6d45b8c") : i18n("uploadFile503a3d8")}
          </button>
          {hasFile && (
            <button
              type="button"
              onClick={handleDownload}
              disabled={downloading}
              className="rounded-full border border-[var(--primary)] bg-[var(--panel)] px-3 py-1 text-xs font-semibold text-[var(--primary)] hover:bg-[color-mix(in_srgb,var(--primary)_12%,transparent)] disabled:opacity-50 transition-colors"
            >
              {downloading ? "…" : i18n("downloada479c9c")}
            </button>
          )}
          {invoiceParams.file_name && (
            <span className="text-xs text-[var(--muted)] truncate max-w-[160px]">{invoiceParams.file_name}</span>
          )}
        </div>
        {uploadError && <p className="text-xs text-[var(--danger)]">{uploadError}</p>}
      </div>
    </div>
  );
}

function SubmitButton({
  pending,
  disabled = false,
  children,
}: {
  pending: boolean;
  disabled?: boolean;
  children: React.ReactNode;
}) {
  const i18n = useUiTranslations();
  return (
    <button
      className="rounded-full bg-[var(--text)] px-5 py-3 text-sm font-bold text-[var(--primary-contrast)] disabled:opacity-50"
      disabled={pending || disabled}
      type="submit"
    >
      {pending ? i18n("savingae7e887") : children}
    </button>
  );
}

function ErrorText({ error }: { error: unknown }) {
  const i18n = useUiTranslations();
  if (!(error instanceof Error)) return null;
  return <p className="text-sm font-semibold text-[var(--danger)]">{localizeError(error, i18n)}</p>;
}

function History({
  title,
  rows,
  primary,
  secondary,
  moneySecondary = false,
}: {
  title: string;
  rows: FinanceRecord[];
  primary: string;
  secondary: string;
  moneySecondary?: boolean;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  return (
    <section className="rounded-[1.8rem] border border-[var(--border)] bg-[var(--panel)] p-6">
      <h2 className="text-xl font-black">{title}</h2>
      <div className="mt-4 grid gap-3">
        {rows.length === 0 ? <p className="text-sm text-[var(--muted)]">{i18n("noRecords2cd2e01")}</p> : null}
        {rows.map((row) => (
          <div key={field(row, "id")} className="rounded-2xl border border-[var(--border)] p-4">
            <p className="font-bold">{field(row, primary)}</p>
            <p className="text-sm text-[var(--muted)]">{moneySecondary ? money(uiLocale, row[secondary]) : field(row, secondary)}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
