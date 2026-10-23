"use client";

import { useLocale, useTranslations } from "next-intl";

import type { PasswordResetRequest } from "@/api/password-resets";
import { relativeTime } from "@/components/password-resets/reset-email";
import { claimerName } from "@/components/password-resets/request-labels";

const TONES: Record<PasswordResetRequest["state"], string> = {
  open: "var(--primary)",
  mine: "var(--accent)",
  taken: "var(--dim)",
  link_sent: "var(--success)",
  expired: "var(--warning)",
};

/** The state a viewer sees a request in: new, theirs, someone else's, link out, expired. */
export function StateChip({ request, now }: { request: PasswordResetRequest; now: number }) {
  const t = useTranslations("passwordResets");
  const locale = useLocale();
  const tone = TONES[request.state];
  const label = (() => {
    switch (request.state) {
      case "open":
        return t("stateOpen");
      case "mine":
        return t("stateMine");
      case "taken":
        return t("stateTaken", { name: claimerName(request, t) });
      case "link_sent":
        return request.link_expires_at
          ? t("stateLinkSent", { time: relativeTime(request.link_expires_at, now, locale) })
          : t("stateLinkSentPlain");
      case "expired":
        return t("stateExpired");
    }
  })();

  return (
    <span
      className="inline-flex max-w-full items-center gap-1.5 truncate rounded-full px-2.5 py-0.5 text-xs font-semibold"
      style={{ color: tone, background: `color-mix(in srgb, ${tone} 12%, transparent)` }}
    >
      <span aria-hidden="true" className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: tone }} />
      {label}
    </span>
  );
}
