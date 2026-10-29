"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type FormEvent, type ReactNode } from "react";

import {
  fetchFiscalCountries,
  fetchFiscalIdentity,
  lookupRegistryBusiness,
  saveFiscalIdentity,
  type CountryProfile,
  type IdentityStatus,
} from "@/api/fiscal";
import { ApiError } from "@/api/client";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder, formErrorsFrom, invalidFieldProps, type FormErrors } from "@/lib/form-errors";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

import {
  doneGroups,
  draftOf,
  changesFor,
  fromRegistry,
  groupFields,
  GROUPS,
  isValidAfm,
  localTerm,
  progress,
  summaryValues,
  VAT_SCHEMES,
  type Draft,
  type FieldDef,
  type FieldKey,
  type GroupKey,
  type RegistryLater,
  type VatScheme,
} from "./identity-model";
import {
  Card,
  countryName,
  ghostButtonClass,
  ghostButtonStyle,
  hintStyle,
  Icon,
  primaryButtonStyle,
  Ring,
} from "./fiscal-ui";
import { FiscalConnectionsCard } from "./FiscalConnections";

export const FISCAL_IDENTITY_KEY = ["admin", "fiscal", "identity"] as const;
const COUNTRIES_KEY = ["admin", "fiscal", "countries"] as const;

type Panel = "country" | GroupKey | null;

/** Settings › «Στοιχεία τιμολόγησης» (mockup s1, option C; ADR-240, ADR-243, ADR-245). */
export function FiscalIdentitySettings() {
  const t = useTranslations("FiscalIdentity");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const identity = useQuery({ queryKey: FISCAL_IDENTITY_KEY, enabled: Boolean(token), queryFn: () => fetchFiscalIdentity(token) });
  const countries = useQuery({
    queryKey: COUNTRIES_KEY,
    enabled: Boolean(token),
    staleTime: FRESHNESS.reference,
    queryFn: () => fetchFiscalCountries(token),
  });

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-4 pb-24">
        <BackLink href={adminHref("/admin/settings", slug)} className="self-start text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
          {t("backToSettings")}
        </BackLink>
        {identity.isPending || countries.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : identity.isError || countries.isError ? (
          <ErrorNotice>{t("loadFailed")}</ErrorNotice>
        ) : (
          <Checklist token={token} status={identity.data} profiles={countries.data.countries} />
        )}
      </div>
    </main>
  );
}

function Checklist({ token, status, profiles }: { token: string; status: IdentityStatus; profiles: CountryProfile[] }) {
  const t = useTranslations("FiscalIdentity");
  const locale = useUiLocale();
  const [panel, setPanel] = useState<Panel>(null);
  const saved = status.identity;
  const country = saved?.country_code ?? null;
  const profile = profiles.find((entry) => entry.country === country) ?? status.profile ?? null;
  const draft = draftOf(saved);
  const scheme = (saved?.vat_scheme ?? "standard") as VatScheme;
  const groups = profile ? groupFields(profile, scheme) : null;
  const done = doneGroups(status);
  const percent = progress(status);
  const nextGroup = country ? GROUPS.find((group) => !done.has(group)) ?? null : null;
  const currency = profile?.currency ?? "";

  return (
    <>
      <header className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="text-xs" style={hintStyle}>
            {t("crumbSettings")} › <b style={{ color: "var(--text)" }}>{t("title")}</b>
          </p>
          <h1 className="mt-1 text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h1>
          <p className="text-sm" style={hintStyle}>{t("intro")}</p>
        </div>
        <Ring percent={percent} label={t("progress", { percent })} />
      </header>

      {status.complete && saved ? (
        <Card style={{ borderColor: "var(--success)" }} testId="fiscal-identity-ready">
          <div className="flex items-center gap-3">
            <span style={{ color: "var(--success)" }}><Icon name="check" size={22} /></span>
            <div className="min-w-0 flex-1">
              <b style={{ color: "var(--text)" }}>{t("ready")}</b>
              <p className="text-sm" style={hintStyle}>
                {countryName(locale, saved.country_code)} · {saved.legal_name}
              </p>
            </div>
          </div>
        </Card>
      ) : null}

      <Card>
        <ol className="grid gap-1" data-testid="fiscal-identity-checklist">
          <Row
            testId="fiscal-row-country"
            status={country ? "done" : "next"}
            marker={country ? <Icon name="check" size={12} /> : "1"}
            title={t("rowCountry")}
            detail={country ? t("countryDone", { country: countryName(locale, country), currency }) : t("countryStart")}
            action={country ? t("change") : t("choose")}
            onOpen={() => setPanel("country")}
          />
          {GROUPS.map((group, index) => {
            const fields = groups?.[group] ?? [];
            const isDone = done.has(group);
            const locked = !country;
            const detail = locked
              ? t("afterCountry")
              : isDone
                ? summaryValues(fields, draft).join(" · ") || t(`scheme.${scheme}`)
                : fields.filter((field) => field.required).map((field) => fieldLabel(t, country!, field.key)).join(", ");
            return (
              <Row
                key={group}
                testId={`fiscal-row-${group}`}
                status={locked ? "locked" : isDone ? "done" : nextGroup === group ? "next" : "open"}
                marker={isDone ? <Icon name="check" size={12} /> : locked ? <Icon name="lock" size={11} /> : String(index + 2)}
                title={t(`group.${group}`)}
                detail={detail}
                action={locked ? null : isDone ? t("change") : t("fill")}
                onOpen={locked ? undefined : () => setPanel(group)}
              />
            );
          })}
        </ol>
        <p className="flex items-start gap-1.5 text-xs" style={hintStyle}>
          <Icon name="shield" size={13} />
          {t("legalNote")}
        </p>
      </Card>

      {country ? <FiscalConnectionsCard token={token} countryName={countryName(locale, country)} /> : null}

      {panel === "country" ? (
        <CountryPanel token={token} current={country} profiles={profiles} onClose={() => setPanel(null)} />
      ) : null}
      {panel && panel !== "country" && groups && country ? (
        <GroupPanel
          token={token}
          group={panel}
          country={country}
          profile={profile!}
          initial={draft}
          onClose={() => setPanel(null)}
        />
      ) : null}
    </>
  );
}

type RowState = "done" | "next" | "open" | "locked";

function Row({
  status: state,
  marker,
  title,
  detail,
  action,
  onOpen,
  testId,
}: {
  status: RowState;
  marker: ReactNode;
  title: string;
  detail: string;
  action: string | null;
  onOpen?: () => void;
  testId: string;
}) {
  const doneState = state === "done";
  return (
    <li>
      <button
        type="button"
        data-testid={testId}
        data-state={state}
        disabled={!onOpen}
        onClick={onOpen}
        className="flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2.5 text-start disabled:cursor-default"
        style={{
          background: "var(--panel)",
          border: `1px solid ${state === "next" ? "var(--primary)" : "var(--border)"}`,
          opacity: state === "locked" ? 0.55 : 1,
        }}
      >
        <span
          aria-hidden="true"
          className="grid h-[22px] w-[22px] flex-none place-items-center rounded-full text-[11px] font-extrabold"
          style={
            doneState
              ? { background: "var(--success)", color: "var(--success-contrast)", border: "2px solid var(--success)" }
              : { border: "2px solid var(--border-strong)", color: "var(--text-soft)" }
          }
        >
          {marker}
        </span>
        <span className="min-w-0 flex-1">
          <b className="block text-sm" style={{ color: "var(--text)" }}>{title}</b>
          <span className="block truncate text-xs" style={hintStyle}>{detail}</span>
        </span>
        {action ? <span className="text-sm font-bold" style={{ color: "var(--primary-strong)" }}>{action}</span> : null}
      </button>
    </li>
  );
}

type Translate = ReturnType<typeof useTranslations<"FiscalIdentity">>;

function fieldLabel(t: Translate, country: string, key: FieldKey) {
  const label = t(`field.${key}`);
  const term = localTerm(country, key);
  return term && !label.includes(term) ? `${label} (${term})` : label;
}

function CountryPanel({
  token,
  current,
  profiles,
  onClose,
}: {
  token: string;
  current: string | null;
  profiles: CountryProfile[];
  onClose: () => void;
}) {
  const t = useTranslations("FiscalIdentity");
  const translate = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [picked, setPicked] = useState<string | null>(current);
  const [error, setError] = useState<string | null>(null);
  const save = useMutation({
    mutationFn: (country: string) => saveFiscalIdentity(token, { country_code: country }),
    onSuccess: (data) => {
      queryClient.setQueryData(FISCAL_IDENTITY_KEY, data);
      onClose();
    },
    onError: (failure) => setError(formErrorsFrom(failure, translate, []).message),
  });

  function finish() {
    if (picked && picked !== current) save.mutate(picked);
    else onClose();
  }

  return (
    <Dialog
      variant="panel"
      size="md"
      title={t("countryPanelTitle")}
      onClose={onClose}
      dismissible={!save.isPending}
      error={error}
      testId="fiscal-country-panel"
      footer={
        <button type="button" className={ghostButtonClass} style={primaryButtonStyle} onClick={finish} disabled={save.isPending} data-testid="fiscal-country-done">
          {t("done")}
        </button>
      }
    >
      <p className="mb-3 text-sm" style={hintStyle}>
        {t("countryPanelHint")} {current ? <b>{t("countryChangeWarning")}</b> : null}
      </p>
      <div role="radiogroup" aria-label={t("rowCountry")} className="grid gap-1.5">
        {profiles.map((profile) => {
          const on = picked === profile.country;
          return (
            <button
              key={profile.country}
              type="button"
              role="radio"
              aria-checked={on}
              data-testid={`fiscal-country-${profile.country}`}
              onClick={() => setPicked(profile.country)}
              className="flex items-center gap-2.5 rounded-[14px] p-2.5 text-start"
              style={{
                background: "var(--panel)",
                border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
                boxShadow: on ? "inset 0 0 0 1px var(--primary)" : undefined,
              }}
            >
              <span
                aria-hidden="true"
                className="h-4 w-4 flex-none rounded-full"
                style={{ border: `2px solid ${on ? "var(--primary)" : "var(--border-strong)"}`, boxShadow: on ? "inset 0 0 0 3px var(--panel)" : undefined, background: on ? "var(--primary)" : "transparent" }}
              />
              <span className="min-w-0 flex-1">
                <b className="block text-sm" style={{ color: "var(--text)" }}>{countryName(locale, profile.country)}</b>
                <span className="text-xs" style={hintStyle}>{profile.currency}</span>
              </span>
              <span className="font-mono text-xs" style={hintStyle}>{profile.country}</span>
            </button>
          );
        })}
      </div>
    </Dialog>
  );
}

function GroupPanel({
  token,
  group,
  country,
  profile,
  initial,
  onClose,
}: {
  token: string;
  group: GroupKey;
  country: string;
  profile: CountryProfile;
  initial: Draft;
  onClose: () => void;
}) {
  const t = useTranslations("FiscalIdentity");
  const translate = useUiTranslations();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<Draft>(() => ({ vat_scheme: "standard", ...initial }));
  const [errors, setErrors] = useState<FormErrors<FieldKey> | null>(null);
  const scheme = (draft.vat_scheme ?? "standard") as VatScheme;
  const fields: FieldDef[] = groupFields(profile, scheme)[group];
  // «Συμπλήρωση από το ΑΦΜ» (ADR-265): Greek businesses, business row only.
  const offersLookup = group === "business" && country === "GR";
  const [found, setFound] = useState<{ later: RegistryLater } | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);

  const lookup = useMutation({
    mutationFn: () => lookupRegistryBusiness(token, (draft.tax_id ?? "").trim()),
    onSuccess: ({ business }) => {
      const { shown, later } = fromRegistry(business, draft);
      setDraft((current) => ({ ...current, ...shown }));
      setFound({ later });
      setErrors(null);
    },
    onError: (failure) => {
      const code = failure instanceof ApiError ? failure.payload.code : undefined;
      setLookupError(
        code && (REGISTRY_ERRORS as readonly string[]).includes(code)
          ? t(`registry.error.${code as (typeof REGISTRY_ERRORS)[number]}`)
          : formErrorsFrom(failure, translate, []).message,
      );
    },
  });

  const save = useMutation({
    // What the registry gave for later rows (address, ΚΑΔ) is saved with this one.
    mutationFn: () => saveFiscalIdentity(token, { ...changesFor(fields, draft, country), ...(found?.later ?? {}) }),
    onSuccess: (data) => {
      queryClient.setQueryData(FISCAL_IDENTITY_KEY, data);
      onClose();
    },
    onError: (failure) =>
      setErrors(
        formErrorsFrom(
          failure,
          translate,
          fields.map((field) => field.key),
          { overrides: Object.fromEntries(fields.map((field) => [field.key, (reason: string) => reasonText(t, reason)])) },
        ),
      ),
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErrors(null);
    save.mutate();
  }

  const set = (key: FieldKey, value: string) => {
    setDraft((current) => ({ ...current, [key]: value }));
    if (key === "tax_id") {
      setFound(null);
      setLookupError(null);
    }
    if (errors?.fields[key]) setErrors({ ...errors, fields: { ...errors.fields, [key]: undefined } });
  };

  return (
    <Dialog
      variant="panel"
      size="md"
      title={t(`group.${group}`)}
      onClose={onClose}
      onSubmit={submit}
      dismissible={!save.isPending}
      error={errors?.message}
      testId={`fiscal-panel-${group}`}
      footer={
        <>
          <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={onClose} disabled={save.isPending}>
            {t("cancel")}
          </button>
          <button type="submit" className={ghostButtonClass} style={primaryButtonStyle} disabled={save.isPending} data-testid="fiscal-panel-save">
            {save.isPending ? t("saving") : t("save")}
          </button>
        </>
      }
    >
      <div className="grid gap-3">
        {fields.map((field) => (
          <FieldInput
            key={field.key}
            field={field}
            country={country}
            value={draft[field.key] ?? ""}
            error={errors?.fields[field.key]}
            onChange={(value) => set(field.key, value)}
            taxId={draft.tax_id ?? ""}
          >
            {offersLookup && field.key === "tax_id" ? (
              <RegistryLookup
                ready={isValidAfm(draft.tax_id ?? "")}
                pending={lookup.isPending}
                found={found !== null}
                foundLater={Object.keys(found?.later ?? {}).length > 0}
                error={lookupError}
                onLookup={() => {
                  setLookupError(null);
                  lookup.mutate();
                }}
              />
            ) : null}
          </FieldInput>
        ))}
      </div>
    </Dialog>
  );
}

function FieldInput({
  field,
  country,
  value,
  error,
  onChange,
  taxId,
  children,
}: {
  field: FieldDef;
  country: string;
  value: string;
  error?: string;
  onChange: (value: string) => void;
  taxId: string;
  children?: ReactNode;
}) {
  const t = useTranslations("FiscalIdentity");
  const id = `fiscal-field-${field.key}`;
  const errorId = `${id}-error`;
  const label = fieldLabel(t, country, field.key);
  const hint = fieldHint(t, field.key, country, value, taxId);
  const inputStyle = { background: "var(--bg)", border: fieldBorder(error), color: "var(--text)" };

  return (
    <div className="grid gap-1">
      <label htmlFor={id} className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>
        {label}
        {field.required ? <span style={{ color: "var(--danger)" }}> *</span> : null}
      </label>
      {field.key === "vat_scheme" ? (
        <Select
          id={id}
          data-testid={id}
          value={value || "standard"}
          onValueChange={onChange}
          className="min-h-11 w-full rounded-xl px-3 text-sm"
          style={inputStyle}
          {...invalidFieldProps(error, errorId)}
        >
          {VAT_SCHEMES.map((scheme) => (
            <option key={scheme} value={scheme}>{t(`scheme.${scheme}`)}</option>
          ))}
        </Select>
      ) : (
        <input
          id={id}
          data-testid={id}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          inputMode={field.key === "branch_code" ? "numeric" : undefined}
          autoComplete="off"
          className="min-h-11 w-full rounded-xl px-3 text-sm"
          style={inputStyle}
          {...invalidFieldProps(error, errorId)}
        />
      )}
      {error ? <FieldError id={errorId}>{error}</FieldError> : hint ? <span className="text-xs" style={hintStyle}>{hint}</span> : null}
      {children}
    </div>
  );
}

const REGISTRY_ERRORS = [
  "invalid_tax_id",
  "registry_not_connected",
  "registry_credentials_rejected",
  "registry_not_found",
  "registry_limit_reached",
  "registry_unavailable",
] as const;

/** Mockup s1 C: «Συμπλήρωση από το ΑΦΜ» under the ΑΦΜ, once its check digit is right. */
function RegistryLookup({
  ready,
  pending,
  found,
  foundLater,
  error,
  onLookup,
}: {
  ready: boolean;
  pending: boolean;
  found: boolean;
  foundLater: boolean;
  error: string | null;
  onLookup: () => void;
}) {
  const t = useTranslations("FiscalIdentity");
  return (
    <div className="mt-1 grid gap-1.5" data-testid="fiscal-registry">
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          className={ghostButtonClass}
          style={ghostButtonStyle}
          onClick={onLookup}
          disabled={!ready || pending}
          data-testid="fiscal-registry-lookup"
        >
          <Icon name="search" size={14} />
          {pending ? t("registry.looking") : t("registry.lookup")}
        </button>
        <span className="text-xs" style={hintStyle}>{t("registry.orByHand")}</span>
      </div>
      {error ? (
        <FieldError id="fiscal-registry-error">{error}</FieldError>
      ) : found ? (
        <p className="grid gap-0.5 text-xs" role="status" data-testid="fiscal-registry-found">
          <span className="flex items-center gap-1.5" style={{ color: "var(--success)" }}>
            <Icon name="check" size={13} />
            {t("registry.found")}
          </span>
          {foundLater ? <span style={hintStyle}>{t("registry.foundLater")}</span> : null}
        </p>
      ) : null}
    </div>
  );
}

function fieldHint(t: Translate, key: FieldKey, country: string, value: string, taxId: string): string | null {
  switch (key) {
    case "tax_id":
      return country === "GR" && isValidAfm(value) ? t("hint.checkDigitsOk") : t("hint.checkDigits");
    case "vat_number":
      return t("hint.checkDigits");
    case "vat_scheme":
      return country === "GR" && (value || "standard") === "standard" && taxId.trim()
        ? t("hint.greekVatNumber", { number: `EL${taxId.trim()}` })
        : null;
    case "branch_code":
      return t("hint.branchCode");
    case "trade_name":
      return t("hint.optional");
    case "iban":
      return t("hint.iban");
    case "qr_iban":
      return t("hint.qrIban");
    default:
      return null;
  }
}

const REASONS = [
  "blank",
  "check_digit",
  "format",
  "not_applicable",
  "too_long",
  "invalid",
  "invalid_iban",
  "qr_iban_in_iban_field",
  "qr_iban_country",
  "not_a_qr_iban",
] as const;

function reasonText(t: Translate, reason: string): string | null {
  return (REASONS as readonly string[]).includes(reason) ? t(`reason.${reason as (typeof REASONS)[number]}`) : null;
}
