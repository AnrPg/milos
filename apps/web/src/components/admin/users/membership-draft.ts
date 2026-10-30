import { changedPatch, type DraftHistory } from "@/lib/draft-history";

import { renewableSubscriptions } from "./membership-leaving";

/**
 * ADR-276: what staff can edit on a box member's Finance tab before pressing
 * «Αποθήκευση»: the membership's status and dates, and each running
 * package's automatic renewal (ADR-220).
 */
export type MembershipDraft = {
  status: string;
  starts_on: string;
  expires_on: string;
  auto_renew: Record<string, boolean>;
};

export const EDITABLE_STATUSES = ["active", "paused", "cancelled"] as const;

function day(value: unknown) {
  return typeof value === "string" ? value.slice(0, 10) : "";
}

export function membershipDraftFrom(
  membership: Record<string, unknown> | null | undefined,
  subscriptions: Array<Record<string, unknown>>,
): MembershipDraft {
  const status = typeof membership?.status === "string" && membership.status ? membership.status : "active";
  return {
    status,
    starts_on: day(membership?.starts_on),
    expires_on: day(membership?.expires_on),
    auto_renew: Object.fromEntries(
      renewableSubscriptions(subscriptions).map((subscription) => [String(subscription.id), subscription.auto_renew === true]),
    ),
  };
}

/** The status picker's choices; a status set elsewhere (trial, expired…) stays visible. */
export function statusOptions(current: string): string[] {
  return (EDITABLE_STATUSES as readonly string[]).includes(current) ? [...EDITABLE_STATUSES] : [current, ...EDITABLE_STATUSES];
}

export function changedRenewals(history: DraftHistory<MembershipDraft>): Set<string> {
  const { saved, draft } = history;
  return new Set(Object.keys(draft.auto_renew).filter((id) => draft.auto_renew[id] !== saved.auto_renew[id]));
}

/** Changed fields, counting each renewal switch as its own change. */
export function membershipChangeCount(history: DraftHistory<MembershipDraft>) {
  const { auto_renew: renewals, ...fields } = changedPatch(history);
  return Object.keys(fields).length + (renewals ? changedRenewals(history).size : 0);
}

/**
 * The calls a save makes: one PATCH with only the changed membership fields
 * (an emptied date is sent as null) and one renewal call per changed switch.
 */
export function membershipSaveRequests(history: DraftHistory<MembershipDraft>) {
  const fields: Partial<MembershipDraft> = changedPatch(history);
  delete fields.auto_renew;
  const patch: Record<string, string | null> = {};
  for (const [key, value] of Object.entries(fields)) patch[key] = value === "" ? null : (value as string);
  const renewals = [...changedRenewals(history)].map((id) => ({ id, autoRenew: history.draft.auto_renew[id] }));
  return { patch: Object.keys(patch).length ? patch : null, renewals };
}
