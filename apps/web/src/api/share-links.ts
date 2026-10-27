import { apiRequest } from "@/api/client";

/** ADR-210: the share links a member can also send by email. */
export type ShareLinkKind = "guest_pass" | "buddy_invite" | "referral";

export type ShareLinkDelivery = {
  id: string;
  status: "queued" | "deferred" | "sent" | "failed" | "suppressed";
};

/** Emails one of your own share links (`token`: the guest pass or buddy token, or the referral code). */
export function sendShareLinkByEmail(token: string, input: { link: ShareLinkKind; token: string; to: string }) {
  return apiRequest<{ delivery: ShareLinkDelivery }>("/me/share-links/email", {
    method: "POST",
    token,
    body: input,
  });
}
