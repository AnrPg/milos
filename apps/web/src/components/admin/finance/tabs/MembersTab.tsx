"use client";






import {useUiTranslations} from "@/i18n/ui";
import {useUiLocale} from "@/i18n/use-ui-locale";
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
import { SemanticLabel } from "@/components/semantic-label";
import { semanticLabel } from "@/i18n/presentation";
import { MemberPanel } from "@/components/admin/finance/panels/MemberPanel";
import { ReferralEventWizard } from "@/components/admin/finance/ReferralEventWizard";
import { InlineAssignPackage } from "@/components/admin/finance/shared/InlineAssignPackage";
import { SortableHeader } from "@/components/admin/finance/shared/SortableHeader";
import {
  useSortFilter,
  type ColumnKey,
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
              ? { background: "var(--primary)", color: "var(--primary-contrast)" }
              : { background: "var(--border)", color: "var(--dim)" }
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
            className="accent-[var(--primary)]"
          />
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>
            {o.label}
          </span>
        </label>
      ))}
    </div>
  );
}

// ── MembersTab ────────────────────────────────────────────────────────────────

export function MembersTab() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
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
  const packages = packagesQuery.data?.packages ?? [];

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
      sublabel: semanticLabel(field(u, "identity_role"), i18n),
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
      <p className="px-6 py-10 text-sm" style={{ color: "var(--dim)" }}>
        {i18n("loadingMembers402901a")}
      </p>
    );
  }

  const hasActiveFilters = Object.keys(filters).length > 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p
          className="text-sm font-semibold uppercase tracking-[0.22em]"
          style={{ color: "var(--dim)" }}
        >
          {filteredMembers.length === members.length
            ? i18n("memberCount", {count: members.length})
            : i18n("filteredMemberCount", {filtered: filteredMembers.length, total: members.length})}
        </p>
        {hasActiveFilters && (
          <button
            type="button"
            onClick={clearFilters}
            className="text-xs hover:opacity-70 transition-opacity"
            style={{ color: "var(--primary)" }}
          >
            {i18n("clearFilters4122267")}
          </button>
        )}
      </div>

      <div
        className="rounded-[2rem] overflow-hidden"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="overflow-x-auto">
          <table className="w-full border-collapse" style={{ minWidth: "1400px" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--border)" }}>
                {/* Nickname — sticky */}
                <SortableHeader
                  column="nickname"
                  label={i18n("nicknamece2bd99")}
                  sort={sort}
                  hasFilter={Boolean(filters.nickname)}
                  onSort={() => cycleSort("nickname")}
                  filterSlot={
                    <input
                      type="text"
                      placeholder={i18n("searchf54fbca")}
                      value={(filters.nickname as { kind: "text"; value: string } | undefined)?.value ?? ""}
                      onChange={(e) =>
                        e.target.value
                          ? setFilter("nickname", { kind: "text", value: e.target.value })
                          : setFilter("nickname", undefined)
                      }
                      className="w-full rounded-lg px-2 py-1 text-xs"
                      style={{ background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }}
                    />
                  }
                />
                <SortableHeader
                  column="type"
                  label={i18n("type3deb745")}
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
                  label={i18n("statusbae7d5b")}
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
                  label={i18n("planae2f98a")}
                  sort={sort}
                  hasFilter={Boolean(filters.plan)}
                  onSort={() => cycleSort("plan")}
                  filterSlot={
                    <MultiCheck
                      options={[
                        { label: i18n("none6eef664"), value: "__none__" },
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
                  label={i18n("expiresa99be3d")}
                  sort={sort}
                  hasFilter={Boolean(filters.expires)}
                  onSort={() => cycleSort("expires")}
                  filterSlot={datePresetFilter("expires", [
                    { label: i18n("expireda689a99"), value: "expired" },
                    { label: i18n("next30d1a7b0bd"), value: "next_30d" },
                    { label: i18n("noExpiry39d436a"), value: "no_expiry" },
                  ])}
                />
                <SortableHeader
                  column="last_paid"
                  label={i18n("lastPaid05b910a")}
                  sort={sort}
                  hasFilter={Boolean(filters.last_paid)}
                  onSort={() => cycleSort("last_paid")}
                  filterSlot={datePresetFilter("last_paid", [
                    { label: i18n("never80c3052"), value: "never" },
                    { label: i18n("last30d5ef79d5"), value: "last_30d" },
                    { label: i18n("last90d8c9f9e6"), value: "last_90d" },
                  ])}
                />
                <SortableHeader
                  column="amount"
                  label={i18n("amount43dc853")}
                  sort={sort}
                  hasFilter={Boolean(filters.amount)}
                  onSort={() => cycleSort("amount")}
                  filterSlot={presenceFilter("amount", i18n("hasPaymentd3b5c9e"), i18n("noPayment63104bf"))}
                />
                <SortableHeader
                  column="credits"
                  label={i18n("creditsbfac50d")}
                  sort={sort}
                  hasFilter={Boolean(filters.credits)}
                  onSort={() => cycleSort("credits")}
                  filterSlot={
                    <PillGroup
                      options={[
                        { label: i18n("hasCredits2c1970f"), value: "positive" },
                        { label: i18n("owesCredits8f977d5"), value: "negative" },
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
                  column="balance_due"
                  label={i18n("balanceDue5a6bd4c")}
                  sort={sort}
                  hasFilter={Boolean(filters.balance_due)}
                  onSort={() => cycleSort("balance_due")}
                  filterSlot={presenceFilter("balance_due", i18n("hasBalanceDue2379e94"), i18n("settled7fb3a9b"))}
                />
                <SortableHeader
                  column="notes"
                  label={i18n("notes7044004")}
                  sort={sort}
                  hasFilter={Boolean(filters.notes)}
                  onSort={() => cycleSort("notes")}
                  filterSlot={presenceFilter("notes", i18n("hasNotesf0af50f"), i18n("empty3159fe4"))}
                />
                <SortableHeader
                  column="referred_by"
                  label={i18n("referredByb47f784")}
                  sort={sort}
                  hasFilter={Boolean(filters.referred_by)}
                  onSort={() => cycleSort("referred_by")}
                  filterSlot={presenceFilter("referred_by", i18n("hasReferrer0bf42e5"), i18n("none6eef664"))}
                />
                <SortableHeader
                  column="referrals"
                  label={i18n("referrals2b0e3a3")}
                  sort={sort}
                  hasFilter={Boolean(filters.referrals)}
                  onSort={() => cycleSort("referrals")}
                  filterSlot={presenceFilter("referrals", i18n("madeReferralsbe27ef7"), i18n("none6eef664"))}
                />
              </tr>
            </thead>
            <tbody>
              {filteredMembers.length === 0 ? (
                <tr>
                  <td colSpan={12} className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>
                    {members.length === 0 ? i18n("noMembersYetea27c45") : i18n("noMembersMatchTheActiveFilters14acbb5")}
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
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const eur = new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" });
  const membershipStatusOptions = [
    { value: "active", label: i18n("activea733b80"), accent: true },
    { value: "trial", label: i18n("trial5f7537c") },
    { value: "expiring", label: i18n("expiringb98d672") },
    { value: "expired", label: i18n("expireda689a99") },
    { value: "comped", label: i18n("comped1945ffe") },
    { value: "paused", label: i18n("pausedc7dfb6f") },
  ];
  const membership = member.membership as FinanceRecord | null | undefined;
  const activeSub = member.active_package_subscription as FinanceRecord | null | undefined;
  const referralsMade = (member.referrals_made_user_ids as string[]) ?? [];

  const expiresOn = field(activeSub, "ends_on") || field(membership, "expires_on");
  const membershipStatus = field(membership, "status", "trial");
  const referredById = field(membership, "referred_by_user_id");
  const creditCents =
    typeof member.credit_balance === "number"
      ? member.credit_balance
      : typeof member.credit_balance_cents === "number"
        ? member.credit_balance_cents
        : 0;
  const outstandingCents =
    typeof member.outstanding_balance_cents === "number" ? member.outstanding_balance_cents : 0;
  const userType = field(membership, "user_type_snapshot") || field(member, "identity_role");
  const currentPlanCode = activeSub ? field(activeSub, "package_code_snapshot") || null : null;
  const lastPaidOn = field(member, "last_payment_on");
  const lastPaidCents =
    typeof member.last_payment_amount_cents === "number" ? member.last_payment_amount_cents : null;
  const notes = field(member, "notes");

  const borderStyle = last ? undefined : "1px solid var(--border)";

  return (
    <tr style={{ borderBottom: borderStyle }}>
      {/* Nickname — sticky, opens detail panel */}
      <td className="sticky start-0 z-10 px-4 py-3" style={{ background: "var(--panel)" }}>
        <button
          className="text-sm font-semibold text-start hover:opacity-70 transition-opacity"
          style={{ color: "var(--text)" }}
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
                userType === "athlete" ? "color-mix(in srgb, var(--primary) 12%, transparent)" : "color-mix(in srgb, var(--muted) 12%, transparent)",
              color: userType === "athlete" ? "var(--primary)" : "var(--muted)",
            }}
          >
            <SemanticLabel value={userType} />
          </span>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>—</span>
        )}
      </td>

      {/* Status */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <InlineToggle
          value={membershipStatus}
          options={membershipStatusOptions}
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
          placeholder={i18n("noExpiry39d436a")}
          warn={expiresWarn(expiresOn)}
          dimmed={!expiresOn}
        />
      </td>

      {/* Last paid */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {lastPaidOn ? (
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>
            {lastPaidOn}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>—</span>
        )}
      </td>

      {/* Amount */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {lastPaidCents !== null ? (
          <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
            {eur.format(lastPaidCents / 100)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>—</span>
        )}
      </td>

      {/* Credits */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {creditCents !== 0 ? (
          <span
            className="text-xs font-semibold"
            style={{ color: creditCents > 0 ? "var(--success)" : "var(--primary-strong)" }}
          >
            {eur.format(creditCents / 100)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>—</span>
        )}
      </td>

      {/* Balance Due */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        {outstandingCents > 0 ? (
          <span
            className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold"
            style={{
              background: "color-mix(in srgb, var(--danger) 12%, transparent)",
              color: "var(--danger)",
            }}
          >
            {eur.format(outstandingCents / 100)} {i18n("due30cdf73")}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>—</span>
        )}
      </td>

      {/* Notes */}
      <td className="px-4 py-3" style={{ minWidth: "140px" }}>
        <InlineCell
          value={notes}
          type="text"
          onSave={(n) => onSave({ notes: n })}
          placeholder={i18n("addNotee26fd6a")}
          dimmed={!notes}
        />
      </td>

      {/* Referred By */}
      <td className="px-4 py-3" style={{ whiteSpace: "nowrap" }}>
        <Combobox
          value={referredById}
          placeholder={i18n("none6eef664")}
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
            <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {referralsMade.length}
            </span>
          ) : (
            <span className="text-xs" style={{ color: "var(--dim)" }}>0</span>
          )}
          <button
            className="rounded-full px-2 py-0.5 text-xs font-semibold"
            style={{
              background: "color-mix(in srgb, var(--primary) 10%, transparent)",
              border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)",
              color: "var(--primary)",
            }}
            onClick={onOpenReferralWizard}
            disabled={updatePending}
            type="button"
            title={i18n("recordNewReferrald9838d4")}
          >
            +
          </button>
        </div>
      </td>
    </tr>
  );
}
