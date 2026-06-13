"use client";

import { useCallback, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";

import {
  assignFinancePackage,
  fetchFinanceMembers,
  fetchFinancePackages,
  fetchReferralPrograms,
  updateFinanceMember,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { InlineCell, InlineToggle } from "@/components/admin/finance/shared/InlineCell";
import { Combobox, type ComboboxOption } from "@/components/admin/finance/shared/Combobox";
import { MemberPanel } from "@/components/admin/finance/panels/MemberPanel";
import { ReferralEventWizard } from "@/components/admin/finance/ReferralEventWizard";
import { InlineAssignPackage } from "@/components/admin/finance/shared/InlineAssignPackage";
import { SortableHeader } from "@/components/admin/finance/shared/SortableHeader";
import {
  useSortFilter,
  type ColumnKey,
  type FilterValue,
} from "@/components/admin/finance/hooks/useSortFilter";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function expiresWarn(expiresOn: string): boolean {
  if (!expiresOn) return false;
  const diff = new Date(expiresOn).getTime() - Date.now();
  return diff > 0 && diff < 30 * 24 * 60 * 60 * 1000;
}

const MEMBERSHIP_STATUS_OPTIONS = [
  { value: "active", label: "Active", accent: true },
  { value: "trial", label: "Trial" },
  { value: "expiring", label: "Expiring" },
  { value: "expired", label: "Expired" },
  { value: "comped", label: "Comped" },
  { value: "paused", label: "Paused" },
];

const EUR = new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" });

// ── Reusable filter UI helpers ────────────────────────────────────────────────

function PillGroup({
  options,
  value,
  onSelect,
}: {
  options: { label: string; value: string }[];
  value: string;
  onSelect: (v: string) => void;
}) {
  return (
    <div className="flex flex-wrap gap-1">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          onClick={() => onSelect(o.value === value ? "" : o.value)}
          className="rounded-full px-2 py-0.5 text-xs font-semibold transition-colors"
          style={
            o.value === value
              ? { background: "#d95d39", color: "#fff" }
              : { background: "#1a1a28", color: "#55556a" }
          }
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function MultiCheck({
  options,
  values,
  onChange,
}: {
  options: { label: string; value: string }[];
  values: string[];
  onChange: (values: string[]) => void;
}) {
  function toggle(v: string) {
    onChange(values.includes(v) ? values.filter((x) => x !== v) : [...values, v]);
  }
  return (
    <div className="space-y-1">
      {options.map((o) => (
        <label key={o.value} className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={values.includes(o.value)}
            onChange={() => toggle(o.value)}
            className="accent-[#d95d39]"
          />
          <span className="text-xs" style={{ color: "#c0c0d8" }}>
            {o.label}
          </span>
        </label>
      ))}
    </div>
  );
}

// ── MembersTab ────────────────────────────────────────────────────────────────

export function MembersTab() {
  const { tokens } = useSession();
  const token = tokens?.access_token!;
  const queryClient = useQueryClient();
  const router = useRouter();
  const searchParams = useSearchParams();

  const openMemberId = searchParams.get("member");
  const showReferralWizard = searchParams.get("new-referral") === "true";
  const prefillReferrerId = searchParams.get("referrer") ?? undefined;

  const setParam = useCallback(
    (updates: Record<string, string | null>) => {
      const params = new URLSearchParams(searchParams.toString());
      Object.entries(updates).forEach(([k, v]) => {
        if (v === null) params.delete(k);
        else params.set(k, v);
      });
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  const membersQuery = useQuery({
    queryKey: ["admin", "finance", "members"],
    enabled: Boolean(token),
    queryFn: () => fetchFinanceMembers(token),
  });

  const referralProgramsQuery = useQuery({
    queryKey: ["admin", "finance", "referral-programs"],
    enabled: Boolean(token),
    queryFn: () => fetchReferralPrograms(token),
  });

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token),
  });

  const members = membersQuery.data?.members ?? [];
  const referralPrograms = referralProgramsQuery.data?.referral_programs ?? [];
  const packages = (packagesQuery.data?.packages ?? []).filter(
    (p) => field(p, "status") === "active",
  );

  const { sort, cycleSort, filters, setFilter, clearFilters, result: filteredMembers } =
    useSortFilter(members);

  const [userQuery, setUserQuery] = useState("");

  const updateMutation = useMutation({
    mutationFn: ({ userId, body }: { userId: string; body: FinanceRecord }) =>
      updateFinanceMember(token, userId, body),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  const assignPackageMutation = useMutation({
    mutationFn: ({ userId, packageId }: { userId: string; packageId: string }) =>
      assignFinancePackage(token, userId, { membership_package_id: packageId }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  function userOptions(): ComboboxOption[] {
    const q = userQuery.toLowerCase();
    const filtered =
      q.length < 1
        ? members
        : members.filter((u) => field(u, "nickname").toLowerCase().includes(q));
    return filtered.slice(0, 30).map((u) => ({
      value: field(u, "id"),
      label: field(u, "nickname"),
      sublabel: field(u, "identity_role"),
    }));
  }

  const openMember = members.find((m) => field(m, "id") === openMemberId) ?? null;
  const prefillUser = prefillReferrerId
    ? (members.find((m) => field(m, "id") === prefillReferrerId) ?? null)
    : null;

  // ── Unique filter option lists ──────────────────────────────────────────────
  const uniqueStatuses = Array.from(
    new Set(members.map((m) => field(m.membership as FinanceRecord, "status")).filter(Boolean)),
  );
  const uniquePlanCodes = Array.from(
    new Set(
      members
        .map((m) => field(m.active_package_subscription as FinanceRecord, "package_code_snapshot"))
        .filter(Boolean),
    ),
  );

  // ── Helper to build SortableHeader filterSlot ─────────────────────────────
  function presenceFilter(col: ColumnKey, hasLabel: string, noneLabel: string): ReactNode {
    const fv = filters[col] as { kind: "presence"; value: string } | undefined;
    return (
      <PillGroup
        options={[
          { label: hasLabel, value: "has" },
          { label: noneLabel, value: "none" },
        ]}
        value={fv?.value ?? ""}
        onSelect={(v) =>
          v
            ? setFilter(col, { kind: "presence", value: v as "has" | "none" })
            : setFilter(col, undefined)
        }
      />
    );
  }

  function datePresetFilter(
    col: ColumnKey,
    presets: { label: string; value: string }[],
  ): ReactNode {
    const fv = filters[col] as { kind: "date_preset"; preset: string } | undefined;
    return (
      <PillGroup
        options={presets}
        value={fv?.preset ?? ""}
        onSelect={(v) =>
          v
            ? setFilter(col, { kind: "date_preset", preset: v })
            : setFilter(col, undefined)
        }
      />
    );
  }

  if (membersQuery.isLoading) {
    return (
      <p className="px-6 py-10 text-sm" style={{ color: "#55556a" }}>
        Loading members…
      </p>
    );
  }

  const hasActiveFilters = Object.keys(filters).length > 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p
          className="text-sm font-semibold uppercase tracking-[0.22em]"
          style={{ color: "#55556a" }}
        >
          {filteredMembers.length === members.length
            ? `${members.length} member${members.length !== 1 ? "s" : ""}`
            : `${filteredMembers.length} / ${members.length} members`}
        </p>
        {hasActiveFilters && (
          <button
            type="button"
            onClick={clearFilters}
            className="text-xs hover:opacity-70 transition-opacity"
            style={{ color: "#d95d39" }}
          >
            Clear filters
          </button>
        )}
      </div>

      <div
        className="rounded-[2rem] overflow-hidden"
        style={{ background: "#111118", border: "1px solid #1a1a28" }}
      >
        <div className="overflow-x-auto">
          <table className="w-full border-collapse" style={{ minWidth: "1400px" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid #1a1a28" }}>
                {/* Nickname — sticky */}
                <SortableHeader
                  column="nickname"
                  label="Nickname"
                  sort={sort}
                  hasFilter={Boolean(filters.nickname)}
                  onSort={() => cycleSort("nickname")}
                  filterSlot={
                    <input
                      type="text"
                      placeholder="Search…"
                      value={(filters.nickname as { kind: "text"; value: string } | undefined)?.value ?? ""}
                      onChange={(e) =>
                        e.target.value
                          ? setFilter("nickname", { kind: "text", value: e.target.value })
                          : setFilter("nickname", undefined)
                      }
                      className="w-full rounded-lg px-2 py-1 text-xs"
                      style={{ background: "#111118", color: "#c0c0d8", border: "1px solid #2a2a3a" }}
                    />
                  }
                />
                <SortableHeader
                  column="type"
                  label="Type"
                  sort={sort}
                  hasFilter={Boolean(filters.type)}
                  onSort={() => cycleSort("type")}
                  filterSlot={
                    <MultiCheck
                      options={["athlete", "member"].map((v) => ({ label: v, value: v }))}
                      values={(filters.type as { kind: "multi"; values: string[] } | undefined)?.values ?? []}
                      onChange={(vals) =>
                        vals.length
                          ? setFilter("type", { kind: "multi", values: vals })
                          : setFilter("type", undefined)
                      }
                    />
                  }
                />
                <SortableHeader
                  column="status"
                  label="Status"
                  sort={sort}
                  hasFilter={Boolean(filters.status)}
                  onSort={() => cycleSort("status")}
                  filterSlot={
                    <MultiCheck
                      options={uniqueStatuses.map((v) => ({ label: v, value: v }))}
                      values={(filters.status as { kind: "multi"; values: string[] } | undefined)?.values ?? []}
                      onChange={(vals) =>
                        vals.length
                          ? setFilter("status", { kind: "multi", values: vals })
                          : setFilter("status", undefined)
                      }
                    />
                  }
                />
                <SortableHeader
                  column="plan"
                  label="Plan"
                  sort={sort}
                  hasFilter={Boolean(filters.plan)}
                  onSort={() => cycleSort("plan")}
                  filterSlot={
                    <MultiCheck
                      options={[
                        { label: "None", value: "__none__" },
                        ...uniquePlanCodes.map((v) => ({ label: v, value: v })),
                      ]}
                      values={(filters.plan as { kind: "multi"; values: string[] } | undefined)?.values ?? []}
                      onChange={(vals) =>
                        vals.length
                          ? setFilter("plan", { kind: "multi", values: vals })
                          : setFilter("plan", undefined)
                      }
                    />
                  }
                />
                <SortableHeader
                  column="expires"
                  label="Expires"
                  sort={sort}
                  hasFilter={Boolean(filters.expires)}
                  onSort={() => cycleSort("expires")}
                  filterSlot={datePresetFilter("expires", [
                    { label: "Expired", value: "expired" },
                    { label: "Next 30d", value: "next_30d" },
                    { label: "No expiry", value: "no_expiry" },
                  ])}
                />
                <SortableHeader
                  column="last_paid"
                  label="Last paid"
                  sort={sort}
                  hasFilter={Boolean(filters.last_paid)}
                  onSort={() => cycleSort("last_paid")}
                  filterSlot={datePresetFilter("last_paid", [
                    { label: "Never", value: "never" },
                    { label: "Last 30d", value: "last_30d" },
                    { label: "Last 90d", value: "last_90d" },
                  ])}
                />
                <SortableHeader
                  column="amount"
                  label="Amount"
                  sort={sort}
                  hasFilter={Boolean(filters.amount)}
                  onSort={() => cycleSort("amount")}
                  filterSlot={presenceFilter("amount", "Has payment", "No payment")}
                />
                <SortableHeader
                  column="credits"
                  label="Credits"
                  sort={sort}
                  hasFilter={Boolean(filters.credits)}
                  onSort={() => cycleSort("credits")}
                  filterSlot={
                    <PillGroup
                      options={[
                        { label: "Has credits", value: "positive" },
                        { label: "Owes credits", value: "negative" },
                      ]}
                      value={(filters.credits as { kind: "sign"; value: string } | undefined)?.value ?? ""}
                      onSelect={(v) =>
                        v
                          ? setFilter("credits", { kind: "sign", value: v as "positive" | "negative" })
                          : setFilter("credits", undefined)
                      }
                    />
                  }
                />
                <SortableHeader
                  column="notes"
                  label="Notes"
                  sort={sort}
                  hasFilter={Boolean(filters.notes)}
                  onSort={() => cycleSort("notes")}
                  filterSlot={presenceFilter("notes", "Has notes", "Empty")}
                />
                <SortableHeader
                  column="referred_by"
                  label="Referred By"
                  sort={sort}
                  hasFilter={Boolean(filters.referred_by)}
                  onSort={() => cycleSort("referred_by")}
                  filterSlot={presenceFilter("referred_by", "Has referrer", "None")}
                />
                <SortableHeader
                  column="referrals"
                  label="Referrals"
                  sort={sort}
                  hasFilter={Boolean(filters.referrals)}
                  onSort={() => cycleSort("referrals")}
                  filterSlot={presenceFilter("referrals", "Made referrals", "None")}
                />
              </tr>
            </thead>
            <tbody>
              {filteredMembers.length === 0 ? (
                <tr>
                  <td colSpan={11} className="px-6 py-8 text-sm" style={{ color: "#55556a" }}>
                    {members.length === 0 ? "No members yet." : "No members match the active filters."}
                  </td>
                </tr>
              ) : (
                filteredMembers.map((member, i) => (
                  <MemberRow
                    key={field(member, "id")}
                    member={member}
                    last={i === filteredMembers.length - 1}
                    packages={packages}
                    userOptions={userOptions()}
                    onUserSearch={setUserQuery}
                    updatePending={updateMutation.isPending}
                    assignPending={assignPackageMutation.isPending}
                    onSave={(body) => updateMutation.mutate({ userId: field(member, "id"), body })}
                    onAssignPackage={(packageId) =>
                      assignPackageMutation.mutate({ userId: field(member, "id"), packageId })
                    }
                    onOpenPanel={() => setParam({ member: field(member, "id"), tab: "members" })}
                    onOpenReferralWizard={() =>
                      setParam({ "new-referral": "true", referrer: field(member, "id") })
                    }
                  />
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {openMember ? (
        <MemberPanel
          userId={field(openMember, "id")}
          nickname={field(openMember, "nickname")}
          onClose={() => setParam({ member: null })}
        />
      ) : null}

      {showReferralWizard ? (
        <ReferralEventWizard
          programs={referralPrograms}
          packages={packages}
          prefillReferrerUser={prefillUser}
          prefillReferrerId={prefillReferrerId}
          onClose={() => setParam({ "new-referral": null, referrer: null })}
        />
      ) : null}
    </div>
  );
}

// ── MemberRow ─────────────────────────────────────────────────────────────────

function MemberRow({
  member,
  last,
  packages,
  userOptions,
  onUserSearch,
  updatePending,
  assignPending,
  onSave,
  onAssignPackage,
  onOpenPanel,
  onOpenReferralWizard,
}: {
  member: FinanceRecord;
  last: boolean;
  packages: FinanceRecord[];
  userOptions: ComboboxOption[];
  onUserSearch: (q: string) => void;
  updatePending: boolean;
  assignPending: boolean;
  onSave: (body: FinanceRecord) => void;
  onAssignPackage: (packageId: string) => void;
  onOpenPanel: () => void;
  onOpenReferralWizard: () => void;
}) {
  const membership = member.membership as FinanceRecord | null | undefined;
  const activeSub = member.active_package_subscription as FinanceRecord | null | undefined;
  const referralsMade = (member.referrals_made_user_ids as string[]) ?? [];

  const expiresOn = field(activeSub, "ends_on") || field(membership, "expires_on");
  const membershipStatus = field(membership, "status", "trial");
  const referredById = field(membership, "referred_by_user_id");
  const creditCents = typeof member.credit_balance === "number" ? member.credit_balance : 0;
  const userType = field(membership, "user_type_snapshot") || field(member, "identity_role");
  const currentPlanCode = activeSub ? field(activeSub, "package_code_snapshot") || null : null;
  const lastPaidOn = field(member, "last_payment_on");
  const lastPaidCents =
    typeof member.last_payment_amount_cents === "number" ? member.last_payment_amount_cents : null;
  const notes = field(member, "notes");

  const borderStyle = last ? undefined : "1px solid #1a1a28";

  return (
    <tr style={{ borderBottom: borderStyle }}>
      {/* Nickname — sticky, opens detail panel */}
      <td className="sticky left-0 z-10 px-4 py-3" style={{ background: "#111118" }}>
        <button
          className="text-sm font-semibold text-left hover:opacity-70 transition-opacity"
          style={{ color: "#F0EDF8" }}
          onClick={onOpenPanel}
          type="button"
        >
          {field(member, "nickname")}
        </button>
      </td>

      {/* Type */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {userType ? (
          <span
            className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-wider"
            style={{
              background:
                userType === "athlete" ? "rgba(217,93,57,0.12)" : "rgba(136,136,170,0.12)",
              color: userType === "athlete" ? "#d95d39" : "#8888aa",
            }}
          >
            {userType}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Status */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineToggle
          value={membershipStatus}
          options={MEMBERSHIP_STATUS_OPTIONS}
          onSave={(status) => onSave({ status })}
        />
      </td>

      {/* Plan — inline assign */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineAssignPackage
          userId={field(member, "id")}
          currentCode={currentPlanCode}
          packages={packages}
          pending={assignPending}
          onAssign={onAssignPackage}
        />
      </td>

      {/* Expires */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineCell
          value={expiresOn}
          type="date"
          onSave={(expires_on) => onSave({ expires_on })}
          placeholder="No expiry"
          warn={expiresWarn(expiresOn)}
          dimmed={!expiresOn}
        />
      </td>

      {/* Last paid */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {lastPaidOn ? (
          <span className="text-xs" style={{ color: "#c0c0d8" }}>
            {lastPaidOn}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Amount */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {lastPaidCents !== null ? (
          <span className="text-xs font-semibold" style={{ color: "#c0c0d8" }}>
            {EUR.format(lastPaidCents / 100)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Credits */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {creditCents !== 0 ? (
          <span
            className="text-xs font-semibold"
            style={{ color: creditCents > 0 ? "#4db89c" : "#e07a5f" }}
          >
            {EUR.format(creditCents / 100)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "#3a3a55" }}>—</span>
        )}
      </td>

      {/* Notes */}
      <td className="px-4 py-3" style={{ minWidth: "140px" }}>
        <InlineCell
          value={notes}
          type="text"
          onSave={(n) => onSave({ notes: n })}
          placeholder="Add note…"
          dimmed={!notes}
        />
      </td>

      {/* Referred By */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <Combobox
          value={referredById}
          placeholder="None"
          options={userOptions}
          onSearch={onUserSearch}
          onChange={(id) => onSave({ referred_by_user_id: id || null })}
          nullable
        />
      </td>

      {/* Referrals Made */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <div className="flex items-center gap-2">
          {referralsMade.length > 0 ? (
            <span className="text-xs font-semibold" style={{ color: "#c0c0d8" }}>
              {referralsMade.length}
            </span>
          ) : (
            <span className="text-xs" style={{ color: "#3a3a55" }}>0</span>
          )}
          <button
            className="rounded-full px-2 py-0.5 text-xs font-semibold"
            style={{
              background: "rgba(217,93,57,0.1)",
              border: "1px solid rgba(217,93,57,0.2)",
              color: "#d95d39",
            }}
            onClick={onOpenReferralWizard}
            disabled={updatePending}
            type="button"
            title="Record new referral"
          >
            +
          </button>
        </div>
      </td>
    </tr>
  );
}
