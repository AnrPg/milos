"use client";

import { useMutation, useQuery, useQueryClient, type QueryKey } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type FormEvent, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import {
  checkFiscalConnection,
  fetchFiscalConnections,
  saveFiscalConnection,
  type ConnectionKind,
  type ConnectionResult,
  type ConnectionsOverview,
  type FiscalConnection,
  type TillConnection,
} from "@/api/fiscal";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder, formErrorsFrom, invalidFieldProps, type FormErrors } from "@/lib/form-errors";

import {
  checkOutcome,
  CONNECTION_BRANDS,
  CONNECTION_MARKS,
  DEVICE_NAMES,
  draftOf,
  errorField,
  FORM_SHAPES,
  formFields,
  hasSecret,
  knownErrorCode,
  knownSaveError,
  PROVIDER_OF,
  requestedKind,
  rowStatus,
  saveBody,
  saveErrorField,
  type CheckOutcome,
  type Draft,
  type EnvironmentChoice,
  type ErrorCode,
  type FormField,
  type RowStatus,
  type SaveErrorCode,
  type SecretField,
  type TextField,
} from "./connections-model";
import { Card, ghostButtonClass, ghostButtonStyle, dangerButtonStyle, hintStyle, Icon, Pill, primaryButtonStyle } from "./fiscal-ui";

export const FISCAL_CONNECTIONS_KEY = ["admin", "fiscal", "connections"] as const;

type Translate = ReturnType<typeof useTranslations<"FiscalConnections">>;

/** Where a panel saves and checks: the box's own endpoints, or the vendor console's. */
export type ConnectionsApi = {
  queryKey: QueryKey;
  save: (kind: ConnectionKind, body: Record<string, unknown>) => Promise<ConnectionResult>;
  check: (kind: ConnectionKind) => Promise<ConnectionResult>;
};

/**
 * Settings › Στοιχεία τιμολόγησης › «Συνδέσεις» (mockup p3, alternative A;
 * ADR-273): one row per connection the box's country asks for, with its
 * status; a row opens its form in a side panel.
 */
export function FiscalConnectionsCard({ token, countryName }: { token: string; countryName: string }) {
  const t = useTranslations("FiscalConnections");
  const overview = useQuery({
    queryKey: FISCAL_CONNECTIONS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchFiscalConnections(token),
  });
  // A notification links to `?connection=mydata`: that row's panel opens
  // first; `undefined` until the viewer opens or closes one.
  const [requested] = useState(() => (typeof window === "undefined" ? null : new URLSearchParams(window.location.search).get("connection")));
  const [chosen, setOpen] = useState<ConnectionKind | null | undefined>(undefined);
  const open = chosen === undefined ? requestedKind(requested, overview.data?.kinds ?? []) : chosen;

  const api: ConnectionsApi = {
    queryKey: FISCAL_CONNECTIONS_KEY,
    save: (kind, body) => saveFiscalConnection(token, kind, body),
    check: (kind) => checkFiscalConnection(token, kind),
  };

  return (
    <Card testId="fiscal-connections">
      <h2 className="text-base font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h2>
      {overview.isPending ? null : overview.isError ? (
        <ErrorNotice>{t("loadFailed")}</ErrorNotice>
      ) : (
        <>
          <ConnectionRows overview={overview.data} countryName={countryName} selected={open} onOpen={setOpen} />
          {open && overview.data.kinds.includes(open) ? (
            <ConnectionPanel
              kind={open}
              overview={overview.data}
              api={api}
              readOnly={overview.data.managed_by === "palee"}
              onClose={() => setOpen(null)}
            />
          ) : null}
        </>
      )}
    </Card>
  );
}

/** The rows of the card, shared with the vendor console. */
export function ConnectionRows({
  overview,
  countryName,
  selected,
  onOpen,
}: {
  overview: ConnectionsOverview;
  countryName: string;
  selected: ConnectionKind | null;
  onOpen: (kind: ConnectionKind) => void;
}) {
  const t = useTranslations("FiscalConnections");

  if (overview.kinds.length === 0) {
    return (
      <div className="flex items-center gap-3" data-testid="fiscal-connections-none">
        <span style={{ color: "var(--success)" }}><Icon name="check" size={20} /></span>
        <div className="min-w-0 flex-1">
          <b style={{ color: "var(--text)" }}>{t("noneTitle")}</b>
          <p className="text-sm" style={hintStyle}>{t("noneHint", { country: countryName })}</p>
        </div>
      </div>
    );
  }

  return (
    <>
      <p className="text-sm" style={hintStyle}>{t("intro", { country: countryName })}</p>
      {overview.managed_by === "palee" ? (
        <p className="flex items-start gap-1.5 text-sm font-semibold" style={{ color: "var(--text-soft)" }} data-testid="fiscal-connections-managed">
          <Icon name="shield" size={14} />
          {t("managedByPalee")}
        </p>
      ) : null}
      <ul className="grid gap-1.5">
        {overview.kinds.map((kind) => {
          const status = rowStatus(overview.connections[kind]);
          return (
            <li key={kind}>
              <button
                type="button"
                data-testid={`fiscal-connection-${kind}`}
                data-status={status}
                onClick={() => onOpen(kind)}
                className="flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2.5 text-start"
                style={{ background: "var(--panel)", border: `1px solid ${selected === kind ? "var(--primary)" : "var(--border)"}` }}
              >
                <span
                  aria-hidden="true"
                  className="grid h-8 w-8 flex-none place-items-center rounded-lg text-xs font-extrabold"
                  style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
                >
                  {CONNECTION_MARKS[kind]}
                </span>
                <span className="min-w-0 flex-1">
                  <b className="block text-sm" style={{ color: "var(--text)" }}>{connectionName(t, kind)}</b>
                  <span className="block truncate text-xs" style={hintStyle}>{t(`description.${kind}`)}</span>
                </span>
                <StatusPill status={status} testId={statusTestId(kind)} />
                <span aria-hidden="true" style={hintStyle}>›</span>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function statusTestId(kind: ConnectionKind) {
  return ["fiscal-connection", kind, "status"].join("-");
}

function connectionName(t: Translate, kind: ConnectionKind) {
  return CONNECTION_BRANDS[kind] ?? t("registryName");
}

function StatusPill({ status, testId }: { status: RowStatus; testId?: string }) {
  const t = useTranslations("FiscalConnections");
  if (status === "active") {
    return <Pill tone="ok" testId={testId}><Icon name="check" size={11} />{t("status.active")}</Pill>;
  }
  if (status === "invalid") return <Pill tone="bad" testId={testId}>{t("status.invalid")}</Pill>;
  if (status === "provisioning") return <Pill tone="info" testId={testId}>{t("status.provisioning")}</Pill>;
  return <Pill testId={testId}>{t("status.none")}</Pill>;
}

/** A stable error code (ADR-273) in the viewer's words. */
export function errorText(t: Translate, kind: ConnectionKind, code: ErrorCode | SaveErrorCode | null): string {
  switch (code) {
    case null:
      return t("error.generic");
    case "credentials_rejected":
    case "till_credentials_refused":
      return kind === "registry"
        ? t("error.credentials_rejected_registry")
        : PROVIDER_OF[kind] === "aade"
          ? t("error.credentials_rejected_aade")
          : t("error.credentials_rejected_fiskaly");
    case "till_provisioning_failed":
      return t("error.provisioning_failed");
    case "fiscal_connections_managed_by_palee":
      return t("error.managed_by_palee");
    case "connection_not_found":
      return t("check.needsSave");
    default:
      return t(`error.${code}`);
  }
}

function formatWhen(locale: string, iso: string | null | undefined) {
  if (!iso) return null;
  return new Intl.DateTimeFormat(locale, {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(iso));
}

type Notice = { tone: "ok" | "info" | "bad"; text: string };

/** The side panel of one connection (mockup p3): its form, one «Αποθήκευση». */
export function ConnectionPanel({
  kind,
  overview,
  api,
  readOnly,
  onClose,
}: {
  kind: ConnectionKind;
  overview: ConnectionsOverview;
  api: ConnectionsApi;
  readOnly: boolean;
  onClose: () => void;
}) {
  const t = useTranslations("FiscalConnections");
  const translate = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const connection = (overview.connections[kind] ?? null) as FiscalConnection | null;
  const shape = FORM_SHAPES[kind];
  const [draft, setDraft] = useState<Draft>(() => draftOf(kind, connection));
  const [replacing, setReplacing] = useState<Set<SecretField>>(() => new Set());
  const [errors, setErrors] = useState<FormErrors<FormField> | null>(null);
  const [saved, setSaved] = useState<Notice | null>(null);
  const [tested, setTested] = useState<Notice | null>(null);
  const [advanced, setAdvanced] = useState(false);
  const [reprovisionArmed, setReprovisionArmed] = useState(false);
  const status = rowStatus(connection);

  function remember(result: ConnectionResult) {
    queryClient.setQueryData<ConnectionsOverview>(api.queryKey, (current) =>
      current && result.connection
        ? { ...current, connections: { ...current.connections, [kind]: { ...current.connections[kind], ...result.connection } } }
        : current,
    );
    void queryClient.invalidateQueries({ queryKey: api.queryKey });
  }

  function apiFailure(failure: unknown): FormErrors<FormField> {
    const code = failure instanceof ApiError ? knownSaveError(failure.payload.code) : null;
    if (code) {
      const field = saveErrorField(kind, code);
      const text = errorText(t, kind, code);
      return field ? { fields: { [field]: text }, message: null } : { fields: {}, message: text };
    }
    return formErrorsFrom(failure, translate, formFields(kind));
  }

  const save = useMutation({
    mutationFn: (reprovision: boolean) => api.save(kind, saveBody(kind, draft, connection, reprovision)),
    onSuccess: (result) => {
      remember(result);
      setReprovisionArmed(false);
      setTested(null);
      const outcome = checkOutcome(result.check);
      if (outcome?.kind === "invalid") {
        const field = outcome.code ? errorField(kind, outcome.code) : null;
        const text = errorText(t, kind, outcome.code);
        setSaved(null);
        setErrors(field ? { fields: { [field]: text }, message: null } : { fields: {}, message: text });
        return;
      }
      // Saved: what was typed is now a saved secret.
      setDraft({ ...draftOf(kind, result.connection as FiscalConnection | null), environment: draft.environment });
      setReplacing(new Set());
      setErrors(null);
      setSaved(
        outcome?.kind === "unreachable"
          ? { tone: "info", text: unreachableText(t, kind, result.check?.error_code) }
          : { tone: "ok", text: t("saved") },
      );
    },
    onError: (failure) => {
      setSaved(null);
      setReprovisionArmed(false);
      setErrors(apiFailure(failure));
    },
  });

  const check = useMutation({
    mutationFn: () => api.check(kind),
    onSuccess: (result) => {
      remember(result);
      setTested(testNotice(t, kind, checkOutcome(result.check), result.check?.error_code));
    },
    onError: (failure) => setTested({ tone: "bad", text: apiFailure(failure).message ?? t("error.generic") }),
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (readOnly) return;
    setErrors(null);
    setSaved(null);
    save.mutate(false);
  }

  function reprovision() {
    if (!reprovisionArmed) {
      setReprovisionArmed(true);
      return;
    }
    setErrors(null);
    save.mutate(true);
  }

  const setField = (field: TextField | SecretField, value: string) => {
    setDraft((current) => ({ ...current, [field]: value }));
    setSaved(null);
    if (errors?.fields[field]) setErrors({ ...errors, fields: { ...errors.fields, [field]: undefined } });
  };

  const setEnvironment = (environment: EnvironmentChoice) => {
    setDraft((current) => ({ ...current, environment }));
    setSaved(null);
  };

  const updated = formatWhen(locale, connection?.updated_at ?? null);
  const checked = formatWhen(locale, connection?.checked_at ?? null);
  const pending = save.isPending || check.isPending;
  const showInvalid = status === "invalid" && !errors?.message && !Object.values(errors?.fields ?? {}).some(Boolean);
  const device = DEVICE_NAMES[kind];
  const invalidCode = knownErrorCode(connection?.error_code);
  const advancedOpen = advanced || Boolean(errors?.fields.peppol_id || errors?.fields.environment);

  return (
    <Dialog
      variant="panel"
      size="md"
      title={connectionName(t, kind)}
      onClose={onClose}
      onSubmit={submit}
      dismissible={!pending}
      error={errors?.message}
      testId={`fiscal-connection-panel-${kind}`}
      footer={
        readOnly ? (
          <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={onClose}>
            {t("close")}
          </button>
        ) : (
          <>
            <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={onClose} disabled={pending}>
              {t("cancel")}
            </button>
            <button type="submit" className={ghostButtonClass} style={primaryButtonStyle} disabled={pending} data-testid="fiscal-connection-save">
              {save.isPending ? t("saving") : t("save")}
            </button>
          </>
        )
      }
    >
      <div className="grid gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <StatusPill status={status} testId="fiscal-connection-status" />
          {updated ? (
            <span className="text-xs" style={hintStyle} data-testid="fiscal-connection-updated">
              {connection?.updated_by_platform
                ? t("updatedByPalee", { date: updated })
                : connection?.updated_by_name
                  ? t("updated", { date: updated, name: connection.updated_by_name })
                  : t("updatedAt", { date: updated })}
            </span>
          ) : null}
          {checked ? <span className="text-xs" style={hintStyle}>{t("checkedAt", { date: checked })}</span> : null}
        </div>

        {readOnly ? (
          <p className="rounded-xl p-2.5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="fiscal-connection-managed">
            <b>{t("managedByPalee")}</b> {t("managedByPaleeHint")}
          </p>
        ) : null}

        {showInvalid ? (
          <p
            className="rounded-xl p-2.5 text-sm"
            style={{ background: "color-mix(in srgb, var(--danger) 10%, transparent)", color: "var(--text-soft)" }}
            data-testid="fiscal-connection-invalid"
          >
            {errorText(t, kind, invalidCode)} {t("waiting")}
          </p>
        ) : null}

        <p className="text-xs" style={hintStyle}>{t(`help.${helpKey(kind)}`)}</p>

        {shape.text.map((field) => (
          <TextInput
            key={field}
            field={field}
            value={draft[field] ?? ""}
            error={errors?.fields[field]}
            disabled={readOnly}
            onChange={(value) => setField(field, value)}
          />
        ))}
        {shape.secrets.map((field) => (
          <SecretInput
            key={field}
            field={field}
            saved={hasSecret(kind, connection, field)}
            replacing={replacing.has(field)}
            value={draft[field] ?? ""}
            error={errors?.fields[field]}
            disabled={readOnly}
            onReplace={(on) => {
              setReplacing((current) => {
                const next = new Set(current);
                if (on) next.add(field);
                else next.delete(field);
                return next;
              });
              if (!on) setField(field, "");
            }}
            onChange={(value) => setField(field, value)}
          />
        ))}

        {connection && device && status === "active" ? <DeviceInfo kind={kind} device={device} connection={connection as TillConnection} locale={locale} /> : null}

        <div className="rounded-xl" style={{ border: "1px solid var(--border)" }}>
          <button
            type="button"
            className="flex w-full items-center gap-2 px-3 py-2.5 text-start text-sm font-bold"
            style={{ color: "var(--text)" }}
            aria-expanded={advancedOpen}
            onClick={() => setAdvanced((current) => !current)}
            data-testid="fiscal-connection-advanced"
          >
            <span className="flex-1">{t("advanced")}</span>
            <span aria-hidden="true">{advancedOpen ? "▴" : "▾"}</span>
          </button>
          {advancedOpen ? (
            <div className="grid gap-3 px-3 pb-3">
              {shape.advancedText.map((field) => (
                <TextInput
                  key={field}
                  field={field}
                  value={draft[field] ?? ""}
                  error={errors?.fields[field]}
                  disabled={readOnly}
                  onChange={(value) => setField(field, value)}
                />
              ))}
              <EnvironmentChoiceInput
                kind={kind}
                value={draft.environment}
                disabled={readOnly}
                error={errors?.fields.environment}
                onChange={setEnvironment}
              />
              {connection && device && !readOnly ? (
                <div className="flex flex-wrap items-center gap-2 rounded-xl p-2.5" style={{ background: "var(--panel-muted)" }}>
                  <span className="min-w-0 flex-1">
                    <b className="block text-sm" style={{ color: "var(--text)" }}>{t("reprovision.title", { device })}</b>
                    <span className="block text-xs" style={hintStyle}>{t("reprovision.hint")}</span>
                  </span>
                  <button
                    type="button"
                    className={ghostButtonClass}
                    style={dangerButtonStyle}
                    onClick={reprovision}
                    disabled={pending}
                    data-testid="fiscal-connection-reprovision"
                  >
                    {reprovisionArmed ? t("reprovision.confirm") : t("reprovision.action")}
                  </button>
                </div>
              ) : null}
            </div>
          ) : null}
        </div>

        <div className="grid gap-1.5">
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              className={ghostButtonClass}
              style={ghostButtonStyle}
              onClick={() => {
                setTested(null);
                check.mutate();
              }}
              disabled={!connection || pending}
              data-testid="fiscal-connection-check"
            >
              <Icon name="refresh" size={14} />
              {check.isPending ? t("check.running") : t("check.action")}
            </button>
            {!tested ? (
              <span className="text-xs" style={hintStyle}>
                {!connection ? t("check.needsSave") : kind === "registry" ? t("check.registryHint") : null}
              </span>
            ) : null}
          </div>
          {tested ? <NoticeLine notice={tested} testId="fiscal-connection-check-result" /> : null}
        </div>

        {saved ? <NoticeLine notice={saved} testId="fiscal-connection-saved" /> : null}
      </div>
    </Dialog>
  );
}

function helpKey(kind: ConnectionKind) {
  if (kind === "mydata" || kind === "registry" || kind === "peppol") return kind;
  return "fiskaly";
}

function unreachableText(t: Translate, kind: ConnectionKind, code: string | null | undefined) {
  const known = knownErrorCode(code);
  return known && known !== "unreachable" ? `${t("savedUnchecked")} ${errorText(t, kind, known)}` : t("savedUnchecked");
}

function testNotice(t: Translate, kind: ConnectionKind, outcome: CheckOutcome | null, code: string | null | undefined): Notice {
  if (!outcome) return { tone: "bad", text: t("error.generic") };
  if (outcome.kind === "ok") {
    return outcome.registry
      ? { tone: "ok", text: t("check.okRegistry", { taxId: outcome.registry.taxId, name: outcome.registry.name ?? "" }) }
      : { tone: "ok", text: t("check.ok") };
  }
  if (outcome.kind === "invalid") return { tone: "bad", text: errorText(t, kind, outcome.code) };
  const known = knownErrorCode(code);
  return { tone: "info", text: known && known !== "unreachable" ? errorText(t, kind, known) : t("check.unreachable") };
}

function NoticeLine({ notice, testId }: { notice: Notice; testId: string }) {
  const color = notice.tone === "ok" ? "var(--success)" : notice.tone === "bad" ? "var(--danger)" : "var(--text-soft)";
  return (
    <p className="flex items-start gap-1.5 text-xs" style={{ color }} role="status" data-testid={testId} data-tone={notice.tone}>
      {notice.tone === "ok" ? <Icon name="check" size={13} /> : null}
      <span>{notice.text}</span>
    </p>
  );
}

function Field({ id, label, required, error, hint, children }: { id: string; label: string; required?: boolean; error?: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <div className="grid gap-1">
      <label htmlFor={id} className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>
        {label}
        {required ? <span style={{ color: "var(--danger)" }}> *</span> : null}
      </label>
      {children}
      {error ? <FieldError id={`${id}-error`}>{error}</FieldError> : hint ? <span className="text-xs" style={hintStyle}>{hint}</span> : null}
    </div>
  );
}

const inputClass = "min-h-11 w-full rounded-xl px-3 text-sm";

function TextInput({
  field,
  value,
  error,
  disabled,
  onChange,
}: {
  field: TextField;
  value: string;
  error?: string;
  disabled: boolean;
  onChange: (value: string) => void;
}) {
  const t = useTranslations("FiscalConnections");
  const id = `fiscal-connection-${field}`;
  const placeholder = field === "peppol_id" ? undefined : t(`placeholder.${field}`);
  return (
    <Field id={id} label={t(`field.${field}`)} required={field !== "peppol_id"} error={error} hint={field === "peppol_id" ? t("fieldHint.peppol_id") : null}>
      <input
        id={id}
        data-testid={id}
        value={value}
        placeholder={placeholder}
        disabled={disabled}
        autoComplete="off"
        spellCheck={false}
        onChange={(event) => onChange(event.target.value)}
        className={inputClass}
        style={{ background: "var(--bg)", border: fieldBorder(error), color: "var(--text)" }}
        {...invalidFieldProps(error, `${id}-error`)}
      />
    </Field>
  );
}

/** A secret: only «Αποθηκευμένο» and «Αντικατάσταση» once saved; never shown again. */
function SecretInput({
  field,
  saved,
  replacing,
  value,
  error,
  disabled,
  onReplace,
  onChange,
}: {
  field: SecretField;
  saved: boolean;
  replacing: boolean;
  value: string;
  error?: string;
  disabled: boolean;
  onReplace: (on: boolean) => void;
  onChange: (value: string) => void;
}) {
  const t = useTranslations("FiscalConnections");
  const id = `fiscal-connection-${field}`;
  const label = t(`field.${field}`);

  if (saved && !replacing && !error) {
    return (
      <Field id={id} label={label} hint={t("secret.savedHint")}>
        <div
          id={id}
          data-testid={id}
          data-saved="true"
          className="flex min-h-11 items-center gap-2 rounded-xl px-3 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          <Icon name="lock" size={14} />
          <span className="flex-1">{t("secret.saved")}</span>
          {disabled ? null : (
            <button type="button" className="text-sm font-bold" style={{ color: "var(--primary-strong)" }} onClick={() => onReplace(true)} data-testid={`${id}-replace`}>
              {t("secret.replace")}
            </button>
          )}
        </div>
      </Field>
    );
  }

  return (
    <Field id={id} label={label} required error={error} hint={field === "api_key" ? t("fieldHint.api_key") : t("secret.newHint")}>
      <div className="flex items-center gap-2">
        <input
          id={id}
          data-testid={id}
          type="password"
          value={value}
          placeholder={saved ? t("secret.newValue") : t("secret.paste")}
          disabled={disabled}
          autoComplete="new-password"
          spellCheck={false}
          onChange={(event) => onChange(event.target.value)}
          className={inputClass}
          style={{ background: "var(--bg)", border: fieldBorder(error), color: "var(--text)" }}
          {...invalidFieldProps(error, `${id}-error`)}
        />
        {saved ? (
          <button type="button" className="text-sm font-bold" style={{ color: "var(--primary-strong)" }} onClick={() => onReplace(false)}>
            {t("secret.cancelReplace")}
          </button>
        ) : null}
      </div>
    </Field>
  );
}

function EnvironmentChoiceInput({
  kind,
  value,
  disabled,
  error,
  onChange,
}: {
  kind: ConnectionKind;
  value: EnvironmentChoice;
  disabled: boolean;
  error?: string;
  onChange: (value: EnvironmentChoice) => void;
}) {
  const t = useTranslations("FiscalConnections");
  const options: Array<[EnvironmentChoice, string]> = [
    ["production", t("environment.production")],
    ["test", kind === "mydata" ? t("environment.testAade") : t("environment.test")],
  ];
  return (
    <div className="grid gap-1">
      <span className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>{t("field.environment")}</span>
      <div role="radiogroup" aria-label={t("field.environment")} className="inline-flex w-fit rounded-xl p-0.5" style={{ background: "var(--panel-muted)" }}>
        {options.map(([option, label]) => {
          const on = value === option;
          return (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={on}
              disabled={disabled}
              onClick={() => onChange(option)}
              data-testid={`fiscal-connection-env-${option}`}
              className="rounded-lg px-3 py-1.5 text-sm font-bold"
              style={on ? { background: "var(--panel)", color: "var(--text)", boxShadow: "0 0 0 1px var(--border)" } : { color: "var(--text-soft)" }}
            >
              {label}
            </button>
          );
        })}
      </div>
      {error ? <FieldError id="fiscal-connection-environment-error">{error}</FieldError> : <span className="text-xs" style={hintStyle}>{t("environment.testHint")}</span>}
    </div>
  );
}

function DeviceInfo({ kind, device, connection, locale }: { kind: ConnectionKind; device: string; connection: TillConnection; locale: string }) {
  const t = useTranslations("FiscalConnections");
  const short = (value: string | null | undefined) => (value && value.length > 12 ? `${value.slice(0, 6)}…${value.slice(-4)}` : value ?? "");
  const since = formatWhen(locale, connection.provisioned_at ?? null);
  return (
    <dl className="grid gap-1 rounded-xl p-2.5 text-xs" style={{ background: "var(--panel-muted)" }} data-testid="fiscal-connection-device">
      <div className="flex gap-2">
        <dt className="flex-1" style={hintStyle}>{kind === "sign_fr" ? t("device.taxpayer") : t("device.unit", { device })}</dt>
        <dd className="font-mono" style={{ color: "var(--text)" }}>{short(connection.unit_serial ?? connection.unit_id)}</dd>
      </div>
      <div className="flex gap-2">
        <dt className="flex-1" style={hintStyle}>{t("device.register")}</dt>
        <dd className="font-mono" style={{ color: "var(--text)" }}>{short(connection.register_serial ?? connection.register_id)}</dd>
      </div>
      {since ? (
        <div className="flex gap-2">
          <dt className="flex-1" style={hintStyle}>{t("device.since")}</dt>
          <dd className="font-mono" style={{ color: "var(--text)" }}>{since}</dd>
        </div>
      ) : null}
    </dl>
  );
}

