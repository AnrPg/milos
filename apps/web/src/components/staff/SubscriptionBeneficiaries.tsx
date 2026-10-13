"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";

import type { FinanceRecord } from "@/api/finance";
import {
  addSubscriptionBeneficiary,
  fetchSubscriptionBeneficiaries,
  removeSubscriptionBeneficiary,
} from "@/api/payment-models";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { useSession } from "@/components/session-provider";
import { remainingBeneficiaryPlaces, staffErrorMessage } from "@/components/staff/staff-helpers";
import { dangerButtonStyle, Pill, primaryButtonClass, primaryButtonStyle, secondaryButtonClass, StatusText } from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";

// ADR-098 shared memberships: the payer's subscription lists the other people
// who use it. Staff add members who already have accounts in the gym.

function fieldValue(record: FinanceRecord, key: string): unknown {
  const fields = record.fields;
  if (fields && typeof fields === "object" && key in (fields as Record<string, unknown>)) {
    return (fields as Record<string, unknown>)[key];
  }
  const params = record.params_snapshot;
  if (params && typeof params === "object") return (params as Record<string, unknown>)[key];
  return undefined;
}

export function SubscriptionBeneficiaries({ subscription, payerUserId }: { subscription: FinanceRecord; payerUserId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const minorId = useId();
  const subscriptionId = String(subscription.id);
  const [userId, setUserId] = useState("");
  const [isMinor, setIsMinor] = useState(false);
  const queryKey = ["admin", "finance", "beneficiaries", subscriptionId];
  const limit = fieldValue(subscription, "terms.beneficiaries");
  const allowMinors = fieldValue(subscription, "terms.allow_minor_beneficiaries") === true;

  const beneficiariesQuery = useQuery({
    queryKey,
    enabled: Boolean(token),
    queryFn: () => fetchSubscriptionBeneficiaries(token, subscriptionId),
  });
  const active = (beneficiariesQuery.data ?? []).filter((beneficiary) => !beneficiary.removed_at);
  const remaining = remainingBeneficiaryPlaces(limit, active.length);

  const add = useMutation({
    mutationFn: () => addSubscriptionBeneficiary(token, subscriptionId, { user_id: userId, is_minor: isMinor }),
    onSuccess: async () => {
      setUserId("");
      setIsMinor(false);
      await queryClient.invalidateQueries({ queryKey });
    },
  });
  const remove = useMutation({
    mutationFn: (beneficiaryId: string) => removeSubscriptionBeneficiary(token, subscriptionId, beneficiaryId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });

  return (
    <div className="mt-2 space-y-2 rounded-[1rem] p-3" style={{ border: "1px dashed var(--border-strong)" }}>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {i18n("stfBeneficiaries")}
        {remaining !== null ? ` · ${i18n("stfPlacesLeft", { count: remaining })}` : ""}
      </p>
      {beneficiariesQuery.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : beneficiariesQuery.isError ? (
        <StatusText tone="error">{staffErrorMessage(beneficiariesQuery.error, i18n)}</StatusText>
      ) : active.length === 0 ? (
        <StatusText tone="muted">{i18n("stfNoBeneficiaries")}</StatusText>
      ) : (
        <ul className="space-y-1">
          {active.map((beneficiary) => (
            <li key={beneficiary.id} className="flex flex-wrap items-center justify-between gap-2 text-sm" style={{ color: "var(--text)" }}>
              <span className="flex items-center gap-2">
                {beneficiary.nickname ?? i18n("stfUnknownMember")}
                {beneficiary.is_minor ? <Pill tone="primary">{i18n("stfMinor")}</Pill> : null}
              </span>
              <button
                className={secondaryButtonClass}
                disabled={remove.isPending}
                onClick={() => {
                  if (window.confirm(i18n("stfRemoveBeneficiaryConfirm"))) remove.mutate(beneficiary.id);
                }}
                style={dangerButtonStyle}
                type="button"
              >
                {i18n("stfRemove")}
              </button>
            </li>
          ))}
        </ul>
      )}
      {remaining !== 0 && token ? (
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-56 flex-1">
            <UserSearchField
              excludeUserId={payerUserId}
              label={i18n("stfAddBeneficiary")}
              onChange={(id) => setUserId(id)}
              token={token}
              value={userId}
            />
          </div>
          {allowMinors ? (
            <label className="flex items-center gap-2 text-sm" htmlFor={minorId} style={{ color: "var(--text-soft)" }}>
              <input id={minorId} checked={isMinor} onChange={(event) => setIsMinor(event.target.checked)} type="checkbox" />
              {i18n("stfMinorCheckbox")}
            </label>
          ) : null}
          <button
            className={primaryButtonClass}
            disabled={!userId || add.isPending}
            onClick={() => add.mutate()}
            style={primaryButtonStyle}
            type="button"
          >
            {i18n("stfAdd")}
          </button>
        </div>
      ) : null}
      {add.isError ? <StatusText tone="error">{staffErrorMessage(add.error, i18n)}</StatusText> : null}
      {remove.isError ? <StatusText tone="error">{staffErrorMessage(remove.error, i18n)}</StatusText> : null}
    </div>
  );
}
