"use client";

import { useEffect, useId, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  VERIFICATION_KEY,
  confirmPhone,
  sendPhoneCode,
  type PhoneSent,
  type VerificationLimits,
  type VerificationRequest,
} from "@/api/partner-verification";

import { cleanCode, errorFor, plausiblePhone } from "./verify-model";
import { VerifyError, inputClass, inputStyle, primaryButton, primaryStyle, secondaryStyle } from "./verify-ui";

/** Seconds before «Στείλε ξανά» is offered, so a slow SMS is not chased by a second one. */
const RESEND_AFTER = 30;

/**
 * Step 3: a mobile number (one per account) and the 6-digit code it gets by
 * SMS. Errors show under their own field; the send limits (3 an hour, 10 a
 * day) come back from the API as `partner_phone_rate_limited`.
 */
export function PhoneStep({ token, request, limits }: { token: string; request: VerificationRequest; limits: VerificationLimits }) {
  const t = useTranslations("PartnerVerify");
  const queryClient = useQueryClient();
  const phoneId = useId();
  const codeId = useId();
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState<(PhoneSent & { at: number }) | null>(null);
  // A number already given but not confirmed: go straight to the code.
  const [editing, setEditing] = useState(!request.phone);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!sent) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [sent]);

  const send = useMutation({
    mutationFn: (number: string) => sendPhoneCode(token, number),
    onSuccess: (result) => {
      setSent({ ...result, at: Date.now() });
      setNow(Date.now());
      setEditing(false);
      setCode("");
    },
  });
  const confirm = useMutation({
    mutationFn: (value: string) => confirmPhone(token, value),
    onSuccess: (next) => {
      queryClient.setQueryData(VERIFICATION_KEY, next);
    },
  });
  const maskedPhone = sent?.phone ?? request.phone;
  const waited = sent ? Math.floor((now - sent.at) / 1000) : RESEND_AFTER;
  const resendIn = Math.max(0, RESEND_AFTER - waited);

  if (editing || !maskedPhone) {
    const phoneError = errorFor(send.error, "phone");
    return (
      <form
        className="flex flex-col gap-2"
        data-testid="phone-form"
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          if (plausiblePhone(phone)) send.mutate(phone.trim());
        }}
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("phone.lead")}</p>
        <label htmlFor={phoneId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("phone.label")}</label>
        <input
          id={phoneId}
          className={inputClass}
          style={inputStyle}
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          dir="ltr"
          placeholder={t("phone.placeholder")}
          value={phone}
          aria-invalid={Boolean(phoneError)}
          aria-describedby={phoneError ? `${phoneId}-error` : undefined}
          onChange={(event) => setPhone(event.target.value)}
        />
        {phoneError ? <VerifyError error={phoneError} field id={`${phoneId}-error`} /> : null}
        {!phoneError && send.error ? <VerifyError error={send.error} /> : null}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("phone.private")}</p>
        <div className="flex flex-wrap gap-2">
          <button type="submit" className={primaryButton} style={primaryStyle} disabled={send.isPending || !plausiblePhone(phone)}>
            {t("phone.send")}
          </button>
          {maskedPhone ? (
            <button type="button" className={primaryButton} style={secondaryStyle} onClick={() => setEditing(false)}>
              {t("phone.back")}
            </button>
          ) : null}
        </div>
      </form>
    );
  }

  const codeError = errorFor(confirm.error, "code");
  const resendError = send.error;
  return (
    <form
      className="flex flex-col gap-2"
      data-testid="code-form"
      noValidate
      onSubmit={(event) => {
        event.preventDefault();
        if (code.length === 6) confirm.mutate(code);
      }}
    >
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {t("phone.sentTo", { phone: maskedPhone, minutes: sent?.code_minutes ?? limits.code_minutes })}
      </p>
      <label htmlFor={codeId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("phone.codeLabel")}</label>
      <input
        id={codeId}
        className={`${inputClass} tracking-[0.4em]`}
        style={inputStyle}
        inputMode="numeric"
        autoComplete="one-time-code"
        dir="ltr"
        maxLength={6}
        value={code}
        aria-invalid={Boolean(codeError)}
        aria-describedby={codeError ? `${codeId}-error` : undefined}
        onChange={(event) => setCode(cleanCode(event.target.value))}
      />
      {codeError ? <VerifyError error={codeError} field id={`${codeId}-error`} /> : null}
      {!codeError && confirm.error ? <VerifyError error={confirm.error} /> : null}
      {resendError ? <VerifyError error={resendError} field /> : null}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("phone.attempts", { count: limits.code_attempts })}</p>
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={primaryButton} style={primaryStyle} disabled={confirm.isPending || code.length !== 6}>
          {t("phone.confirm")}
        </button>
        {sent ? (
          <button
            type="button"
            className={primaryButton}
            style={secondaryStyle}
            disabled={send.isPending || resendIn > 0}
            onClick={() => send.mutate(phone.trim())}
          >
            {resendIn > 0 ? t("phone.resendIn", { seconds: resendIn }) : t("phone.resend")}
          </button>
        ) : null}
        <button type="button" className={primaryButton} style={secondaryStyle} onClick={() => setEditing(true)}>
          {t("phone.change")}
        </button>
      </div>
    </form>
  );
}
