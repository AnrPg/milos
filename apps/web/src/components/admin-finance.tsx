"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import {
  createFinancePackage,
  createPromotionCampaign,
  createPromotionCode,
  createReferralEvent,
  createReferralProgram,
  createReferralReward,
  fetchAdminSearch,
  fetchFinancePackages,
  fetchFinanceQueues,
  fetchFinanceSummary,
  fetchPromotionCampaigns,
  fetchReferralEvents,
  fetchReferralPrograms,
  fetchReferralRewards,
  updateReferralEventStatus,
  updateReferralRewardStatus,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function nestedRecord(record: FinanceRecord | null | undefined, key: string) {
  const value = record?.[key];
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as FinanceRecord;
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function dateText(value: unknown) {
  if (!value) return "—";
  return String(value).slice(0, 10);
}

function percent(value: unknown) {
  const amount = typeof value === "number" ? value : Number(value ?? 0);
  return `${amount.toFixed(1)}%`;
}

export function AdminFinance() {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const token = tokens?.access_token;
  const [packageForm, setPackageForm] = useState({
    code: "",
    name: "",
    family: "unlimited",
    billing_period: "monthly",
    price: "0",
    tags: "",
  });
  const [search, setSearch] = useState("");
  const [referralUserSearch, setReferralUserSearch] = useState("");
  const [campaignForm, setCampaignForm] = useState({
    name: "",
    description: "",
    starts_on: "",
    ends_on: "",
    active: true,
  });
  const [codeForm, setCodeForm] = useState({
    campaign_id: "",
    code: "",
    discount_type: "percent",
    discount_value: "10",
    max_redemptions: "",
    active: true,
  });
  const [referralProgramForm, setReferralProgramForm] = useState({
    name: "",
    description: "",
    reward_type: "credit",
    reward_value: "0",
    active: true,
  });
  const [referralEventForm, setReferralEventForm] = useState({
    referral_program_id: "",
    referrer_user_id: "",
    referred_user_id: "",
    membership_id: "",
    notes: "",
  });
  const [referralRewardForm, setReferralRewardForm] = useState({ referral_event_id: "" });

  const enabled = Boolean(token);

  const summaryQuery = useQuery({
    queryKey: ["admin", "finance", "summary"],
    enabled,
    queryFn: async () => fetchFinanceSummary(token!),
  });

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled,
    queryFn: async () => fetchFinancePackages(token!),
  });

  const queuesQuery = useQuery({
    queryKey: ["admin", "finance", "queues"],
    enabled,
    queryFn: async () => fetchFinanceQueues(token!, { limit: "12", expires_within_days: "30" }),
  });

  const campaignsQuery = useQuery({
    queryKey: ["admin", "finance", "promotions"],
    enabled,
    queryFn: async () => fetchPromotionCampaigns(token!),
  });

  const rewardsQuery = useQuery({
    queryKey: ["admin", "finance", "referral-rewards"],
    enabled,
    queryFn: async () => fetchReferralRewards(token!),
  });

  const referralEventsQuery = useQuery({
    queryKey: ["admin", "finance", "referrals"],
    enabled,
    queryFn: async () => fetchReferralEvents(token!),
  });

  const referralProgramsQuery = useQuery({
    queryKey: ["admin", "finance", "referral-programs"],
    enabled,
    queryFn: async () => fetchReferralPrograms(token!),
  });

  const searchTerm = search.trim();
  const searchReady = searchTerm.length > 0;

  const searchQuery = useQuery({
    queryKey: ["admin", "search", "finance", searchTerm],
    enabled: enabled && searchReady,
    queryFn: async () => fetchAdminSearch(token!, searchTerm, "all", { limit: "10" }),
  });

  const referralUserSearchTerm = referralUserSearch.trim();
  const referralUserSearchReady = referralUserSearchTerm.length >= 2;

  const referralUserSearchQuery = useQuery({
    queryKey: ["admin", "search", "referral-users", referralUserSearchTerm],
    enabled: enabled && referralUserSearchReady,
    queryFn: async () => fetchAdminSearch(token!, referralUserSearchTerm, "all", { limit: "20" }),
    staleTime: 10_000,
  });

  const createPackageMutation = useMutation({
    mutationFn: async () =>
      createFinancePackage(token!, {
        code: packageForm.code,
        name: packageForm.name,
        family: packageForm.family,
        billing_period: packageForm.billing_period,
        base_price_cents: Math.round(Number(packageForm.price || 0) * 100),
        currency: "EUR",
        tags: packageForm.tags
          .split(",")
          .map((tag) => tag.trim())
          .filter(Boolean),
        params: {},
      }),
    onSuccess: async () => {
      setPackageForm({ code: "", name: "", family: "unlimited", billing_period: "monthly", price: "0", tags: "" });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const createCampaignMutation = useMutation({
    mutationFn: async () =>
      createPromotionCampaign(token!, {
        ...campaignForm,
        starts_on: campaignForm.starts_on || null,
        ends_on: campaignForm.ends_on || null,
      }),
    onSuccess: async (response) => {
      setCampaignForm({ name: "", description: "", starts_on: "", ends_on: "", active: true });
      setCodeForm((current) => ({ ...current, campaign_id: field(response.promotion_campaign, "id") }));
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "promotions"] });
    },
  });

  const createCodeMutation = useMutation({
    mutationFn: async () =>
      createPromotionCode(token!, codeForm.campaign_id, {
        code: codeForm.code,
        discount_type: codeForm.discount_type,
        discount_value: Number(codeForm.discount_value || 0),
        max_redemptions: codeForm.max_redemptions ? Number(codeForm.max_redemptions) : null,
        active: codeForm.active,
      }),
    onSuccess: async () => {
      setCodeForm((current) => ({ ...current, code: "" }));
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const createReferralProgramMutation = useMutation({
    mutationFn: async () =>
      createReferralProgram(token!, {
        name: referralProgramForm.name,
        description: referralProgramForm.description,
        reward_type: referralProgramForm.reward_type,
        reward_value: Number(referralProgramForm.reward_value || 0),
        active: referralProgramForm.active,
      }),
    onSuccess: async (response) => {
      const programId = field(response.referral_program, "id");
      setReferralProgramForm({
        name: "",
        description: "",
        reward_type: "credit",
        reward_value: "0",
        active: true,
      });
      setReferralEventForm((current) => ({ ...current, referral_program_id: programId }));
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const updateRewardMutation = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => updateReferralRewardStatus(token!, id, status),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const updateReferralEventMutation = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => updateReferralEventStatus(token!, id, status),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const createReferralEventMutation = useMutation({
    mutationFn: async () =>
      createReferralEvent(token!, {
        referral_program_id: referralEventForm.referral_program_id,
        referrer_user_id: referralEventForm.referrer_user_id,
        referred_user_id: referralEventForm.referred_user_id,
        membership_id: referralEventForm.membership_id || undefined,
        notes: referralEventForm.notes,
        signup_source_snapshot: "referral",
      }),
    onSuccess: async () => {
      setReferralEventForm({
        referral_program_id: "",
        referrer_user_id: "",
        referred_user_id: "",
        membership_id: "",
        notes: "",
      });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const createReferralRewardMutation = useMutation({
    mutationFn: async () =>
      createReferralReward(token!, referralRewardForm.referral_event_id, {}),
    onSuccess: async () => {
      setReferralRewardForm({ referral_event_id: "" });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  const totals = (summaryQuery.data?.totals ?? {}) as FinanceRecord;
  const packages = packagesQuery.data?.packages ?? [];
  const campaigns = campaignsQuery.data?.promotion_campaigns ?? [];
  const referralPrograms = referralProgramsQuery.data?.referral_programs ?? [];
  const referralEvents = referralEventsQuery.data?.referral_events ?? [];
  const rewards = rewardsQuery.data?.referral_rewards ?? [];
  const queues = queuesQuery.data?.queues ?? {};
  const users = searchReady ? searchQuery.data?.users ?? [] : [];
  const referralSearchUsers = referralUserSearchReady
    ? (referralUserSearchQuery.data?.users ?? []).filter((user) => {
        const role = field(user, "identity_role");
        return ["member", "athlete"].includes(role);
      })
    : [];
  const monthlyRevenue = (summaryQuery.data?.monthly_revenue ?? []) as FinanceRecord[];
  const rewardableReferralEvents = referralEvents.filter((event) =>
    ["approved", "applied"].includes(field(event, "status")),
  );
  const selectedRewardEvent = rewardableReferralEvents.find(
    (event) => field(event, "id") === referralRewardForm.referral_event_id,
  );
  const selectedRewardProgram = referralPrograms.find(
    (program) => field(program, "id") === field(selectedRewardEvent, "referral_program_id"),
  );
  const selectedReferredUser = referralSearchUsers.find(
    (user) => field(user, "id") === referralEventForm.referred_user_id,
  );
  const selectedReferredMembership = nestedRecord(selectedReferredUser, "membership");
  const canCreateReferralEvent = Boolean(
    referralEventForm.referral_program_id &&
      referralEventForm.referrer_user_id &&
      referralEventForm.referred_user_id &&
      referralEventForm.membership_id,
  );

  const summaryCards: Array<[string, string]> = [
    [i18n("activeMemberships0d117fb"), String(totals.active_memberships ?? 0)],
    [i18n("expiringIn30Days3722a5d"), String(totals.expiring_memberships ?? 0)],
    [i18n("paidRevenue64c34e5"), money(uiLocale, totals.paid_revenue_cents)],
    [i18n("openCreditBalancec588f1f"), money(uiLocale, totals.credit_balance_cents)],
    [i18n("outstandingInvoices700edaf"), money(uiLocale, totals.outstanding_invoice_balance_cents)],
    [i18n("overdueInvoices747a2d8"), money(uiLocale, totals.overdue_invoice_balance_cents)],
    [i18n("renewalConversion8c3f769"), percent(totals.renewal_conversion_percent)],
    [i18n("invoiceCreditOffsets9fc1210"), money(uiLocale, totals.invoice_credit_offset_cents)],
  ];

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-7xl space-y-8">
        <section className="rounded-[2rem] border border-[var(--border)] bg-[var(--panel)] p-8">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">{i18n("financeOperations60f9e5a")}</p>
          <h1 className="mt-3 text-4xl font-black tracking-tight md:text-5xl">{i18n("membershipRevenueCockpit0b90204")}</h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-[var(--muted)]">
            {i18n("managePackagesMemberFinanceProfilesManualPaymentsPromotions366ce90")}
          </p>
        </section>

        <section className="grid gap-4 md:grid-cols-3 xl:grid-cols-4">
          {summaryCards.map(([label, value]) => (
            <div key={String(label)} className="rounded-[1.5rem] border border-[var(--border)] bg-[var(--panel)] p-5">
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{label}</p>
              <p className="mt-3 text-3xl font-black">{String(value)}</p>
            </div>
          ))}
        </section>

        <section className="border-y border-[var(--border)] bg-[var(--panel)] px-4 py-6 md:px-6">
          <h2 className="text-xl font-black">{i18n("monthlyRevenue93e061c")}</h2>
          <div className="mt-4 h-72 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={monthlyRevenue}>
                <CartesianGrid stroke="var(--border)" vertical={false} />
                <XAxis
                  dataKey="period_start"
                  tickFormatter={(value) => String(value).slice(0, 7)}
                />
                <YAxis tickFormatter={(value) => "€" + (Number(value) / 100)} />
                <Tooltip
                  labelFormatter={(value) => String(value).slice(0, 7)}
                  formatter={(value) => money(uiLocale, value)}
                />
                <Line
                  dataKey="paid_revenue_cents"
                  name="Paid revenue"
                  stroke="var(--success)"
                  strokeWidth={3}
                  dot={false}
                />
                <Line
                  dataKey="pending_revenue_cents"
                  name="Pending revenue"
                  stroke="var(--primary)"
                  strokeWidth={2}
                  strokeDasharray="5 4"
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </section>

        <section className="grid gap-6 xl:grid-cols-[0.9fr_1.1fr]">
          <form
            className="space-y-3 rounded-[1.8rem] border border-[var(--border)] bg-[var(--panel)] p-6"
            onSubmit={(event) => {
              event.preventDefault();
              createPackageMutation.mutate();
            }}
          >
            <h2 className="text-xl font-black">{i18n("createMembershipPackage3b5ed69")}</h2>
            <Input label={i18n("packageCode4e5df5f")} value={packageForm.code} onChange={(code) => setPackageForm({ ...packageForm, code })} />
            <Input label={i18n("name709a232")} value={packageForm.name} onChange={(name) => setPackageForm({ ...packageForm, name })} />
            <div className="grid gap-3 md:grid-cols-2">
              <Select
                label={i18n("family4efb6cb")}
                value={packageForm.family}
                options={["unlimited", "limited-visits", "personal-programming", "hybrid"]}
                onChange={(family) => setPackageForm({ ...packageForm, family })}
              />
              <Select
                label={i18n("billingPeriodda59f5a")}
                value={packageForm.billing_period}
                options={["monthly", "quarterly", "annual", "custom"]}
                onChange={(billing_period) => setPackageForm({ ...packageForm, billing_period })}
              />
            </div>
            <Input
              label={i18n("priceInEur0e33182")}
              type="number"
              value={packageForm.price}
              onChange={(price) => setPackageForm({ ...packageForm, price })}
            />
            <Input
              label={i18n("tagsCommaSeparated7bfd75e")}
              value={packageForm.tags}
              required={false}
              onChange={(tags) => setPackageForm({ ...packageForm, tags })}
            />
            <SubmitButton pending={createPackageMutation.isPending}>{i18n("createPackagebd56259")}</SubmitButton>
            <ErrorText error={createPackageMutation.error} />
          </form>

          <Panel title={i18n("membershipPackages3cd69ce")}>
            <div className="grid gap-3">
              {packages.length === 0 ? <EmptyState>{i18n("noPackagesYet0b70a95")}</EmptyState> : null}
              {packages.map((item) => (
                <Link
                  key={field(item, "id")}
                  href={`/admin/finance/packages/${field(item, "id")}`}
                  className="rounded-2xl border border-[var(--border)] p-4 transition hover:border-[var(--text)]"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="font-bold">{field(item, "name", field(item, "code"))}</p>
                      <p className="text-sm text-[var(--muted)]">
                        {field(item, "code")} · {field(item, "family")} · {field(item, "billing_period")}
                      </p>
                    </div>
                    <p className="font-black">{money(uiLocale, item.base_price_cents)}</p>
                  </div>
                </Link>
              ))}
            </div>
          </Panel>
        </section>

        <section className="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
          <Panel title={i18n("memberFinanceProfilesf78cebd")}>
            <Input label={i18n("searchUsers1bd6226")} required={false} value={search} onChange={setSearch} />
            <div className="mt-4 grid gap-3 md:grid-cols-2">
              {!searchReady ? (
                <p className="rounded-2xl border border-[var(--border)] p-4 text-sm text-[var(--muted)] md:col-span-2">
                  {i18n("enterANameToLoadMatchingFinanceProfiles0fe97fa")}
                </p>
              ) : null}
              {searchReady && !searchQuery.isLoading && users.length === 0 ? (
                <p className="rounded-2xl border border-[var(--border)] p-4 text-sm text-[var(--muted)] md:col-span-2">
                  {i18n("noMatchingMembersFound65841d7")}
                </p>
              ) : null}
              {users.slice(0, 10).map((user) => {
                const membership = (user.membership as FinanceRecord | null) ?? null;
                return (
                  <Link
                    key={field(user, "id")}
                    href={`/admin/finance/members/${field(user, "id")}`}
                    className="rounded-2xl border border-[var(--border)] p-4 transition hover:border-[var(--text)]"
                  >
                    <p className="font-bold">{field(user, "nickname")}</p>
                    <p className="text-sm text-[var(--muted)]">
                      {field(user, "identity_role")} · {field(membership, "status", i18n("noMembershipb174349"))}
                    </p>
                    <p className="mt-2 text-xs font-bold uppercase tracking-[0.16em] text-[var(--primary)]">
                      {field(membership, "package_code", i18n("openProfile7db8d6d"))}
                    </p>
                  </Link>
                );
              })}
            </div>
          </Panel>

          <Panel title={i18n("promotionCampaignsAndCodesa7ca161")}>
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                createCampaignMutation.mutate();
              }}
            >
              <Input label={i18n("campaignNameaa5d0e7")} value={campaignForm.name} onChange={(name) => setCampaignForm({ ...campaignForm, name })} />
              <Input
                label={i18n("description55f8ebc")}
                required={false}
                value={campaignForm.description}
                onChange={(description) => setCampaignForm({ ...campaignForm, description })}
              />
              <div className="grid gap-3 md:grid-cols-2">
                <Input
                  label={i18n("startsOn6d888f7")}
                  required={false}
                  type="date"
                  value={campaignForm.starts_on}
                  onChange={(starts_on) => setCampaignForm({ ...campaignForm, starts_on })}
                />
                <Input
                  label={i18n("endsOn5c262f3")}
                  required={false}
                  type="date"
                  value={campaignForm.ends_on}
                  onChange={(ends_on) => setCampaignForm({ ...campaignForm, ends_on })}
                />
              </div>
              <Checkbox
                checked={campaignForm.active}
                label={i18n("campaignActive11ce462")}
                onChange={(active) => setCampaignForm({ ...campaignForm, active })}
              />
              <SubmitButton pending={createCampaignMutation.isPending}>{i18n("createCampaign59812bb")}</SubmitButton>
              <ErrorText error={createCampaignMutation.error} />
            </form>

            <form
              className="mt-6 space-y-3 border-t border-[var(--border)] pt-5"
              onSubmit={(event) => {
                event.preventDefault();
                createCodeMutation.mutate();
              }}
            >
              <Select
                label={i18n("campaign69390e1")}
                value={codeForm.campaign_id}
                options={campaigns.map((campaign) => field(campaign, "id"))}
                optionLabel={(id) => field(campaigns.find((campaign) => field(campaign, "id") === id), "name", id)}
                onChange={(campaign_id) => setCodeForm({ ...codeForm, campaign_id })}
              />
              <Input label={i18n("codeadac693")} value={codeForm.code} onChange={(code) => setCodeForm({ ...codeForm, code })} />
              <div className="grid gap-3 md:grid-cols-2">
                <Select
                  label={i18n("discountTypec5137dd")}
                  value={codeForm.discount_type}
                  options={["percent", "fixed_amount", "free_period", "manual"]}
                  onChange={(discount_type) => setCodeForm({ ...codeForm, discount_type })}
                />
                <Input
                  label={i18n("discountValuecfbd2d5")}
                  type="number"
                  value={codeForm.discount_value}
                  onChange={(discount_value) => setCodeForm({ ...codeForm, discount_value })}
                />
              </div>
              <Input
                label={i18n("maximumRedemptions86769db")}
                required={false}
                type="number"
                value={codeForm.max_redemptions}
                onChange={(max_redemptions) => setCodeForm({ ...codeForm, max_redemptions })}
              />
              <Checkbox
                checked={codeForm.active}
                label={i18n("codeActivee55ce6f")}
                onChange={(active) => setCodeForm({ ...codeForm, active })}
              />
              <SubmitButton pending={createCodeMutation.isPending}>{i18n("createCodecdeaf88")}</SubmitButton>
              <ErrorText error={createCodeMutation.error} />
            </form>
          </Panel>
        </section>

        <section className="grid gap-6 xl:grid-cols-2">
          <Panel title={i18n("operationalQueuesc2120a9")}>
            <QueueList title={i18n("expiringMemberships522e6a4")} rows={queues.expiring_memberships ?? []} primary="user_id" secondary="expires_on" />
            <QueueList title={i18n("pendingPaymentsb4ebfb2")} rows={queues.pending_payments ?? []} primary="membership_id" secondary="amount_cents" moneySecondary />
            <QueueList title={i18n("overdueInvoices747a2d8")} rows={queues.overdue_invoices ?? []} primary="invoice_number" secondary="balance_due_cents" moneySecondary />
            <QueueList title={i18n("pendingReferralRewards110afb2")} rows={queues.pending_referral_rewards ?? []} primary="recipient_user_id" secondary="reward_value" />
            <QueueList title={i18n("promoRedemptions7408919")} rows={queues.promotion_redemptions ?? []} primary="membership_id" secondary="discount_value_snapshot" />
          </Panel>

          <Panel title={i18n("referralLifecycleManagementd2d3c90")}>
            <div className="mb-6 grid gap-5 border-b border-[var(--border)] pb-5 lg:grid-cols-[1fr_1.2fr]">
              <form
                className="space-y-3"
                onSubmit={(event) => {
                  event.preventDefault();
                  createReferralProgramMutation.mutate();
                }}
              >
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{i18n("createReferralProgram80d2646")}</p>
                <Input
                  label={i18n("programName699413c")}
                  value={referralProgramForm.name}
                  onChange={(name) => setReferralProgramForm({ ...referralProgramForm, name })}
                />
                <Input
                  label={i18n("description55f8ebc")}
                  required={false}
                  value={referralProgramForm.description}
                  onChange={(description) => setReferralProgramForm({ ...referralProgramForm, description })}
                />
                <div className="grid gap-3 md:grid-cols-2">
                  <Select
                    label={i18n("rewardType9e0f28d")}
                    value={referralProgramForm.reward_type}
                    options={["credit", "discount", "free_period", "manual"]}
                    onChange={(reward_type) => setReferralProgramForm({ ...referralProgramForm, reward_type })}
                  />
                  <Input
                    label={i18n("rewardValue8cb933f")}
                    type="number"
                    value={referralProgramForm.reward_value}
                    onChange={(reward_value) => setReferralProgramForm({ ...referralProgramForm, reward_value })}
                  />
                </div>
                <Checkbox
                  checked={referralProgramForm.active}
                  label={i18n("programActive51f4e1a")}
                  onChange={(active) => setReferralProgramForm({ ...referralProgramForm, active })}
                />
                <SubmitButton pending={createReferralProgramMutation.isPending}>{i18n("createProgram63a76cb")}</SubmitButton>
                <ErrorText error={createReferralProgramMutation.error} />
              </form>

              <div className="grid content-start gap-3">
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{i18n("programsab14d0a")}</p>
                {referralPrograms.length === 0 ? <EmptyState>{i18n("noReferralProgramsYet8445c6c")}</EmptyState> : null}
                {referralPrograms.map((program) => (
                  <div key={field(program, "id")} className="rounded-2xl border border-[var(--border)] p-4">
                    <p className="font-bold">{field(program, "name")}</p>
                    <p className="text-sm text-[var(--muted)]">
                      {field(program, "reward_type")} · {field(program, "reward_value")} ·{" "}
                      {program.active === false ? i18n("inactive09af574") : i18n("activea733b80")}
                    </p>
                  </div>
                ))}
              </div>
            </div>

            <div className="mb-6 grid gap-5 border-b border-[var(--border)] pb-5 lg:grid-cols-2">
              <form
                className="space-y-3"
                onSubmit={(event) => {
                  event.preventDefault();
                  createReferralEventMutation.mutate();
                }}
              >
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{i18n("createReferralEventc3c4f63")}</p>
                <Select
                  label={i18n("referralProgramecbeeaa")}
                  value={referralEventForm.referral_program_id}
                  options={referralPrograms
                    .filter((program) => program.active !== false)
                    .map((program) => field(program, "id"))}
                  optionLabel={(id) =>
                    field(referralPrograms.find((program) => field(program, "id") === id), "name", id)
                  }
                  onChange={(referral_program_id) =>
                    setReferralEventForm({ ...referralEventForm, referral_program_id })
                  }
                />
                <Input
                  label={i18n("searchUsersReferrerReferred4bb924e")}
                  required={false}
                  value={referralUserSearch}
                  onChange={setReferralUserSearch}
                />
                {referralUserSearchReady && referralUserSearchQuery.isLoading ? (
                  <p className="text-xs text-[var(--muted)]">{i18n("searching1a6a5ba")}</p>
                ) : null}
                {referralUserSearchReady && !referralUserSearchQuery.isLoading && referralSearchUsers.length === 0 ? (
                  <p className="text-xs text-[var(--muted)]">{i18n("noMembersOrAthletesFounde70afd0")}</p>
                ) : null}
                <Select
                  label={i18n("referrer548b0b9")}
                  value={referralEventForm.referrer_user_id}
                  options={referralSearchUsers.map((user) => field(user, "id"))}
                  optionLabel={(id) => {
                    const user = referralSearchUsers.find((item) => field(item, "id") === id);
                    return (field(user, "nickname", id)) + " · " + (field(user, "identity_role"));
                  }}
                  onChange={(referrer_user_id) =>
                    setReferralEventForm({ ...referralEventForm, referrer_user_id })
                  }
                />
                <Select
                  label={i18n("referredMember9883a2f")}
                  value={referralEventForm.referred_user_id}
                  options={referralSearchUsers.map((user) => field(user, "id"))}
                  optionLabel={(id) => {
                    const user = referralSearchUsers.find((item) => field(item, "id") === id);
                    const membership = nestedRecord(user, "membership");
                    return (field(user, "nickname", id)) + " · " + (field(user, "identity_role")) + " · " + (field(membership, "status", i18n("noMembershipb174349")));
                  }}
                  onChange={(referred_user_id) => {
                    const user = referralSearchUsers.find((item) => field(item, "id") === referred_user_id);
                    const membership = nestedRecord(user, "membership");
                    setReferralEventForm({
                      ...referralEventForm,
                      referred_user_id,
                      membership_id: field(membership, "id"),
                    });
                  }}
                />
                <p className="rounded-2xl bg-[var(--panel)] p-4 text-sm font-bold text-[var(--muted)]">
                  {i18n("requiredReferredMembership751aa8e")} {field(selectedReferredMembership, "id", i18n("selectAReferredMember7be027f"))}
                </p>
                {!referralUserSearchReady ? (
                  <p className="text-xs font-semibold text-[var(--muted)]">
                    {i18n("typeAtLeast2CharactersToFindRegisteredf0c72cf")}
                  </p>
                ) : null}
                <Input
                  label={i18n("notes7044004")}
                  required={false}
                  value={referralEventForm.notes}
                  onChange={(notes) => setReferralEventForm({ ...referralEventForm, notes })}
                />
                <SubmitButton pending={createReferralEventMutation.isPending} disabled={!canCreateReferralEvent}>
                  {i18n("createReferral459dc41")}
                </SubmitButton>
                <ErrorText error={createReferralEventMutation.error} />
              </form>

              <form
                className="space-y-3"
                onSubmit={(event) => {
                  event.preventDefault();
                  createReferralRewardMutation.mutate();
                }}
              >
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{i18n("createReward4da5168")}</p>
                <Select
                  label={i18n("approvedReferralEvent94e137a")}
                  value={referralRewardForm.referral_event_id}
                  options={rewardableReferralEvents.map((event) => field(event, "id"))}
                  optionLabel={(id) => {
                    const event = rewardableReferralEvents.find((item) => field(item, "id") === id);
                    return (field(event, "referrer_user_id", id)) + " -> " + (field(event, "referred_user_id", id));
                  }}
                  onChange={(referral_event_id) => setReferralRewardForm({ ...referralRewardForm, referral_event_id })}
                />
                <p className="rounded-2xl bg-[var(--panel)] p-4 text-sm font-bold text-[var(--muted)]">
                  {i18n("policyd5a7012")} {field(selectedRewardProgram, "reward_type", i18n("selectAnEvent30b452a"))} ·{" "}
                  {field(selectedRewardProgram, "reward_value", "0")}
                </p>
                <SubmitButton pending={createReferralRewardMutation.isPending}>{i18n("createReward4da5168")}</SubmitButton>
                <ErrorText error={createReferralRewardMutation.error} />
              </form>
            </div>

            <div className="mb-6 grid gap-3 border-b border-[var(--border)] pb-5">
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{i18n("referralEvents8bcf3f4")}</p>
              {referralEvents.length === 0 ? <EmptyState>{i18n("noReferralEventsYeta4b3417")}</EmptyState> : null}
              {referralEvents.slice(0, 8).map((event) => (
                <div key={field(event, "id")} className="rounded-2xl border border-[var(--border)] p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="font-bold">{i18n("eventa4e3090")} {field(event, "status")}</p>
                      <p className="text-sm text-[var(--muted)]">
                        {i18n("referrer548b0b9")} {field(event, "referrer_user_id")} {i18n("referred0d4f978")} {field(event, "referred_user_id")}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {["approved", "applied", "rejected"].map((status) => (
                        <button
                          key={status}
                          className="rounded-full border border-[var(--text)] px-3 py-2 text-xs font-bold uppercase tracking-[0.12em] disabled:opacity-40"
                          disabled={updateReferralEventMutation.isPending || field(event, "status") === status}
                          type="button"
                          onClick={() => updateReferralEventMutation.mutate({ id: field(event, "id"), status })}
                        >
                          {status}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              ))}
              <ErrorText error={updateReferralEventMutation.error} />
            </div>

            <div className="grid gap-3">
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{i18n("referralRewards22d6a91")}</p>
              {rewards.length === 0 ? <EmptyState>{i18n("noReferralRewardsYetf260f84")}</EmptyState> : null}
              {rewards.slice(0, 12).map((reward) => (
                <div key={field(reward, "id")} className="rounded-2xl border border-[var(--border)] p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="font-bold">
                        {field(reward, "reward_type")} · {field(reward, "status")}
                      </p>
                      <p className="text-sm text-[var(--muted)]">
                        {i18n("recipient9034326")} {field(reward, "recipient_user_id")} {i18n("valuef18ab8d")} {field(reward, "reward_value")}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {["approved", "applied", "rejected"].map((status) => (
                        <button
                          key={status}
                          className="rounded-full border border-[var(--text)] px-3 py-2 text-xs font-bold uppercase tracking-[0.12em] disabled:opacity-40"
                          disabled={updateRewardMutation.isPending || field(reward, "status") === status}
                          type="button"
                          onClick={() => updateRewardMutation.mutate({ id: field(reward, "id"), status })}
                        >
                          {status}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              ))}
              <ErrorText error={updateRewardMutation.error} />
            </div>
          </Panel>
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
}: {
  label: string;
  value: string;
  options: string[];
  onChange: (value: string) => void;
  optionLabel?: (value: string) => string;
}) {
  const i18n = useUiTranslations();
  return (
    <label className="block space-y-1 text-sm font-semibold">
      <span>{label}</span>
      <select
        className="w-full rounded-2xl border border-[var(--border)] px-4 py-3"
        required
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="" disabled>
          {i18n("select8598222")} {label.toLowerCase()}
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

function Checkbox({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="flex items-center gap-3 text-sm font-semibold">
      <input
        checked={checked}
        type="checkbox"
        onChange={(event) => onChange(event.target.checked)}
      />
      <span>{label}</span>
    </label>
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
  if (!(error instanceof Error)) return null;
  return <p className="text-sm font-semibold text-[var(--danger)]">{error.message}</p>;
}

function EmptyState({ children }: { children: React.ReactNode }) {
  return <p className="rounded-2xl border border-dashed border-[var(--border)] p-4 text-sm text-[var(--muted)]">{children}</p>;
}

function QueueList({
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
    <div className="mb-5">
      <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{title}</p>
      <div className="mt-2 grid gap-2">
        {rows.length === 0 ? <EmptyState>{i18n("noItems83d7e52")}</EmptyState> : null}
        {rows.slice(0, 5).map((row) => (
          <div key={field(row, "id")} className="rounded-2xl border border-[var(--border)] p-3 text-sm">
            <p className="font-bold">{field(row, primary)}</p>
            <p className="text-[var(--muted)]">
              {secondary.includes("date") || secondary.includes("_on") || secondary.includes("_at")
                ? dateText(row[secondary])
                : moneySecondary
                  ? money(uiLocale, row[secondary])
                  : field(row, secondary)}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
