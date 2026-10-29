"use client";

import { useId, useState, type FormEvent } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  PROVIDER_CREDENTIALS,
  pickableProviders,
  providerName,
  savePaymentAccount,
  type CredentialKey,
  type PaymentAccountStatus,
  type PaymentEnvironment,
  type PaymentProvider,
} from "@/api/online-payments";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

import { paymentErrorText } from "./payment-errors";

const SECRET: Record<CredentialKey, boolean> = {
  client_id: false,
  merchant_id: false,
  client_secret: true,
  api_key: true,
  secret_key: true,
  webhook_secret: true,
};

type KeysErrors = { fields: Partial<Record<CredentialKey | "source_code", string>>; message: string | null };

/**
 * The pasted-keys way in (ADR-246): the business's own Viva or Stripe API
 * keys, checked with the provider before they are saved. Keys are written,
 * never read back; a saved one shows as «Αποθηκευμένο» and stays when left
 * empty. Errors stay in the form, under the field they belong to.
 */
export function PaymentKeysForm({
  token,
  status,
  provider: initialProvider,
  lockProvider = false,
  onSaved,
}: {
  token: string;
  status: PaymentAccountStatus;
  provider: PaymentProvider;
  lockProvider?: boolean;
  onSaved?: () => void;
}) {
  const t = useTranslations("OnlinePayments");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const formId = useId();
  const account = status.account;

  const [provider, setProvider] = useState<PaymentProvider>(initialProvider);
  const [environment, setEnvironment] = useState<PaymentEnvironment>(account?.environment ?? "live");
  const [values, setValues] = useState<Partial<Record<CredentialKey, string>>>({});
  const [sourceCode, setSourceCode] = useState(account?.provider === "viva" ? (account.settings?.source_code ?? "") : "");
  const [errors, setErrors] = useState<KeysErrors>({ fields: {}, message: null });

  const sameAccount = account?.provider === provider;
  const keys = PROVIDER_CREDENTIALS[provider] ?? [];
  const environments = (status.environments.length > 0 ? status.environments : ["live", "test"]) as PaymentEnvironment[];
  const providers = pickableProviders(status);

  const mutation = useMutation({
    mutationFn: () => {
      const credentials = Object.fromEntries(
        Object.entries(values).filter(([, value]) => typeof value === "string" && value.trim() !== ""),
      ) as Partial<Record<CredentialKey, string>>;
      return savePaymentAccount(token, {
        provider,
        environment,
        credentials,
        ...(provider === "viva" ? { settings: { source_code: sourceCode.trim() } } : {}),
      });
    },
    onSuccess: (next) => {
      queryClient.setQueryData(["admin", "payments", "account"], next);
      setValues({});
      setErrors({ fields: {}, message: null });
      onSaved?.();
    },
    onError: (error) => setErrors(keysErrors(error, provider, t, ui)),
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    mutation.mutate();
  }

  const fieldStyle = (message: string | undefined) => ({
    background: "var(--panel)",
    border: fieldBorder(message),
    color: "var(--text)",
  });

  return (
    <form className="space-y-3" onSubmit={submit} aria-label={t("keysTitle")} noValidate>
      <div className="grid gap-3 sm:grid-cols-2">
        {lockProvider ? null : (
          <label className="block space-y-1">
            <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("provider")}</span>
            <Select
              aria-label={t("provider")}
              value={provider}
              onValueChange={(value: string) => {
                setProvider(value as PaymentProvider);
                setErrors({ fields: {}, message: null });
              }}
              className="w-full"
            >
              {providers.map((option) => (
                <option key={option} value={option}>{providerName(option)}</option>
              ))}
            </Select>
          </label>
        )}
        <label className="block space-y-1">
          <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("environment")}</span>
          <Select
            aria-label={t("environment")}
            value={environment}
            onValueChange={(value: string) => setEnvironment(value as PaymentEnvironment)}
            className="w-full"
          >
            {environments.map((option) => (
              <option key={option} value={option}>{t(option === "test" ? "env_test" : "env_live")}</option>
            ))}
          </Select>
        </label>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        {keys.map((key) => {
          const id = `${formId}-${key}`;
          const errorId = `${id}-error`;
          const message = errors.fields[key];
          const saved = sameAccount && account?.credentials_set.includes(key);
          return (
            <label key={key} className="block space-y-1" htmlFor={id}>
              <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t(`cred_${key}`)}</span>
              <input
                id={id}
                type={SECRET[key] ? "password" : "text"}
                autoComplete="off"
                spellCheck={false}
                value={values[key] ?? ""}
                placeholder={saved ? t("savedPlaceholder") : undefined}
                onChange={(event) => setValues((current) => ({ ...current, [key]: event.target.value }))}
                className="w-full rounded-xl px-3 py-2 text-sm outline-none"
                style={fieldStyle(message)}
                {...invalidFieldProps(message, errorId)}
              />
              <FieldError id={errorId}>{message}</FieldError>
            </label>
          );
        })}
        {provider === "viva" ? (
          <label className="block space-y-1" htmlFor={`${formId}-source`}>
            <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("sourceCode")}</span>
            <input
              id={`${formId}-source`}
              type="text"
              autoComplete="off"
              spellCheck={false}
              value={sourceCode}
              maxLength={100}
              onChange={(event) => setSourceCode(event.target.value)}
              className="w-full rounded-xl px-3 py-2 text-sm outline-none"
              style={fieldStyle(errors.fields.source_code)}
            />
          </label>
        ) : null}
      </div>

      {sameAccount && account?.webhook_url ? (
        <div className="space-y-1">
          <p className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("webhookUrl")}</p>
          <p className="break-all rounded-xl px-3 py-2 font-mono text-xs" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
            {account.webhook_url}
          </p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("webhookHint", { provider: providerName(provider) })}</p>
        </div>
      ) : null}

      {errors.message ? <ErrorNotice>{errors.message}</ErrorNotice> : null}

      <div className="flex justify-end">
        <button
          type="submit"
          disabled={mutation.isPending}
          className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-60"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {mutation.isPending ? t("saving") : t("saveKeys")}
        </button>
      </div>
    </form>
  );
}

/** The API's `{credentials: rejected}` and per-key reasons, in plain words where they belong. */
export function keysErrors(
  error: unknown,
  provider: PaymentProvider,
  t: (key: string, values?: Record<string, string>) => string,
  ui: Parameters<typeof paymentErrorText>[2],
): KeysErrors {
  const name = providerName(provider);
  if (!(error instanceof ApiError) || error.status !== 422 || !error.payload.errors) {
    return { fields: {}, message: paymentErrorText(error, t, ui) };
  }
  const fields: KeysErrors["fields"] = {};
  const other: string[] = [];
  for (const [field, raw] of Object.entries(error.payload.errors)) {
    const reason = Array.isArray(raw) ? String(raw[0]) : String(raw);
    if (field === "credentials" && reason === "rejected") {
      other.push(t("errRejected", { provider: name }));
    } else if ((PROVIDER_CREDENTIALS[provider] as string[]).includes(field)) {
      fields[field as CredentialKey] = reason === "too_long" ? t("errTooLong") : t("errRequired");
    } else if (field === "provider" && reason === "unavailable") {
      other.push(t("errUnavailable"));
    } else {
      other.push(paymentErrorText(error, t, ui));
    }
  }
  return { fields, message: other.length > 0 ? [...new Set(other)].join(" ") : null };
}
