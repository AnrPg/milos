"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  assignFinancePackage,
  createReferralEvent,
  createReferralReward,
  fetchFinancePackages,
  updateReferralEventStatus,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";

type Step = 1 | 2 | 3;

type WizardProps = {
  programs: FinanceRecord[];
  packages?: FinanceRecord[];
  prefillReferrerId?: string;
  prefillReferrerUser?: FinanceRecord | null;
  onClose: () => void;
};

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

export function ReferralEventWizard({
  programs,
  packages: packagesProp,
  prefillReferrerId,
  prefillReferrerUser,
  onClose,
}: WizardProps) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();

  const [step, setStep] = useState<Step>(1);
  const [createdEventId, setCreatedEventId] = useState<string | null>(null);

  const [form, setForm] = useState({
    referral_program_id: field(programs[0], "id"),
    referrer_user_id: prefillReferrerId ?? "",
    referred_user_id: "",
    membership_id: "",
    notes: "",
  });

  const [referrerUser, setReferrerUser] = useState<FinanceRecord | null>(
    prefillReferrerUser ?? null,
  );
  const [refereeUser, setRefereeUser] = useState<FinanceRecord | null>(null);
  const [showMembershipSetup, setShowMembershipSetup] = useState(false);
  const [inlinePackageId, setInlinePackageId] = useState("");

  // Step 3 reward overrides (pre-filled from program defaults)
  const defaultProgram = programs.find((p) => field(p, "id") === form.referral_program_id);
  const [rewardForm, setRewardForm] = useState({
    reward_type: field(defaultProgram, "reward_type") || "manual",
    reward_value: field(defaultProgram, "reward_value") || "0",
  });

  // Packages — use prop if provided, otherwise fetch once
  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token) && !packagesProp,
    queryFn: () => fetchFinancePackages(token),
  });
  const packages = packagesProp ?? packagesQuery.data?.packages ?? [];

  const selectedProgram = programs.find((p) => field(p, "id") === form.referral_program_id);
  const refereeHasNoMembership =
    Boolean(form.referred_user_id) && !form.membership_id;

  const canProceedStep1 = Boolean(
    form.referral_program_id &&
      form.referrer_user_id &&
      form.referred_user_id &&
      form.membership_id,
  );

  // ── Mutations ───────────────────────────────────────────────────────────────

  const assignMembershipMutation = useMutation({
    mutationFn: () =>
      assignFinancePackage(token, form.referred_user_id, {
        membership_package_id: inlinePackageId,
        signup_source: "referral",
      }),
    onSuccess: (data) => {
      const sub = data.package_subscription as FinanceRecord | null | undefined;
      const membershipId = field(sub, "membership_id");
      setForm((f) => ({ ...f, membership_id: membershipId }));
      setShowMembershipSetup(false);
      setInlinePackageId("");
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  const createEventMutation = useMutation({
    mutationFn: () =>
      createReferralEvent(token, {
        referral_program_id: form.referral_program_id,
        referrer_user_id: form.referrer_user_id,
        referred_user_id: form.referred_user_id,
        membership_id: form.membership_id || undefined,
        notes: form.notes,
        signup_source_snapshot: "referral",
      }),
    onSuccess: (data) => {
      setCreatedEventId(field(data.referral_event, "id"));
      setStep(2);
    },
  });

  const approveEventMutation = useMutation({
    mutationFn: () => updateReferralEventStatus(token, createdEventId!, "approved"),
    onSuccess: async () => {
      setStep(3);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
    },
  });

  const rejectEventMutation = useMutation({
    mutationFn: () => updateReferralEventStatus(token, createdEventId!, "rejected"),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
      onClose();
    },
  });

  const createRewardMutation = useMutation({
    mutationFn: () =>
      createReferralReward(token, createdEventId!, {
        reward_type: rewardForm.reward_type,
        reward_value: parseInt(rewardForm.reward_value, 10) || 0,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referral-rewards"] });
      onClose();
    },
  });

  // ── Handlers ────────────────────────────────────────────────────────────────

  function handleReferrerChange(userId: string, user: FinanceRecord | null) {
    setReferrerUser(user);
    setForm((f) => ({ ...f, referrer_user_id: userId }));
  }

  function handleRefereeChange(userId: string, user: FinanceRecord | null) {
    setRefereeUser(user);
    const membership = user?.membership as FinanceRecord | null | undefined;
    const membershipId = field(membership, "id");
    setForm((f) => ({ ...f, referred_user_id: userId, membership_id: membershipId }));
    setShowMembershipSetup(false);
    setInlinePackageId("");
  }

  const stepLabel = step === 1 ? i18n("recordReferral8f024c9") : step === 2 ? i18n("reviewDecide3cb5459") : i18n("issueRewarde61aced");

  return (
    <SidePanel
      title={i18n("newReferralEvent6bb8253")}
      subtitle={i18n("stepdc416e1") + (step) + i18n("of3e3d985f") + (stepLabel)}
      onClose={onClose}
    >
      {/* Step indicator */}
      <div className="flex gap-2">
        {([1, 2, 3] as Step[]).map((s) => (
          <div
            key={s}
            className="h-1 flex-1 rounded-full"
            style={{ background: s <= step ? "var(--primary)" : "var(--border)" }}
          />
        ))}
      </div>

      {/* ── Step 1 ── */}
      {step === 1 && (
        <div className="space-y-5">
          {/* Referral program */}
          <label className="block space-y-1">
            <span
              className="text-xs font-semibold uppercase tracking-[0.18em]"
              style={{ color: "var(--dim)" }}
            >
              {i18n("referralProgramecbeeaa")}
            </span>
            <select
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={form.referral_program_id}
              onChange={(e) => setForm({ ...form, referral_program_id: e.target.value })}
            >
              {programs
                .filter((p) => p.active !== false)
                .map((p) => (
                  <option key={field(p, "id")} value={field(p, "id")}>
                    {field(p, "name")}
                  </option>
                ))}
            </select>
          </label>

          {/* Referrer search — locked when opened from the members table "+" button */}
          <UserSearchField
            label={i18n("referrer548b0b9")}
            value={form.referrer_user_id}
            prefillUser={prefillReferrerUser}
            token={token}
            onChange={handleReferrerChange}
            excludeUserId={form.referred_user_id || undefined}
            locked={Boolean(prefillReferrerId)}
          />

          {/* Referee search */}
          <div className="space-y-2">
            <UserSearchField
              label={i18n("referee5da9b33")}
              value={form.referred_user_id}
              token={token}
              onChange={handleRefereeChange}
              excludeUserId={form.referrer_user_id || undefined}
            />

            {/* Inline membership setup */}
            {refereeHasNoMembership && (
              <div
                className="rounded-xl p-3 space-y-3"
                style={{
                  background: "color-mix(in srgb, var(--primary-strong) 7%, transparent)",
                  border: "1px solid color-mix(in srgb, var(--primary-strong) 25%, transparent)",
                }}
              >
                <p className="text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>
                  {i18n("thisUserHasNoMembership2569632")}
                </p>

                {!showMembershipSetup ? (
                  <button
                    type="button"
                    onClick={() => setShowMembershipSetup(true)}
                    className="text-xs font-semibold hover:opacity-70 transition-opacity"
                    style={{ color: "var(--primary)" }}
                  >
                    {i18n("assignAPackageToContinuec2f9fa5")}
                  </button>
                ) : (
                  <div className="space-y-2">
                    <select
                      value={inlinePackageId}
                      onChange={(e) => setInlinePackageId(e.target.value)}
                      className="w-full rounded-lg px-2 py-1.5 text-xs"
                      style={{
                        background: "var(--panel)",
                        color: "var(--text-soft)",
                        border: "1px solid var(--border-strong)",
                      }}
                    >
                      <option value="">{i18n("selectPackage02bf832")}</option>
                      {packages.map((pkg) => (
                        <option
                          key={String(pkg.id)}
                          value={String(pkg.id)}
                          disabled={pkg.active === false}
                        >
                          {field(pkg, "name", field(pkg, "code"))}
                          {field(pkg, "code") ? "(" + (field(pkg, "code")) + ")" : ""}
                          {pkg.active === false ? i18n("inactive0e9b582") : ""}
                        </option>
                      ))}
                    </select>

                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => assignMembershipMutation.mutate()}
                        disabled={!inlinePackageId || assignMembershipMutation.isPending}
                        className="flex-1 rounded-lg py-1.5 text-xs font-semibold disabled:opacity-40"
                        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                      >
                        {assignMembershipMutation.isPending ? i18n("assigning4d16a1a") : i18n("assignContinue7bfbc41")}
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setShowMembershipSetup(false);
                          setInlinePackageId("");
                        }}
                        className="rounded-lg px-3 py-1.5 text-xs"
                        style={{ background: "var(--border)", color: "var(--dim)" }}
                      >
                        {i18n("cancel77dfd21")}
                      </button>
                    </div>

                    {assignMembershipMutation.error instanceof Error && (
                      <p className="text-xs" style={{ color: "var(--primary-strong)" }}>
                        {localizeError(assignMembershipMutation.error, i18n)}
                      </p>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Notes */}
          <label className="block space-y-1">
            <span
              className="text-xs font-semibold uppercase tracking-[0.18em]"
              style={{ color: "var(--dim)" }}
            >
              {i18n("notesOptional4d56ca9")}
            </span>
            <textarea
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none resize-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              rows={3}
              value={form.notes}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
            />
          </label>

          {/* Summary */}
          <div
            className="rounded-[1.4rem] p-4 space-y-2"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <SummaryRow
              label={i18n("referrer548b0b9")}
              value={
                referrerUser
                  ? field(referrerUser, "nickname")
                  : form.referrer_user_id || i18n("notSelected183079f")
              }
            />
            <SummaryRow
              label={i18n("referee5da9b33")}
              value={
                refereeUser
                  ? field(refereeUser, "nickname")
                  : form.referred_user_id || i18n("notSelected183079f")
              }
            />
            <SummaryRow
              label={i18n("membership53bc967")}
              value={
                form.membership_id
                  ? form.membership_id
                  : form.referred_user_id
                    ? i18n("referralNoMembership")
                    : i18n("selectRefereeFirst")
              }
              warn={refereeHasNoMembership}
            />
          </div>

          <button
            className="w-full rounded-full py-3 text-sm font-semibold disabled:opacity-50"
            style={{
              background: canProceedStep1 ? "var(--text)" : "var(--border)",
              color: canProceedStep1 ? "var(--bg)" : "var(--dim)",
            }}
            disabled={!canProceedStep1 || createEventMutation.isPending}
            onClick={() => createEventMutation.mutate()}
            type="button"
          >
            {createEventMutation.isPending ? i18n("recording72f9eb4") : i18n("recordReferralStep21a166e0")}
          </button>
          {createEventMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>
              {localizeError(createEventMutation.error, i18n)}
            </p>
          )}
        </div>
      )}

      {/* ── Step 2 ── */}
      {step === 2 && (
        <div className="space-y-5">
          <div
            className="rounded-[1.4rem] p-4 space-y-3"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <p
              className="text-xs font-semibold uppercase tracking-[0.18em]"
              style={{ color: "var(--dim)" }}
            >
              {i18n("referralSummary9cd1831")}
            </p>
            <SummaryRow label={i18n("program9d68007")} value={field(selectedProgram, "name")} />
            <SummaryRow
              label={i18n("referrer548b0b9")}
              value={referrerUser ? field(referrerUser, "nickname") : form.referrer_user_id}
            />
            <SummaryRow
              label={i18n("referred57fcdbd")}
              value={refereeUser ? field(refereeUser, "nickname") : form.referred_user_id}
            />
            <SummaryRow label={i18n("membership53bc967")} value={form.membership_id} />
            {form.notes && <SummaryRow label={i18n("notes7044004")} value={form.notes} />}
          </div>

          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
            {i18n("approvingRecordsThisReferralAsValidAndEnablesd66970e")}
          </p>

          <div className="flex gap-3">
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={approveEventMutation.isPending || rejectEventMutation.isPending}
              onClick={() => approveEventMutation.mutate()}
              type="button"
            >
              {approveEventMutation.isPending ? i18n("approving26fb03f") : i18n("approveStep3b5cd569")}
            </button>
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{
                background: "color-mix(in srgb, var(--primary) 10%, transparent)",
                border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)",
                color: "var(--primary)",
              }}
              disabled={approveEventMutation.isPending || rejectEventMutation.isPending}
              onClick={() => rejectEventMutation.mutate()}
              type="button"
            >
              {rejectEventMutation.isPending ? i18n("rejecting812b8d2") : i18n("rejectTerminal4dd8241")}
            </button>
          </div>
          {(approveEventMutation.error ?? rejectEventMutation.error) instanceof Error && (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>
              {localizeError(approveEventMutation.error ?? rejectEventMutation.error, i18n)}
            </p>
          )}
        </div>
      )}

      {/* ── Step 3 ── */}
      {step === 3 && (
        <div className="space-y-5">
          <div
            className="rounded-[1.4rem] p-4 space-y-3"
            style={{
              background: "color-mix(in srgb, var(--success) 7%, transparent)",
              border: "1px solid color-mix(in srgb, var(--success) 20%, transparent)",
            }}
          >
            <p
              className="text-xs font-semibold uppercase tracking-[0.18em]"
              style={{ color: "var(--success)" }}
            >
              {i18n("eventApprovedConfigureRewarda2659ea")}
            </p>
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              {i18n("defaultsFromfa3e989")}{" "}
              <span style={{ color: "var(--text)" }}>{field(selectedProgram, "name")}</span>{i18n("youCanAdjustBeforeIssuing8ba2699")}
            </p>
          </div>

          {/* Editable reward fields */}
          <div className="space-y-3">
            <label className="block space-y-1">
              <span
                className="text-xs font-semibold uppercase tracking-[0.18em]"
                style={{ color: "var(--dim)" }}
              >
                {i18n("rewardType9e0f28d")}
              </span>
              <select
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={rewardForm.reward_type}
                onChange={(e) => setRewardForm({ ...rewardForm, reward_type: e.target.value })}
              >
                <option value="credit">{i18n("credit8a45d33")}</option>
                <option value="discount">{i18n("discountb524936")}</option>
                <option value="free_period">{i18n("freePeriod55f6fa0")}</option>
                <option value="manual">{i18n("manual4e836fd")}</option>
              </select>
            </label>

            {rewardForm.reward_type !== "manual" && (
              <label className="block space-y-1">
                <span
                  className="text-xs font-semibold uppercase tracking-[0.18em]"
                  style={{ color: "var(--dim)" }}
                >
                  {rewardForm.reward_type === "credit"
                    ? i18n("amountCents0a0d9fc")
                    : rewardForm.reward_type === "discount"
                      ? i18n("discountCentsda869a3")
                      : i18n("daysf6bb0f4")}
                </span>
                <input
                  type="number"
                  min={0}
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={rewardForm.reward_value}
                  onChange={(e) => setRewardForm({ ...rewardForm, reward_value: e.target.value })}
                />
              </label>
            )}
          </div>

          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
            {i18n("issueTheRewardNowOrSkipAndCreate614170f")}
          </p>

          <div className="flex gap-3">
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={createRewardMutation.isPending}
              onClick={() => createRewardMutation.mutate()}
              type="button"
            >
              {createRewardMutation.isPending ? i18n("creating94d7d8e") : i18n("createReward4da5168")}
            </button>
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              onClick={onClose}
              type="button"
            >
              {i18n("skipForNow6fc0960")}
            </button>
          </div>
          {createRewardMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>
              {localizeError(createRewardMutation.error, i18n)}
            </p>
          )}
        </div>
      )}
    </SidePanel>
  );
}

function SummaryRow({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 text-sm">
      <span style={{ color: "var(--dim)" }}>{label}</span>
      <span
        className="text-end font-semibold"
        style={{ color: warn ? "var(--primary-strong)" : "var(--text)" }}
      >
        {value || "—"}
      </span>
    </div>
  );
}
