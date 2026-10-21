"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { HeartIcon } from "./BuddyBits";
import { activeBuddies, latestOpenRequest, recipientNames } from "./buddy-model";
import { NeedSupportSheet } from "./SupportSend";
import { SupportStatus } from "./SupportStatus";
import { useBuddies, useSupportRequests } from "./use-buddies";

/**
 * Ευεξία's «Χρειάζομαι στήριξη» (board 15 q3 A): one button that sends to
 * every active buddy, and the latest request's status underneath (who got
 * it, who replied, the calm card after ten minutes). Without a buddy it
 * leads to Εγώ › Buddy.
 */
export function WellnessSupportCard({ initialOpen = false }: { initialOpen?: boolean }) {
  const t = useTranslations("Buddy");
  const overview = useBuddies();
  const sent = useSupportRequests("sent");
  const [open, setOpen] = useState(initialOpen);
  const [now] = useState(() => Date.now());
  const recipients = activeBuddies(overview.data);
  const latest = latestOpenRequest(sent.data ?? [], now);

  return (
    <section
      id="support"
      aria-labelledby="wellness-support-title"
      className="flex flex-col gap-3 rounded-[1.6rem] p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="wellness-support"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 id="wellness-support-title" className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("needSupport")}</h2>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {recipients.length > 0 ? t("goesTo", { names: recipientNames(recipients, t("someone")) }) : t("noBuddyYetShort")}
          </p>
        </div>
        {recipients.length > 0 ? (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="flex min-h-11 shrink-0 items-center gap-2 rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            <HeartIcon />
            {t("ask")}
          </button>
        ) : (
          <Link
            href="/me/buddy"
            className="flex min-h-11 shrink-0 items-center rounded-2xl px-4 text-sm font-bold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("setUpBuddy")}
          </Link>
        )}
      </div>
      {latest ? <SupportStatus key={latest.id} request={latest} /> : null}
      {open ? <NeedSupportSheet onClose={() => setOpen(false)} /> : null}
    </section>
  );
}
