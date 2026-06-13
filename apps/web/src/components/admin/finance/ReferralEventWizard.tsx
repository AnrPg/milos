"use client";

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
  const { tokens } = useSession();
  const token = tokens?.access_token!;
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

  // Packages — use prop if provided, otherwise fetch once
  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token) && !packagesProp,
    queryFn: () => fetchFinancePackages(token),
  });
  const packages = (
    packagesProp ?? packagesQuery.data?.packages ?? []
  ).filter((p) => field(p, "status") === "active");

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
    mutationFn: () => createReferralReward(token, createdEventId!, {}),
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

  const stepLabel = step === 1 ? "Record referral" : step === 2 ? "Review & decide" : "Issue reward";

  return (
    <SidePanel
      title="New referral event"
      subtitle={`Step ${step} of 3 — ${stepLabel}`}
      onClose={onClose}
    >
      {/* Step indicator */}
      <div className="flex gap-2">
        {([1, 2, 3] as Step[]).map((s) => (
          <div
            key={s}
            className="h-1 flex-1 rounded-full"
            style={{ background: s <= step ? "#d95d39" : "#1a1a28" }}
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
              style={{ color: "#55556a" }}
            >
              Referral program
            </span>
            <select
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
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

          {/* Referrer search */}
          <UserSearchField
            label="Referrer"
            value={form.referrer_user_id}
            prefillUser={prefillReferrerUser}
            token={token}
            onChange={handleReferrerChange}
            excludeUserId={form.referred_user_id || undefined}
          />

          {/* Referee search */}
          <div className="space-y-2">
            <UserSearchField
              label="Referee"
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
                  background: "rgba(224,122,95,0.07)",
                  border: "1px solid rgba(224,122,95,0.25)",
                }}
              >
                <p className="text-xs font-semibold" style={{ color: "#e07a5f" }}>
                  ⚠ This user has no membership.
                </p>

                {!showMembershipSetup ? (
                  <button
                    type="button"
                    onClick={() => setShowMembershipSetup(true)}
                    className="text-xs font-semibold hover:opacity-70 transition-opacity"
                    style={{ color: "#d95d39" }}
                  >
                    Assign a package to continue →
                  </button>
                ) : (
                  <div className="space-y-2">
                    <select
                      value={inlinePackageId}
                      onChange={(e) => setInlinePackageId(e.target.value)}
                      className="w-full rounded-lg px-2 py-1.5 text-xs"
                      style={{
                        background: "#111118",
                        color: "#c0c0d8",
                        border: "1px solid #2a2a3a",
                      }}
                    >
                      <option value="">Select package…</option>
                      {packages.map((pkg) => (
                        <option key={String(pkg.id)} value={String(pkg.id)}>
                          {String(pkg.code)}
                        </option>
                      ))}
                    </select>

                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => assignMembershipMutation.mutate()}
                        disabled={!inlinePackageId || assignMembershipMutation.isPending}
                        className="flex-1 rounded-lg py-1.5 text-xs font-semibold disabled:opacity-40"
                        style={{ background: "#d95d39", color: "#fff" }}
                      >
                        {assignMembershipMutation.isPending ? "Assigning…" : "Assign & continue"}
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setShowMembershipSetup(false);
                          setInlinePackageId("");
                        }}
                        className="rounded-lg px-3 py-1.5 text-xs"
                        style={{ background: "#1a1a28", color: "#55556a" }}
                      >
                        Cancel
                      </button>
                    </div>

                    {assignMembershipMutation.error instanceof Error && (
                      <p className="text-xs" style={{ color: "#e07a5f" }}>
                        {assignMembershipMutation.error.message}
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
              style={{ color: "#55556a" }}
            >
              Notes (optional)
            </span>
            <textarea
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none resize-none"
              style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
              rows={3}
              value={form.notes}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
            />
          </label>

          {/* Summary */}
          <div
            className="rounded-[1.4rem] p-4 space-y-2"
            style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
          >
            <SummaryRow
              label="Referrer"
              value={
                referrerUser
                  ? field(referrerUser, "nickname")
                  : form.referrer_user_id || "Not selected"
              }
            />
            <SummaryRow
              label="Referee"
              value={
                refereeUser
                  ? field(refereeUser, "nickname")
                  : form.referred_user_id || "Not selected"
              }
            />
            <SummaryRow
              label="Membership"
              value={
                form.membership_id
                  ? form.membership_id
                  : form.referred_user_id
                    ? "No membership — assign above"
                    : "Select referee first"
              }
              warn={refereeHasNoMembership}
            />
          </div>

          <button
            className="w-full rounded-full py-3 text-sm font-semibold disabled:opacity-50"
            style={{
              background: canProceedStep1 ? "#F0EDF8" : "#1a1a28",
              color: canProceedStep1 ? "#0A0A0F" : "#55556a",
            }}
            disabled={!canProceedStep1 || createEventMutation.isPending}
            onClick={() => createEventMutation.mutate()}
            type="button"
          >
            {createEventMutation.isPending ? "Recording…" : "Record referral → Step 2"}
          </button>
          {createEventMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "#e07a5f" }}>
              {createEventMutation.error.message}
            </p>
          )}
        </div>
      )}

      {/* ── Step 2 ── */}
      {step === 2 && (
        <div className="space-y-5">
          <div
            className="rounded-[1.4rem] p-4 space-y-3"
            style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
          >
            <p
              className="text-xs font-semibold uppercase tracking-[0.18em]"
              style={{ color: "#55556a" }}
            >
              Referral summary
            </p>
            <SummaryRow label="Program" value={field(selectedProgram, "name")} />
            <SummaryRow
              label="Referrer"
              value={referrerUser ? field(referrerUser, "nickname") : form.referrer_user_id}
            />
            <SummaryRow
              label="Referred"
              value={refereeUser ? field(refereeUser, "nickname") : form.referred_user_id}
            />
            <SummaryRow label="Membership" value={form.membership_id} />
            {form.notes && <SummaryRow label="Notes" value={form.notes} />}
          </div>

          <p className="text-sm leading-6" style={{ color: "#8888aa" }}>
            Approving records this referral as valid and enables reward issuance. Rejecting marks it
            as permanently invalid — no reward can ever be issued for this event.
          </p>

          <div className="flex gap-3">
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "#F0EDF8", color: "#0A0A0F" }}
              disabled={approveEventMutation.isPending || rejectEventMutation.isPending}
              onClick={() => approveEventMutation.mutate()}
              type="button"
            >
              {approveEventMutation.isPending ? "Approving…" : "Approve → Step 3"}
            </button>
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{
                background: "rgba(217,93,57,0.1)",
                border: "1px solid rgba(217,93,57,0.3)",
                color: "#d95d39",
              }}
              disabled={approveEventMutation.isPending || rejectEventMutation.isPending}
              onClick={() => rejectEventMutation.mutate()}
              type="button"
            >
              {rejectEventMutation.isPending ? "Rejecting…" : "Reject (terminal)"}
            </button>
          </div>
          {(approveEventMutation.error ?? rejectEventMutation.error) instanceof Error && (
            <p className="text-sm" style={{ color: "#e07a5f" }}>
              {((approveEventMutation.error ?? rejectEventMutation.error) as Error).message}
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
              background: "rgba(77,184,156,0.07)",
              border: "1px solid rgba(77,184,156,0.2)",
            }}
          >
            <p
              className="text-xs font-semibold uppercase tracking-[0.18em]"
              style={{ color: "#4db89c" }}
            >
              Event approved
            </p>
            <p className="text-sm" style={{ color: "#8888aa" }}>
              Reward policy from{" "}
              <span style={{ color: "#F0EDF8" }}>{field(selectedProgram, "name")}</span>
            </p>
            <SummaryRow label="Reward type" value={field(selectedProgram, "reward_type")} />
            <SummaryRow label="Reward value" value={field(selectedProgram, "reward_value")} />
          </div>

          <p className="text-sm leading-6" style={{ color: "#8888aa" }}>
            Issue the reward now, or skip and create it later from the Rewards section. Skipping does
            not affect the approved event.
          </p>

          <div className="flex gap-3">
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "#F0EDF8", color: "#0A0A0F" }}
              disabled={createRewardMutation.isPending}
              onClick={() => createRewardMutation.mutate()}
              type="button"
            >
              {createRewardMutation.isPending ? "Creating…" : "Create reward"}
            </button>
            <button
              className="flex-1 rounded-full py-3 text-sm font-semibold"
              style={{ background: "#1a1a28", color: "#c0c0d8" }}
              onClick={onClose}
              type="button"
            >
              Skip for now
            </button>
          </div>
          {createRewardMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "#e07a5f" }}>
              {createRewardMutation.error.message}
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
      <span style={{ color: "#55556a" }}>{label}</span>
      <span
        className="text-right font-semibold"
        style={{ color: warn ? "#e07a5f" : "#F0EDF8" }}
      >
        {value || "—"}
      </span>
    </div>
  );
}
