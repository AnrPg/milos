"use client";

import { useState, type FormEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  MY_BUSINESS_REQUESTS_KEY,
  cancelBusinessRequest,
  fetchMyBusinessRequests,
  requestConversion,
  type BusinessKind,
  type BusinessRequest,
} from "@/api/business-accounts";
import { BusinessKindPicker } from "@/components/business/BusinessKindPicker";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const inputClass = "mt-1 w-full rounded-2xl px-4 py-3 text-base outline-none";
const inputStyle = { background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" } as const;

/**
 * ADR-184, Εγώ › Ρυθμίσεις › Επαγγελματικός λογαριασμός: ask the Palee team
 * to turn this account into a gym or an independent coach's practice, and
 * follow the requests already sent.
 */
export function BusinessAccountSettings() {
  const t = useTranslations("Business");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const requests = useQuery({
    queryKey: MY_BUSINESS_REQUESTS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchMyBusinessRequests(token!),
  });
  const list = requests.data?.requests ?? [];
  const pendingConversion = list.find((request) => request.kind === "conversion" && request.status === "pending");

  return (
    <CollapsibleSection id="business" title={t("settings.title")} description={t("settings.description")}>
      <div className="space-y-5">
        {list.length > 0 ? (
          <ul className="space-y-2">
            {list.map((request) => (
              <RequestRow key={request.id} token={token!} request={request} />
            ))}
          </ul>
        ) : null}
        {token && !pendingConversion ? <ConversionForm token={token} /> : null}
      </div>
    </CollapsibleSection>
  );
}

function RequestRow({ token, request }: { token: string; request: BusinessRequest }) {
  const t = useTranslations("Business");
  const i18n = useUiTranslations();
  const format = useFormatter();
  const queryClient = useQueryClient();
  const cancel = useMutation({
    mutationFn: () => cancelBusinessRequest(token, request.id),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: MY_BUSINESS_REQUESTS_KEY }),
  });

  return (
    <li className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{request.business_name}</p>
          <p className="text-xs" style={{ color: "var(--text-soft)" }}>
            {t(`requestKind.${request.kind}`)} · {t(`kind.${request.business_kind}`)} ·{" "}
            {format.dateTime(new Date(request.inserted_at), { dateStyle: "medium" })}
          </p>
        </div>
        <span className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel)", color: "var(--text-soft)" }}>
          {t(`status.${request.status}`)}
        </span>
      </div>
      {request.decision_note ? (
        <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{request.decision_note}</p>
      ) : null}
      {request.status === "pending" && request.kind === "conversion" ? (
        <button
          type="button"
          disabled={cancel.isPending}
          onClick={() => cancel.mutate()}
          className="mt-2 text-sm font-semibold disabled:opacity-50"
          style={{ color: "var(--dim)" }}
        >
          {t("settings.cancel")}
        </button>
      ) : null}
      {cancel.error ? <p role="alert" className="mt-2 text-sm" style={{ color: "var(--danger)" }}>{localizeError(cancel.error, i18n)}</p> : null}
    </li>
  );
}

function ConversionForm({ token }: { token: string }) {
  const t = useTranslations("Business");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [kind, setKind] = useState<BusinessKind>("gym");
  const [name, setName] = useState("");
  const [city, setCity] = useState("");
  const [phone, setPhone] = useState("");
  const [message, setMessage] = useState("");

  const send = useMutation({
    mutationFn: () =>
      requestConversion(token, {
        business_kind: kind,
        business_name: name.trim(),
        city: city.trim() || null,
        phone: phone.trim() || null,
        message: message.trim() || null,
      }),
    onSuccess: () => {
      setName("");
      setMessage("");
      void queryClient.invalidateQueries({ queryKey: MY_BUSINESS_REQUESTS_KEY });
    },
  });

  function submit(event: FormEvent) {
    event.preventDefault();
    if (name.trim().length < 2) return;
    send.mutate();
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("settings.intro")}</p>
      <BusinessKindPicker value={kind} onChange={setKind} />
      <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
        {t(kind === "coach" ? "form.coachName" : "form.gymName")}
        <input value={name} onChange={(event) => setName(event.target.value)} required minLength={2} maxLength={120} className={inputClass} style={inputStyle} />
      </label>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
          {t("form.city")}
          <input value={city} onChange={(event) => setCity(event.target.value)} maxLength={80} autoComplete="address-level2" className={inputClass} style={inputStyle} />
        </label>
        <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
          {t("form.phone")}
          <input value={phone} onChange={(event) => setPhone(event.target.value)} maxLength={40} autoComplete="tel" className={inputClass} style={inputStyle} />
        </label>
      </div>
      <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
        {t("form.message")}
        <textarea value={message} onChange={(event) => setMessage(event.target.value)} maxLength={1000} rows={3} className={inputClass} style={inputStyle} />
      </label>
      {send.isSuccess ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("settings.sent")}</p> : null}
      {send.error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(send.error, i18n)}</p> : null}
      <button
        type="submit"
        disabled={send.isPending || name.trim().length < 2}
        className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {send.isPending ? t("settings.sending") : t("settings.send")}
      </button>
    </form>
  );
}
