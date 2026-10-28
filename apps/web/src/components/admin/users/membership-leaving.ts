/** ADR-220: staff marking a box member as leaving. */

export type LeaveWhen = "end_of_period" | "today" | "date";

/**
 * The request body for a leave: no day means "when what they paid for ends"
 * (the API works it out), today, or a chosen day (today at the earliest).
 */
export function leaveRequest(
  form: { when: LeaveWhen; date: string; reason: string },
  today: string,
  commitmentOverrideReason: string | null,
): { leaving_on: string | null; reason: string | null; commitment_override_reason: string | null } {
  const leavingOn = form.when === "today" ? today : form.when === "date" ? form.date || today : null;
  return {
    leaving_on: leavingOn,
    reason: form.reason.trim() || null,
    commitment_override_reason: commitmentOverrideReason,
  };
}

/** Running packages whose renewal is the box member's choice (`auto_renew` is a boolean). */
export function renewableSubscriptions(subscriptions: Array<Record<string, unknown>>) {
  return subscriptions.filter((subscription) => subscription.status === "active" && typeof subscription.auto_renew === "boolean");
}
