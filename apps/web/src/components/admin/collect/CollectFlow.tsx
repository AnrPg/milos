"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState, type FormEvent, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import {
  cancelTerminalPayment,
  fetchDeskOptions,
  fetchDeskPeople,
  fetchTerminalPayment,
  makeGuest,
  postTerminalResult,
  startTerminalPayment,
  type DeskOptions,
  type DeskPerson,
  type TerminalPayment,
} from "@/api/desk-collect";
import { formatTime } from "@/components/client/format";
import { Card, Chip, formatMoney, Pill } from "@/components/fiscal/fiscal-ui";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { Select } from "@/components/ui/Select";
import { localizeError, roleLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { launchTerminalSale, parseTerminalCallback, vivaTerminalPlugin } from "@/lib/platform/viva-terminal";
import { can } from "@/lib/role-navigation";

import { CollectResult } from "./CollectResult";
import {
  CHARGE_CATEGORIES,
  choicesFor,
  defaultChoice,
  FREE_SALE_MAX,
  freeSaleErrors,
  initials,
  looksLikeEmail,
  newAttemptKey,
  outcomeOf,
  pickedAmount,
  startBody,
  type Choice,
  type FreeSale,
  type Payer,
  type Purchase,
  type Step,
} from "./collect-flow";
import { Avatar, BigButton, BigLink, BigMark, CollectIcon, Crumb, FieldError, fieldInputClass, fieldInputStyle } from "./collect-ui";
import { useRecoveredPayment, useTapToPaySupported, useTerminalAvailability } from "./use-collect";

const EMPTY_FREE: FreeSale = { description: "", amount: "", category: "other" };

/**
 * «Είσπραξη» step by step on the staff phone (mockup pilot-gaps screen 2,
 * alternative A): Ποιος › Τι › Έλεγχος › Viva.com Terminal › Αποτέλεσμα, one
 * main button per step. Money is recorded only from what Viva confirms
 * (ADR-249); the result shows the receipt, the tip and whose it is (ADR-272).
 */
export function CollectFlow() {
  const t = useTranslations("Collect");
  const { membership, isLoading } = useSelectedMembershipRole();
  const supported = useTapToPaySupported();

  if (isLoading) return <Frame><StatusText tone="muted">{t("loading")}</StatusText></Frame>;
  if (!can(membership, "take_payments")) return <Frame><StatusText tone="muted">{t("noAccess")}</StatusText></Frame>;
  if (!supported) return <Frame><StatusText tone="muted">{t("notOnPhone")}</StatusText></Frame>;
  return <Flow />;
}

function Frame({ children }: { children: ReactNode }) {
  return (
    <main className="min-h-screen px-4 pb-24 pt-4" style={{ background: "var(--bg)" }}>
      <div className="mx-auto grid w-full max-w-md gap-4">{children}</div>
    </main>
  );
}

function Flow() {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const router = useRouter();
  const params = useSearchParams();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const availability = useTerminalAvailability();
  const recovered = useRecoveredPayment(true);

  const [step, setStep] = useState<Step>("who");
  const [payer, setPayer] = useState<Payer | null>(null);
  const [payerName, setPayerName] = useState<string | null>(null);
  const [purchase, setPurchase] = useState<Purchase | null>(null);
  const [payment, setPayment] = useState<TerminalPayment | null>(null);
  const [guestPrompt, setGuestPrompt] = useState(false);
  const [attemptKey, setAttemptKey] = useState(newAttemptKey);
  const [dismissed, setDismissed] = useState(false);

  // A payment opened from the home card, or found after iOS reset the app,
  // shows until staff start a new one.
  const openId = params.get("payment");
  const opened = useQuery({
    queryKey: ["admin", "payments", "terminal", "payment", slug, openId],
    enabled: Boolean(token && openId) && !payment && !dismissed,
    queryFn: () => fetchTerminalPayment(token, openId!).then((response) => response.payment),
  });
  const outside = payment || dismissed ? null : (opened.data ?? (openId ? null : recovered));
  const shown = payment ?? outside;
  const current: Step = outside ? (outcomeOf(outside) === "waiting" ? "wait" : "result") : step;

  // The terminal app's answer while the page is open (Android, and iOS
  // without the reset): passed on to the API, which confirms it with Viva.
  useEffect(() => {
    if (!token) return;
    let remove: (() => Promise<void>) | null = null;
    let cancelled = false;
    void vivaTerminalPlugin()
      .then((plugin) =>
        plugin.addListener("result", ({ url }) => {
          const body = parseTerminalCallback(url)?.body;
          if (!body) return;
          void postTerminalResult(token, body).then(({ payment: answered }) => {
            setPayment(answered);
            setStep(outcomeOf(answered) === "waiting" ? "wait" : "result");
          });
        }),
      )
      .then((handle) => {
        if (cancelled) void handle.remove();
        else remove = handle.remove;
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
      if (remove) void remove();
    };
  }, [token]);

  function restart() {
    setAttemptKey(newAttemptKey());
    setDismissed(true);
    setPayer(null);
    setPayerName(null);
    setPurchase(null);
    setPayment(null);
    setGuestPrompt(false);
    setStep("who");
    if (openId) router.replace(adminHref("/admin/collect", slug));
  }

  function again() {
    setAttemptKey(newAttemptKey());
    setDismissed(true);
    setPayment(null);
    setStep(purchase ? "confirm" : "who");
  }

  if (availability.data && !availability.data.available) {
    return (
      <Frame>
        <Crumb title={t("title")} current={t("whoTitle")} backLabel={t("back")} onBack={() => router.push(adminHref("/admin", slug))} />
        <Card testId="collect-unavailable">
          <b className="text-sm" style={{ color: "var(--text)" }}>{t("unavailableTitle")}</b>
          <span className="text-xs" style={{ color: "var(--muted)" }}>{t(`reason_${availability.data.reason ?? "no_viva"}`)}</span>
          <BigLink href={adminHref("/admin/settings?tab=payments", slug)} ghost>
            {t("paymentSettings")}
          </BigLink>
        </Card>
      </Frame>
    );
  }

  return (
    <Frame>
      {current === "who" ? (
        <WhoStep
          prompt={guestPrompt}
          onBack={() => router.push(adminHref("/admin", slug))}
          onPick={(next, name) => {
            setPayer(next);
            setPayerName(name);
            setPurchase(null);
            setGuestPrompt(false);
            setStep("what");
          }}
        />
      ) : null}
      {current === "what" && payer ? (
        <WhatStep
          payer={payer}
          payerName={payerName}
          initial={purchase}
          onBack={() => setStep("who")}
          onMakeGuest={() => {
            setGuestPrompt(true);
            setStep("who");
          }}
          onNext={(next) => {
            setPurchase(next);
            setStep("confirm");
          }}
        />
      ) : null}
      {current === "confirm" && payer && purchase ? (
        <ConfirmStep
          payer={payer}
          payerName={payerName}
          purchase={purchase}
          attemptKey={attemptKey}
          onBack={() => setStep("what")}
          onStarted={(started) => {
            setPayment(started);
            setStep("wait");
          }}
        />
      ) : null}
      {current === "wait" && shown ? (
        <WaitStep
          key={shown.id}
          payment={shown}
          onResult={(answered) => {
            setPayment(answered);
            setStep("result");
          }}
        />
      ) : null}
      {current === "result" && shown ? (
        <CollectResult
          payment={shown}
          payerName={payer?.kind === "person" ? payerName : null}
          onChange={(fresh) => {
            setPayment(fresh);
            setStep(outcomeOf(fresh) === "waiting" ? "wait" : "result");
          }}
          onAgain={again}
          onNew={restart}
          onDone={() => router.push(adminHref("/admin", slug))}
        />
      ) : null}
      {opened.isError ? <StatusText tone="error">{localizeError(opened.error, i18n)}</StatusText> : null}
    </Frame>
  );
}

// ── Ποιος πληρώνει; ─────────────────────────────────────────────────────

function useDebounced(value: string, ms: number) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = window.setTimeout(() => setDebounced(value), ms);
    return () => window.clearTimeout(id);
  }, [value, ms]);
  return debounced;
}

function WhoStep({ onPick, onBack, prompt }: { onPick: (payer: Payer, name: string | null) => void; onBack: () => void; prompt: boolean }) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [query, setQuery] = useState("");
  const q = useDebounced(query.trim(), 250);
  const [outsider, setOutsider] = useState<DeskPerson | null>(null);
  const [newGuest, setNewGuest] = useState(prompt);
  const people = useQuery({
    queryKey: ["admin", "payments", "desk", "people", slug, q],
    enabled: Boolean(token),
    queryFn: () => fetchDeskPeople(token, q).then((response) => response.people),
    placeholderData: (previous) => previous,
  });
  const promote = useMutation({
    mutationFn: (userId: string) => makeGuest(token, { user_id: userId }),
    onSuccess: (result) => onPick({ kind: "person", userId: result.person.user_id, name: result.person.name ?? "", relation: "guest" }, result.person.name),
  });

  function pick(person: DeskPerson) {
    if (person.relation === "none") {
      setOutsider(person);
      return;
    }
    onPick({ kind: "person", userId: person.user_id, name: person.name ?? "", relation: person.relation }, person.name);
  }

  const list = people.data ?? [];

  return (
    <>
      <Crumb title={t("title")} current={t("whoTitle")} backLabel={t("back")} onBack={onBack} />
      <label className="relative block">
        <span className="sr-only">{t("search")}</span>
        <input
          type="search"
          inputMode="search"
          autoComplete="off"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("search")}
          className={fieldInputClass}
          style={fieldInputStyle(false)}
          data-testid="collect-search"
        />
      </label>
      <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{q ? t("results") : t("checkedInToday")}</span>
      {people.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : people.isError ? (
        <StatusText tone="error">{localizeError(people.error, i18n)}</StatusText>
      ) : list.length === 0 ? (
        <StatusText tone="muted">{q ? t("noResults") : t("noCheckIns")}</StatusText>
      ) : (
        <ul className="grid gap-1 rounded-[18px] p-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="collect-people">
          {list.map((person) => (
            <li key={person.user_id}>
              <button type="button" onClick={() => pick(person)} className="flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-start">
                <Avatar text={initials(person.name)} url={person.avatar_url} />
                <span className="grid min-w-0 flex-1">
                  <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{person.name}</span>
                  <span className="flex flex-wrap items-center gap-1.5 text-xs" style={{ color: "var(--muted)" }}>
                    {person.checked_in_at ? t("checkedInAt", { time: formatTime(person.checked_in_at, locale) }) : null}
                    {person.relation === "guest" ? <Pill tone="accent">{roleLabel("guest", i18n)}</Pill> : null}
                    {person.relation === "none" ? <Pill tone="warn">{t("notInBox")}</Pill> : null}
                  </span>
                </span>
                <CollectIcon name="chevron" size={14} />
              </button>
              {outsider?.user_id === person.user_id ? (
                <div className="grid gap-2 px-3 pb-3" data-testid="collect-outsider">
                  <span className="text-xs" style={{ color: "var(--muted)" }}>{t("makeGuestHint")}</span>
                  <BigButton onClick={() => promote.mutate(person.user_id)} disabled={promote.isPending} testId="collect-promote">
                    {promote.isPending ? t("makingGuest") : t("saveGuest")}
                  </BigButton>
                  {promote.isError ? <FieldError id="collect-promote-error">{guestErrorText(promote.error, t, i18n)}</FieldError> : null}
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      <BigButton ghost onClick={() => onPick({ kind: "walk_in" }, null)} testId="collect-walk-in">
        <CollectIcon name="user" />
        {t("walkIn")}
      </BigButton>
      {newGuest ? (
        <NewGuestForm onCancel={() => setNewGuest(false)} onDone={(person) => onPick({ kind: "person", userId: person.user_id, name: person.name ?? "", relation: "guest" }, person.name)} />
      ) : (
        <button type="button" onClick={() => setNewGuest(true)} className="text-sm font-bold" style={{ color: "var(--primary-strong)" }} data-testid="collect-new-guest">
          + {t("newGuest")}
        </button>
      )}
    </>
  );
}

type Translate = ReturnType<typeof useTranslations>;

function guestErrorText(error: unknown, t: Translate, i18n: ReturnType<typeof useUiTranslations>) {
  const code = error instanceof ApiError ? error.payload.code : undefined;
  if (code === "guest_is_staff") return t("guestIsStaff");
  if (code === "guest_email_invalid") return t("emailInvalid");
  if (code === "guest_name_required") return t("nameRequired");
  return localizeError(error, i18n);
}

function NewGuestForm({ onCancel, onDone }: { onCancel: () => void; onDone: (person: DeskPerson) => void }) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [errors, setErrors] = useState<{ name?: string; email?: string; form?: string }>({});
  const save = useMutation({
    mutationFn: () => makeGuest(token, { name: name.trim(), email: email.trim() }),
    onSuccess: (result) => onDone(result.person),
    onError: (error) => {
      const code = error instanceof ApiError ? error.payload.code : undefined;
      if (code === "guest_name_required") setErrors({ name: t("nameRequired") });
      else if (code === "guest_email_invalid" || code === "guest_is_staff") setErrors({ email: guestErrorText(error, t, i18n) });
      else setErrors({ form: localizeError(error, i18n) });
    },
  });

  function submit(event: FormEvent) {
    event.preventDefault();
    const next: typeof errors = {};
    if (!name.trim()) next.name = t("nameRequired");
    if (!looksLikeEmail(email)) next.email = t("emailInvalid");
    setErrors(next);
    if (Object.keys(next).length === 0) save.mutate();
  }

  return (
    <form onSubmit={submit} noValidate className="grid gap-3 rounded-[18px] p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="collect-guest-form">
      <b className="text-sm" style={{ color: "var(--text)" }}>{t("newGuest")}</b>
      <span className="text-xs" style={{ color: "var(--muted)" }}>{t("newGuestHint")}</span>
      <label className="grid gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("guestName")} <span aria-label={t("required")} style={{ color: "var(--danger)" }}>*</span>
        </span>
        <input
          value={name}
          onChange={(event) => setName(event.target.value)}
          maxLength={120}
          autoComplete="off"
          className={fieldInputClass}
          style={fieldInputStyle(Boolean(errors.name))}
          aria-invalid={Boolean(errors.name)}
          aria-describedby={errors.name ? "collect-guest-name-error" : undefined}
          data-testid="collect-guest-name"
        />
        {errors.name ? <FieldError id="collect-guest-name-error">{errors.name}</FieldError> : null}
      </label>
      <label className="grid gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("guestEmail")} <span aria-label={t("required")} style={{ color: "var(--danger)" }}>*</span>
        </span>
        <input
          type="email"
          inputMode="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          maxLength={254}
          autoComplete="off"
          className={fieldInputClass}
          style={fieldInputStyle(Boolean(errors.email))}
          aria-invalid={Boolean(errors.email)}
          aria-describedby={errors.email ? "collect-guest-email-error" : undefined}
          data-testid="collect-guest-email"
        />
        {errors.email ? <FieldError id="collect-guest-email-error">{errors.email}</FieldError> : null}
      </label>
      {errors.form ? <FieldError id="collect-guest-form-error">{errors.form}</FieldError> : null}
      <BigButton type="submit" disabled={save.isPending} testId="collect-guest-save">
        {save.isPending ? t("makingGuest") : t("saveGuest")}
      </BigButton>
      <button type="button" onClick={onCancel} className="text-sm font-bold" style={{ color: "var(--muted)" }}>
        {t("cancel")}
      </button>
    </form>
  );
}

// ── Τι πληρώνει; ────────────────────────────────────────────────────────

function payerLabel(payer: Payer, name: string | null, t: Translate) {
  return payer.kind === "walk_in" ? t("walkIn") : name ?? "";
}

function choiceTitle(choice: Choice, t: Translate) {
  switch (choice.kind) {
    case "renewal":
      return t("renewal", { name: choice.name });
    case "invoice":
      return t("invoice", { number: choice.number ?? "" }).trim();
    case "order":
      return t("order", { number: `K-${choice.number}` });
    case "package":
      return t("package");
    case "free":
      return t("free");
  }
}

function choiceHint(choice: Choice, t: Translate) {
  switch (choice.kind) {
    case "renewal":
      return t("renewalHint");
    case "invoice":
      return choice.description ?? t("invoiceHint");
    case "order":
      return choice.summary;
    case "package":
      return t("packageHint");
    case "free":
      return t("freeHint");
  }
}

function WhatStep({
  payer,
  payerName,
  initial,
  onBack,
  onNext,
  onMakeGuest,
}: {
  payer: Payer;
  payerName: string | null;
  initial: Purchase | null;
  onBack: () => void;
  onNext: (purchase: Purchase) => void;
  onMakeGuest: () => void;
}) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const userId = payer.kind === "person" ? payer.userId : null;
  const options = useQuery({
    queryKey: ["admin", "payments", "desk", "options", slug, userId ?? "walk_in"],
    enabled: Boolean(token),
    queryFn: () => fetchDeskOptions(token, userId).then((response) => response.options),
  });
  const choices = choicesFor(options.data, payer);
  const [key, setKey] = useState<string | null>(initial?.choice.key ?? null);
  const [packageId, setPackageId] = useState<string | null>(initial?.packageId ?? null);
  const [free, setFree] = useState<FreeSale>(initial?.free ?? EMPTY_FREE);
  const [shown, setShown] = useState<{ description?: string; amount?: string; package?: string }>({});
  const choice = choices.find((entry) => entry.key === key) ?? defaultChoice(choices);

  function next() {
    if (!choice) return;
    const purchase: Purchase = { choice, packageId: choice.kind === "package" ? packageId : null, free };
    if (choice.kind === "free") {
      const errors = freeSaleErrors(free);
      setShown({ description: errors.description && t(errors.description), amount: errors.amount && t(errors.amount) });
      if (Object.keys(errors).length > 0) return;
    }
    if (choice.kind === "package" && !packageId) {
      setShown({ package: t("packageRequired") });
      return;
    }
    setShown({});
    onNext(purchase);
  }

  return (
    <>
      <Crumb title={t("title")} current={payerLabel(payer, payerName, t)} backLabel={t("back")} onBack={onBack} />
      <b className="text-base" style={{ color: "var(--text)" }}>{t("whatTitle")}</b>
      {options.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : options.isError ? (
        <StatusText tone="error">{localizeError(options.error, i18n)}</StatusText>
      ) : (
        <div role="radiogroup" aria-label={t("whatTitle")} className="grid gap-2" data-testid="collect-choices">
          {choices.map((entry) => {
            const on = choice?.key === entry.key;
            const amount = "amountCents" in entry ? formatMoney(locale, entry.amountCents, entry.currency) : null;
            return (
              <div key={entry.key} className="grid gap-2">
                <button
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => {
                    setKey(entry.key);
                    setShown({});
                  }}
                  className="flex items-start gap-3 rounded-2xl px-3 py-3 text-start"
                  style={{
                    background: on ? "color-mix(in srgb, var(--primary) 10%, var(--panel))" : "var(--panel)",
                    border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
                  }}
                  data-testid={`collect-choice-${entry.kind}`}
                >
                  <span
                    aria-hidden="true"
                    className="mt-0.5 grid h-4 w-4 shrink-0 place-items-center rounded-full"
                    style={{ border: `2px solid ${on ? "var(--primary)" : "var(--border-strong)"}` }}
                  >
                    {on ? <span className="h-2 w-2 rounded-full" style={{ background: "var(--primary)" }} /> : null}
                  </span>
                  <span className="grid min-w-0 flex-1 gap-0.5">
                    <span className="flex flex-wrap items-center gap-1.5">
                      <b className="text-sm" style={{ color: "var(--text)" }}>{choiceTitle(entry, t)}</b>
                      {entry.kind === "renewal" ? <Pill tone="accent">{t("recommended")}</Pill> : null}
                    </span>
                    <span className="text-xs" style={{ color: "var(--muted)" }}>{choiceHint(entry, t)}</span>
                  </span>
                  {amount ? <b className="whitespace-nowrap font-mono text-sm" style={{ color: "var(--text)" }}>{amount}</b> : null}
                </button>
                {on && entry.kind === "package" ? (
                  <label className="grid gap-1 px-1">
                    <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("packagePick")}</span>
                    <Select
                      value={packageId ?? ""}
                      placeholder={t("packageHint")}
                      onValueChange={(value) => {
                        setPackageId(value);
                        setShown({});
                      }}
                      className={fieldInputClass}
                      style={fieldInputStyle(Boolean(shown.package))}
                      aria-invalid={Boolean(shown.package)}
                      data-testid="collect-package"
                    >
                      {(options.data?.packages ?? []).map((entry) => (
                        <option key={entry.id} value={entry.id}>
                          {`${entry.name} · ${formatMoney(locale, entry.price_cents, entry.currency)}`}
                        </option>
                      ))}
                    </Select>
                    {shown.package ? <FieldError id="collect-package-error">{shown.package}</FieldError> : null}
                  </label>
                ) : null}
              </div>
            );
          })}
        </div>
      )}
      {payer.kind === "walk_in" ? (
        <div className="grid gap-1 text-xs" style={{ color: "var(--muted)" }}>
          <span>{t("walkInPackages")}</span>
          <button type="button" onClick={onMakeGuest} className="justify-self-start font-bold" style={{ color: "var(--primary-strong)" }} data-testid="collect-walk-in-guest">
            {t("makeThemGuest")}
          </button>
        </div>
      ) : null}
      {choice?.kind === "free" ? <FreeSaleForm value={free} onChange={setFree} errors={shown} /> : null}
      <BigButton onClick={next} disabled={!choice || options.isPending} testId="collect-continue">
        {t("continue")}
      </BigButton>
    </>
  );
}

function FreeSaleForm({ value, onChange, errors }: { value: FreeSale; onChange: (next: FreeSale) => void; errors: { description?: string; amount?: string } }) {
  const t = useTranslations("Collect");
  return (
    <div className="grid gap-3 rounded-[18px] p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="collect-free-sale">
      <label className="grid gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("description")} <span aria-label={t("required")} style={{ color: "var(--danger)" }}>*</span>
        </span>
        <input
          value={value.description}
          onChange={(event) => onChange({ ...value, description: event.target.value })}
          maxLength={FREE_SALE_MAX}
          placeholder={t("descriptionPlaceholder")}
          className={fieldInputClass}
          style={fieldInputStyle(Boolean(errors.description))}
          aria-invalid={Boolean(errors.description)}
          aria-describedby={errors.description ? "collect-description-error" : "collect-description-hint"}
          data-testid="collect-description"
        />
        {errors.description ? (
          <FieldError id="collect-description-error">{errors.description}</FieldError>
        ) : (
          <span id="collect-description-hint" className="text-xs" style={{ color: "var(--muted)" }}>{t("descriptionHint")}</span>
        )}
      </label>
      <label className="grid gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("amount")} <span aria-label={t("required")} style={{ color: "var(--danger)" }}>*</span>
        </span>
        <span className="relative block">
          <input
            inputMode="decimal"
            value={value.amount}
            onChange={(event) => onChange({ ...value, amount: event.target.value })}
            placeholder="0,00"
            className={`${fieldInputClass} pe-8 font-mono font-bold`}
            style={fieldInputStyle(Boolean(errors.amount))}
            aria-invalid={Boolean(errors.amount)}
            aria-describedby={errors.amount ? "collect-amount-error" : undefined}
            data-testid="collect-amount"
          />
          <span aria-hidden="true" className="pointer-events-none absolute inset-y-0 end-3 grid place-items-center text-sm" style={{ color: "var(--muted)" }}>
            €
          </span>
        </span>
        {errors.amount ? <FieldError id="collect-amount-error">{errors.amount}</FieldError> : null}
      </label>
      <div className="grid gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("category")}</span>
        <div className="flex flex-wrap gap-1.5">
          {CHARGE_CATEGORIES.map((category) => (
            <Chip key={category} on={value.category === category} onClick={() => onChange({ ...value, category })} testId={`collect-category-${category}`}>
              {t(`category_${category}`)}
            </Chip>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Έλεγχος ─────────────────────────────────────────────────────────────

function ConfirmStep({
  payer,
  payerName,
  purchase,
  attemptKey,
  onBack,
  onStarted,
}: {
  payer: Payer;
  payerName: string | null;
  purchase: Purchase;
  attemptKey: string;
  onBack: () => void;
  onStarted: (payment: TerminalPayment) => void;
}) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const userId = payer.kind === "person" ? payer.userId : null;
  const options = useQuery({
    queryKey: ["admin", "payments", "desk", "options", slug, userId ?? "walk_in"],
    enabled: Boolean(token),
    queryFn: () => fetchDeskOptions(token, userId).then((response) => response.options),
  });
  const amount = pickedAmount(purchase, options.data);
  const [launchFailed, setLaunchFailed] = useState(false);
  const charge = useMutation({
    mutationFn: async () => {
      const body = startBody(purchase, payer, options.data, attemptKey);
      if (!body) throw new Error("incomplete");
      const { payment } = await startTerminalPayment(token, body);
      if (!payment.app_request) return payment;
      try {
        await launchTerminalSale(payment.app_request);
      } catch {
        setLaunchFailed(true);
        await cancelTerminalPayment(token, payment.id).catch(() => undefined);
        return null;
      }
      return payment;
    },
    onMutate: () => setLaunchFailed(false),
    onSuccess: (payment) => {
      if (payment) onStarted(payment);
    },
  });

  const what = what_(purchase, options.data, t);

  return (
    <>
      <Crumb title={t("title")} current={t("confirmTitle")} backLabel={t("back")} onBack={onBack} />
      <Card className="text-center" testId="collect-confirm">
        <span className="text-xs" style={{ color: "var(--muted)" }}>{payerLabel(payer, payerName, t)}</span>
        <b className="text-sm" style={{ color: "var(--text)" }}>{what}</b>
        <span className="font-mono text-3xl font-extrabold" style={{ color: "var(--text)" }}>
          {amount ? formatMoney(locale, amount.cents, amount.currency) : "—"}
        </span>
      </Card>
      <span className="text-xs" style={{ color: "var(--muted)" }}>{t("confirmHint")}</span>
      <BigButton onClick={() => charge.mutate()} disabled={!amount || charge.isPending} testId="collect-charge">
        <CollectIcon name="nfc" />
        {charge.isPending ? t("opening") : t("charge", { amount: amount ? formatMoney(locale, amount.cents, amount.currency) : "" })}
      </BigButton>
      {launchFailed ? <FieldError id="collect-launch-error">{t("launchFailed")}</FieldError> : null}
      {charge.isError ? <FieldError id="collect-charge-error">{localizeError(charge.error, i18n)}</FieldError> : null}
    </>
  );
}

function what_(purchase: Purchase, options: DeskOptions | undefined, t: Translate) {
  const { choice } = purchase;
  if (choice.kind === "free") return purchase.free.description.trim();
  if (choice.kind === "package") return options?.packages.find((entry) => entry.id === purchase.packageId)?.name ?? t("package");
  return choiceTitle(choice, t);
}

// ── Επιβεβαιώνουμε με τη Viva… ──────────────────────────────────────────

function WaitStep({ payment, onResult }: { payment: TerminalPayment; onResult: (payment: TerminalPayment) => void }) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  // A page-scoped work queue (ADR-215): asks until Viva's answer is known.
  const poll = useQuery({
    queryKey: ["admin", "payments", "terminal", "payment", slug, payment.id, "wait"],
    enabled: Boolean(token),
    refetchInterval: 4_000,
    queryFn: () => fetchTerminalPayment(token, payment.id).then((response) => response.payment),
  });
  useEffect(() => {
    if (poll.data && outcomeOf(poll.data) !== "waiting") onResult(poll.data);
  }, [poll.data, onResult]);
  const cancel = useMutation({
    mutationFn: () => cancelTerminalPayment(token, payment.id),
    onSuccess: ({ payment: cancelled }) => onResult(cancelled),
  });

  return (
    <Card className="mt-6 text-center" testId="collect-wait">
      <BigMark tone="accent">
        <CollectIcon name="nfc" size={26} />
      </BigMark>
      <b className="text-base" style={{ color: "var(--text)" }}>{t("waitTitle")}</b>
      <span className="text-sm" style={{ color: "var(--muted)" }}>{t("waitHint")}</span>
      <BigButton ghost onClick={() => void poll.refetch()} disabled={poll.isFetching} testId="collect-check-now">
        {t("checkNow")}
      </BigButton>
      <button type="button" onClick={() => cancel.mutate()} disabled={cancel.isPending} className="text-sm font-bold" style={{ color: "var(--danger)" }} data-testid="collect-cancel">
        {t("cancelPayment")}
      </button>
      {cancel.isError ? <FieldError id="collect-cancel-error">{localizeError(cancel.error, i18n)}</FieldError> : null}
    </Card>
  );
}
