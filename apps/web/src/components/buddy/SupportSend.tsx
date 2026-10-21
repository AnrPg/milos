"use client";

import Link from "next/link";
import { useId, useState } from "react";
import { useTranslations } from "next-intl";

import type { SupportRequest } from "@/api/buddies";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useUiTranslations } from "@/i18n/ui";

import { HeartIcon } from "./BuddyBits";
import { MESSAGE_MAX, activeBuddies, recipientNames } from "./buddy-model";
import { buddyErrorMessage } from "./errors";
import { SupportStatus } from "./SupportStatus";
import { useBuddies, useSendSupport } from "./use-buddies";

/**
 * «Χρειάζομαι στήριξη» (board 15 q3 A): one optional line, who it goes to,
 * Αποστολή, then five seconds to take it back. Buddies hear nothing before
 * the undo closes; nothing about a craving travels.
 */
export function NeedSupportSheet({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Buddy");
  const labelId = useId();
  const [sent, setSent] = useState<SupportRequest | null>(null);
  return (
    <Sheet
      labelId={labelId}
      title={t("needSupport")}
      onClose={onClose}
      footer={sent ? <SheetButton onClick={onClose}>{t("close")}</SheetButton> : undefined}
    >
      {sent ? <SupportStatus key={sent.id} request={sent} onResent={setSent} /> : <SupportComposer onSent={setSent} onCancel={onClose} />}
    </Sheet>
  );
}

export function SupportComposer({ onSent, onCancel }: { onSent: (request: SupportRequest) => void; onCancel?: () => void }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const overview = useBuddies();
  const { send } = useSendSupport();
  const [message, setMessage] = useState("");
  const recipients = activeBuddies(overview.data);

  if (overview.isPending) return <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (recipients.length === 0) {
    return (
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noBuddyYet")}</p>
        <Link
          href="/me/buddy"
          className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {t("setUpBuddy")}
        </Link>
      </div>
    );
  }

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        send.mutate(message.trim() || null, { onSuccess: onSent });
      }}
    >
      <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("messageLabel")}
        <input
          value={message}
          maxLength={MESSAGE_MAX}
          onChange={(event) => setMessage(event.target.value)}
          placeholder={t("messagePlaceholder")}
          className="min-h-11 rounded-2xl px-4"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
      </label>
      <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }} data-testid="support-recipients">
        {t("goesTo", { names: recipientNames(recipients, t("someone")) })}
      </p>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("sendPrivacy")}</p>
      <ErrorLine message={buddyErrorMessage(send.error, t, tUi)} />
      <div className="flex gap-2">
        {onCancel ? <SheetButton onClick={onCancel}>{t("cancel")}</SheetButton> : null}
        <SheetButton primary type="submit" disabled={send.isPending}>
          {send.isPending ? t("sending") : t("send")}
        </SheetButton>
      </div>
    </form>
  );
}

/** The labelled button that opens the quick send (Ευεξία, Buddy page). */
export function NeedSupportButton({ className = "" }: { className?: string }) {
  const t = useTranslations("Buddy");
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={["flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold", className].join(" ")}
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
      >
        <HeartIcon />
        {t("needSupport")}
      </button>
      {open ? <NeedSupportSheet onClose={() => setOpen(false)} /> : null}
    </>
  );
}
