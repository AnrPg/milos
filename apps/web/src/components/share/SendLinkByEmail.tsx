"use client";

import { useId, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { sendShareLinkByEmail, type ShareLinkKind } from "@/api/share-links";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const ERROR_KEYS: Record<string, string> = {
  share_link_sender_unverified: "errors.unverified",
  share_link_daily_limit: "errors.dailyLimit",
  throttled: "errors.throttled",
  suppressed: "errors.suppressed",
  invalid_address: "errors.invalidAddress",
  business_not_activated: "errors.demo",
  share_link_invalid: "errors.unavailable",
};

/**
 * ADR-210: «Αποστολή με email», one more way out of a share sheet. A
 * quiet link that opens an address field; Palee emails the same link with
 * the member's name and nothing else. `token` is null until the link exists.
 */
export function SendLinkByEmail({ link, token }: { link: ShareLinkKind; token: string | null }) {
  const t = useTranslations("ShareByEmail");
  const { tokens } = useSession();
  const fieldId = useId();
  const [open, setOpen] = useState(false);
  const [to, setTo] = useState("");
  const send = useMutation({
    mutationFn: (address: string) => sendShareLinkByEmail(tokens!.access_token, { link, token: token!, to: address }),
  });

  if (!token || !tokens?.access_token) return null;

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="self-start text-sm font-semibold underline underline-offset-2"
        style={{ color: "var(--text-soft)" }}
        data-testid="share-by-email"
      >
        {t("action")}
      </button>
    );
  }

  const sentTo = send.isSuccess ? send.variables : null;

  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        const address = to.trim();
        if (address) send.mutate(address);
      }}
      data-testid="share-by-email-form"
    >
      <label htmlFor={fieldId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("label")}
      </label>
      <div className="flex gap-2">
        <input
          id={fieldId}
          type="email"
          inputMode="email"
          autoComplete="off"
          required
          value={to}
          onChange={(event) => {
            setTo(event.target.value);
            if (send.isSuccess || send.isError) send.reset();
          }}
          placeholder={t("placeholder")}
          className="min-h-11 min-w-0 flex-1 rounded-2xl px-4 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <button
          type="submit"
          disabled={send.isPending || !to.trim()}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {send.isPending ? t("sending") : t("send")}
        </button>
      </div>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("hint")}</p>
      {sentTo ? (
        <p role="status" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("sent", { email: sentTo })}
        </p>
      ) : null}
      {send.isError ? <ErrorNotice>{t(errorKey(send.error))}</ErrorNotice> : null}
    </form>
  );
}

function errorKey(error: unknown): string {
  const code = error instanceof ApiError ? error.payload.code : undefined;
  return (code && ERROR_KEYS[code]) || "errors.generic";
}
