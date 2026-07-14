"use client";

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

function money(cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" }).format(amount / 100);
}

function dateText(value: unknown) {
  if (!value) return "not set";
  return String(value).slice(0, 10);
}

function percent(value: unknown) {
  const amount = typeof value === "number" ? value : Number(value ?? 0);
  return `${amount.toFixed(1)}%`;
}

export function AdminFinance() {
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
    ["Active memberships", String(totals.active_memberships ?? 0)],
    ["Expiring in 30 days", String(totals.expiring_memberships ?? 0)],
    ["Paid revenue", money(totals.paid_revenue_cents)],
    ["Open credit balance", money(totals.credit_balance_cents)],
    ["Outstanding invoices", money(totals.outstanding_invoice_balance_cents)],
    ["Overdue invoices", money(totals.overdue_invoice_balance_cents)],
    ["Renewal conversion", percent(totals.renewal_conversion_percent)],
    ["Invoice credit offsets", money(totals.invoice_credit_offset_cents)],
  ];

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-7xl space-y-8">
        <section className="rounded-[2rem] border border-[var(--border)] bg-[var(--panel)] p-8">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">Finance operations</p>
          <h1 className="mt-3 text-4xl font-black tracking-tight md:text-5xl">Membership revenue cockpit</h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-[var(--muted)]">
            Manage packages, member finance profiles, manual payments, promotions, referral rewards, and operational
            queues from one admin surface.
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
          <h2 className="text-xl font-black">Monthly revenue</h2>
          <div className="mt-4 h-72 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={monthlyRevenue}>
                <CartesianGrid stroke="var(--border)" vertical={false} />
                <XAxis
                  dataKey="period_start"
                  tickFormatter={(value) => String(value).slice(0, 7)}
                />
                <YAxis tickFormatter={(value) => `€${Number(value) / 100}`} />
                <Tooltip
                  labelFormatter={(value) => String(value).slice(0, 7)}
                  formatter={(value) => money(value)}
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
            <h2 className="text-xl font-black">Create membership package</h2>
            <Input label="Package code" value={packageForm.code} onChange={(code) => setPackageForm({ ...packageForm, code })} />
            <Input label="Name" value={packageForm.name} onChange={(name) => setPackageForm({ ...packageForm, name })} />
            <div className="grid gap-3 md:grid-cols-2">
              <Select
                label="Family"
                value={packageForm.family}
                options={["unlimited", "limited-visits", "personal-programming", "hybrid"]}
                onChange={(family) => setPackageForm({ ...packageForm, family })}
              />
              <Select
                label="Billing period"
                value={packageForm.billing_period}
                options={["monthly", "quarterly", "annual", "custom"]}
                onChange={(billing_period) => setPackageForm({ ...packageForm, billing_period })}
              />
            </div>
            <Input
              label="Price in EUR"
              type="number"
              value={packageForm.price}
              onChange={(price) => setPackageForm({ ...packageForm, price })}
            />
            <Input
              label="Tags, comma-separated"
              value={packageForm.tags}
              required={false}
              onChange={(tags) => setPackageForm({ ...packageForm, tags })}
            />
            <SubmitButton pending={createPackageMutation.isPending}>Create package</SubmitButton>
            <ErrorText error={createPackageMutation.error} />
          </form>

          <Panel title="Membership packages">
            <div className="grid gap-3">
              {packages.length === 0 ? <EmptyState>No packages yet.</EmptyState> : null}
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
                    <p className="font-black">{money(item.base_price_cents)}</p>
                  </div>
                </Link>
              ))}
            </div>
          </Panel>
        </section>

        <section className="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
          <Panel title="Member finance profiles">
            <Input label="Search users" required={false} value={search} onChange={setSearch} />
            <div className="mt-4 grid gap-3 md:grid-cols-2">
              {!searchReady ? (
                <p className="rounded-2xl border border-[var(--border)] p-4 text-sm text-[var(--muted)] md:col-span-2">
                  Enter a name to load matching finance profiles.
                </p>
              ) : null}
              {searchReady && !searchQuery.isLoading && users.length === 0 ? (
                <p className="rounded-2xl border border-[var(--border)] p-4 text-sm text-[var(--muted)] md:col-span-2">
                  No matching members found.
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
                      {field(user, "identity_role")} · {field(membership, "status", "no membership")}
                    </p>
                    <p className="mt-2 text-xs font-bold uppercase tracking-[0.16em] text-[var(--primary)]">
                      {field(membership, "package_code", "open profile")}
                    </p>
                  </Link>
                );
              })}
            </div>
          </Panel>

          <Panel title="Promotion campaigns and codes">
            <form
              className="space-y-3"
              onSubmit={(event) => {
                event.preventDefault();
                createCampaignMutation.mutate();
              }}
            >
              <Input label="Campaign name" value={campaignForm.name} onChange={(name) => setCampaignForm({ ...campaignForm, name })} />
              <Input
                label="Description"
                required={false}
                value={campaignForm.description}
                onChange={(description) => setCampaignForm({ ...campaignForm, description })}
              />
              <div className="grid gap-3 md:grid-cols-2">
                <Input
                  label="Starts on"
                  required={false}
                  type="date"
                  value={campaignForm.starts_on}
                  onChange={(starts_on) => setCampaignForm({ ...campaignForm, starts_on })}
                />
                <Input
                  label="Ends on"
                  required={false}
                  type="date"
                  value={campaignForm.ends_on}
                  onChange={(ends_on) => setCampaignForm({ ...campaignForm, ends_on })}
                />
              </div>
              <Checkbox
                checked={campaignForm.active}
                label="Campaign active"
                onChange={(active) => setCampaignForm({ ...campaignForm, active })}
              />
              <SubmitButton pending={createCampaignMutation.isPending}>Create campaign</SubmitButton>
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
                label="Campaign"
                value={codeForm.campaign_id}
                options={campaigns.map((campaign) => field(campaign, "id"))}
                optionLabel={(id) => field(campaigns.find((campaign) => field(campaign, "id") === id), "name", id)}
                onChange={(campaign_id) => setCodeForm({ ...codeForm, campaign_id })}
              />
              <Input label="Code" value={codeForm.code} onChange={(code) => setCodeForm({ ...codeForm, code })} />
              <div className="grid gap-3 md:grid-cols-2">
                <Select
                  label="Discount type"
                  value={codeForm.discount_type}
                  options={["percent", "fixed_amount", "free_period", "manual"]}
                  onChange={(discount_type) => setCodeForm({ ...codeForm, discount_type })}
                />
                <Input
                  label="Discount value"
                  type="number"
                  value={codeForm.discount_value}
                  onChange={(discount_value) => setCodeForm({ ...codeForm, discount_value })}
                />
              </div>
              <Input
                label="Maximum redemptions"
                required={false}
                type="number"
                value={codeForm.max_redemptions}
                onChange={(max_redemptions) => setCodeForm({ ...codeForm, max_redemptions })}
              />
              <Checkbox
                checked={codeForm.active}
                label="Code active"
                onChange={(active) => setCodeForm({ ...codeForm, active })}
              />
              <SubmitButton pending={createCodeMutation.isPending}>Create code</SubmitButton>
              <ErrorText error={createCodeMutation.error} />
            </form>
          </Panel>
        </section>

        <section className="grid gap-6 xl:grid-cols-2">
          <Panel title="Operational queues">
            <QueueList title="Expiring memberships" rows={queues.expiring_memberships ?? []} primary="user_id" secondary="expires_on" />
            <QueueList title="Pending payments" rows={queues.pending_payments ?? []} primary="membership_id" secondary="amount_cents" moneySecondary />
            <QueueList title="Overdue invoices" rows={queues.overdue_invoices ?? []} primary="invoice_number" secondary="balance_due_cents" moneySecondary />
            <QueueList title="Pending referral rewards" rows={queues.pending_referral_rewards ?? []} primary="recipient_user_id" secondary="reward_value" />
            <QueueList title="Promo redemptions" rows={queues.promotion_redemptions ?? []} primary="membership_id" secondary="discount_value_snapshot" />
          </Panel>

          <Panel title="Referral lifecycle management">
            <div className="mb-6 grid gap-5 border-b border-[var(--border)] pb-5 lg:grid-cols-[1fr_1.2fr]">
              <form
                className="space-y-3"
                onSubmit={(event) => {
                  event.preventDefault();
                  createReferralProgramMutation.mutate();
                }}
              >
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">Create referral program</p>
                <Input
                  label="Program name"
                  value={referralProgramForm.name}
                  onChange={(name) => setReferralProgramForm({ ...referralProgramForm, name })}
                />
                <Input
                  label="Description"
                  required={false}
                  value={referralProgramForm.description}
                  onChange={(description) => setReferralProgramForm({ ...referralProgramForm, description })}
                />
                <div className="grid gap-3 md:grid-cols-2">
                  <Select
                    label="Reward type"
                    value={referralProgramForm.reward_type}
                    options={["credit", "discount", "free_period", "manual"]}
                    onChange={(reward_type) => setReferralProgramForm({ ...referralProgramForm, reward_type })}
                  />
                  <Input
                    label="Reward value"
                    type="number"
                    value={referralProgramForm.reward_value}
                    onChange={(reward_value) => setReferralProgramForm({ ...referralProgramForm, reward_value })}
                  />
                </div>
                <Checkbox
                  checked={referralProgramForm.active}
                  label="Program active"
                  onChange={(active) => setReferralProgramForm({ ...referralProgramForm, active })}
                />
                <SubmitButton pending={createReferralProgramMutation.isPending}>Create program</SubmitButton>
                <ErrorText error={createReferralProgramMutation.error} />
              </form>

              <div className="grid content-start gap-3">
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">Programs</p>
                {referralPrograms.length === 0 ? <EmptyState>No referral programs yet.</EmptyState> : null}
                {referralPrograms.map((program) => (
                  <div key={field(program, "id")} className="rounded-2xl border border-[var(--border)] p-4">
                    <p className="font-bold">{field(program, "name")}</p>
                    <p className="text-sm text-[var(--muted)]">
                      {field(program, "reward_type")} · {field(program, "reward_value")} ·{" "}
                      {program.active === false ? "inactive" : "active"}
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
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">Create referral event</p>
                <Select
                  label="Referral program"
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
                  label="Search users (referrer &amp; referred)"
                  required={false}
                  value={referralUserSearch}
                  onChange={setReferralUserSearch}
                />
                {referralUserSearchReady && referralUserSearchQuery.isLoading ? (
                  <p className="text-xs text-[var(--muted)]">Searching…</p>
                ) : null}
                {referralUserSearchReady && !referralUserSearchQuery.isLoading && referralSearchUsers.length === 0 ? (
                  <p className="text-xs text-[var(--muted)]">No members or athletes found.</p>
                ) : null}
                <Select
                  label="Referrer"
                  value={referralEventForm.referrer_user_id}
                  options={referralSearchUsers.map((user) => field(user, "id"))}
                  optionLabel={(id) => {
                    const user = referralSearchUsers.find((item) => field(item, "id") === id);
                    return `${field(user, "nickname", id)} · ${field(user, "identity_role")}`;
                  }}
                  onChange={(referrer_user_id) =>
                    setReferralEventForm({ ...referralEventForm, referrer_user_id })
                  }
                />
                <Select
                  label="Referred member"
                  value={referralEventForm.referred_user_id}
                  options={referralSearchUsers.map((user) => field(user, "id"))}
                  optionLabel={(id) => {
                    const user = referralSearchUsers.find((item) => field(item, "id") === id);
                    const membership = nestedRecord(user, "membership");
                    return `${field(user, "nickname", id)} · ${field(user, "identity_role")} · ${field(membership, "status", "no membership")}`;
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
                  Required referred membership: {field(selectedReferredMembership, "id", "select a referred member")}
                </p>
                {!referralUserSearchReady ? (
                  <p className="text-xs font-semibold text-[var(--muted)]">
                    Type at least 2 characters to find registered users.
                  </p>
                ) : null}
                <Input
                  label="Notes"
                  required={false}
                  value={referralEventForm.notes}
                  onChange={(notes) => setReferralEventForm({ ...referralEventForm, notes })}
                />
                <SubmitButton pending={createReferralEventMutation.isPending} disabled={!canCreateReferralEvent}>
                  Create referral
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
                <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">Create reward</p>
                <Select
                  label="Approved referral event"
                  value={referralRewardForm.referral_event_id}
                  options={rewardableReferralEvents.map((event) => field(event, "id"))}
                  optionLabel={(id) => {
                    const event = rewardableReferralEvents.find((item) => field(item, "id") === id);
                    return `${field(event, "referrer_user_id", id)} -> ${field(event, "referred_user_id", id)}`;
                  }}
                  onChange={(referral_event_id) => setReferralRewardForm({ ...referralRewardForm, referral_event_id })}
                />
                <p className="rounded-2xl bg-[var(--panel)] p-4 text-sm font-bold text-[var(--muted)]">
                  Policy: {field(selectedRewardProgram, "reward_type", "select an event")} ·{" "}
                  {field(selectedRewardProgram, "reward_value", "0")}
                </p>
                <SubmitButton pending={createReferralRewardMutation.isPending}>Create reward</SubmitButton>
                <ErrorText error={createReferralRewardMutation.error} />
              </form>
            </div>

            <div className="mb-6 grid gap-3 border-b border-[var(--border)] pb-5">
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">Referral events</p>
              {referralEvents.length === 0 ? <EmptyState>No referral events yet.</EmptyState> : null}
              {referralEvents.slice(0, 8).map((event) => (
                <div key={field(event, "id")} className="rounded-2xl border border-[var(--border)] p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="font-bold">Event · {field(event, "status")}</p>
                      <p className="text-sm text-[var(--muted)]">
                        Referrer {field(event, "referrer_user_id")} · Referred {field(event, "referred_user_id")}
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
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">Referral rewards</p>
              {rewards.length === 0 ? <EmptyState>No referral rewards yet.</EmptyState> : null}
              {rewards.slice(0, 12).map((reward) => (
                <div key={field(reward, "id")} className="rounded-2xl border border-[var(--border)] p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="font-bold">
                        {field(reward, "reward_type")} · {field(reward, "status")}
                      </p>
                      <p className="text-sm text-[var(--muted)]">
                        Recipient {field(reward, "recipient_user_id")} · Value {field(reward, "reward_value")}
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
          Select {label.toLowerCase()}
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
  return (
    <button
      className="rounded-full bg-[var(--text)] px-5 py-3 text-sm font-bold text-[var(--primary-contrast)] disabled:opacity-50"
      disabled={pending || disabled}
      type="submit"
    >
      {pending ? "Saving..." : children}
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
  return (
    <div className="mb-5">
      <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{title}</p>
      <div className="mt-2 grid gap-2">
        {rows.length === 0 ? <EmptyState>No items.</EmptyState> : null}
        {rows.slice(0, 5).map((row) => (
          <div key={field(row, "id")} className="rounded-2xl border border-[var(--border)] p-3 text-sm">
            <p className="font-bold">{field(row, primary)}</p>
            <p className="text-[var(--muted)]">
              {secondary.includes("date") || secondary.includes("_on") || secondary.includes("_at")
                ? dateText(row[secondary])
                : moneySecondary
                  ? money(row[secondary])
                  : field(row, secondary)}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
