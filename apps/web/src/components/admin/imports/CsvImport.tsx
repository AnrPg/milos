"use client";

import { keepPreviousData, useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState, type CSSProperties, type DragEvent, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import {
  applyImport,
  deleteImport,
  fetchImport,
  fetchImportCatalog,
  fetchImportRows,
  listImports,
  previewImport,
  sendImportInvitations,
  undoImport,
  uploadImport,
  type ImportDateOrder,
  type ImportField,
  type ImportInvitations,
  type ImportMappingEntry,
  type ImportRow,
  type ImportRowFilters,
  type ImportSource,
  type PeopleImport,
} from "@/api/imports";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";
import { SPARK_GO_STYLE } from "@/lib/spark";

import { LineIcon } from "./ImportIcons";
import {
  applyAnswer,
  applyProgress,
  canUndo,
  decisionKey,
  deriveDecisions,
  fieldOfColumn,
  peopleToImport,
  phaseOf,
  previewKpis,
  reportOf,
  sameMapping,
  setColumnField,
  skippedRowsCsv,
  type Answers,
  type Decision,
} from "./import-model";

// Staff › Χρήστες › Εισαγωγή (ADR-254), mockup s9 option B: drop the file,
// the source is recognised and the dry run runs at once; the owner answers
// only the cards that need a person, the full column mapping is one expand
// away, and «Εισαγωγή» applies it in the background.

const KEY = ["admin", "imports"] as const;
const SAMPLE_ROWS = 500;
const POLL_MS = 2000;

const FIELDS: ImportField[] = [
  "full_name", "first_name", "last_name", "email", "phone", "role", "joined_on", "membership_status", "notes", "external_id",
  "package_name", "package_price", "package_starts_on", "package_ends_on", "credit_balance",
  "payment_amount", "payment_date", "payment_method", "payment_note", "visit_date",
];
const DATE_FIELDS = new Set<ImportField>(["joined_on", "package_starts_on", "package_ends_on", "payment_date", "visit_date"]);
const DATE_ORDERS: ImportDateOrder[] = ["dmy", "mdy", "ymd"];
const ERROR_CODES = new Set([
  "import_file_missing", "file_too_large", "empty_file", "no_rows", "too_many_rows", "unbalanced_quotes", "invalid_source",
  "invalid_mapping", "invalid_date_order", "import_not_editable", "import_not_applicable", "import_already_applied",
  "import_not_applied", "import_already_undone", "undo_window_closed", "undo_incomplete", "business_not_activated",
]);
const ISSUE_CODES = new Set([
  "invalid_email", "invalid_phone", "invalid_date", "invalid_amount", "invalid_role", "invalid_status", "negative_balance",
  "payment_without_date", "package_created", "subscription_exists", "visit_exists", "credit_already_imported", "not_a_client",
  "undecodable_bytes", "missing_person", "missing_name",
]);

const card: CSSProperties = { background: "var(--panel)", border: "1px solid var(--border)" };
const highlighted: CSSProperties = { background: "var(--panel)", border: "1px solid var(--primary)", boxShadow: "inset 0 0 0 1px var(--primary)" };
const quiet: CSSProperties = { color: "var(--muted)" };
const ghostButton = "inline-flex min-h-10 items-center gap-2 rounded-full px-4 text-sm font-semibold disabled:opacity-50";
const ghostStyle: CSSProperties = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };
const primaryButton = "inline-flex min-h-10 items-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-50";
const primaryStyle: CSSProperties = { background: "var(--primary)", color: "var(--primary-contrast)" };

type T = ReturnType<typeof useTranslations>;

function useErrorText() {
  const t = useTranslations("CsvImport");
  const i18n = useUiTranslations();
  return (error: unknown) => {
    const code = error instanceof ApiError ? error.payload.code : undefined;
    if (code && ERROR_CODES.has(code)) return t(`errors.${code}`);
    return localizeError(error, i18n);
  };
}

function Chip({ on, onClick, children, testId }: { on: boolean; onClick: () => void; children: ReactNode; testId?: string }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      data-testid={testId}
      onClick={onClick}
      className="inline-flex min-h-9 items-center rounded-full px-3 text-xs font-bold"
      style={
        on
          ? { color: "var(--text)", border: "1px solid var(--primary)", background: "color-mix(in srgb, var(--primary) 12%, var(--panel))" }
          : { color: "var(--dim)", border: "1px solid var(--border)", background: "var(--panel)" }
      }
    >
      {children}
    </button>
  );
}

function Done() {
  return (
    <span
      className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full"
      style={{ background: "color-mix(in srgb, var(--success) 14%, transparent)", color: "var(--success)" }}
    >
      <LineIcon name="check" size={13} />
    </span>
  );
}

function issueText(t: T, code: string) {
  return ISSUE_CODES.has(code) ? t(`issues.${code}`) : code;
}

function rowIssues(t: T, row: ImportRow) {
  const codes = [...row.errors.map((issue) => issue.code), ...row.warnings.map((issue) => issue.code)];
  if (row.error_code) codes.push(row.error_code);
  return [...new Set(codes)].map((code) => issueText(t, code)).join(" · ");
}

function rowPerson(mapping: ImportMappingEntry[], row: ImportRow) {
  const cell = (field: ImportField) => {
    const column = mapping.find((entry) => entry.field === field)?.column;
    return column === undefined ? "" : (row.cells[column] ?? "").trim();
  };
  const name = cell("full_name") || [cell("first_name"), cell("last_name")].filter(Boolean).join(" ");
  return [name, cell("email") || cell("phone")].filter(Boolean).join(" · ");
}

function sourceName(t: T, source: ImportSource) {
  return t(`sources.${source}`);
}

// ── Page ─────────────────────────────────────────────────────────────────────

export function CsvImport() {
  const t = useTranslations("CsvImport");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const id = params.get("import");
  // The file stays in memory for «Άλλο σύστημα» (upload again with another preset).
  const fileRef = useRef<File | null>(null);
  const supportEmail = process.env.NEXT_PUBLIC_SUPPORT_EMAIL;

  const open = (next: string | null) => router.replace(next ? `${pathname}?import=${next}` : pathname);

  return (
    <main className="min-h-screen px-4 py-8 sm:px-6 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4 pb-24">
        <nav aria-label={t("crumbLabel")} className="text-sm" style={quiet}>
          <Link href={adminHref("/admin/users", slug)} className="hover:underline">
            {t("crumbUsers")}
          </Link>{" "}
          › <b style={{ color: "var(--text)" }}>{t("crumbImport")}</b>
        </nav>
        <header className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-2xl font-semibold tracking-tight md:text-3xl" style={{ color: "var(--text)" }}>
            {t("title")}
          </h1>
          {supportEmail ? (
            <a
              href={`mailto:${supportEmail}?subject=${encodeURIComponent(t("helpSubject"))}`}
              className="inline-flex items-center gap-1.5 text-sm font-semibold"
              style={{ color: "var(--primary)" }}
            >
              <LineIcon name="chat" size={14} /> {t("help")}
            </a>
          ) : null}
        </header>
        {!token ? (
          <p className="text-sm" style={quiet}>{t("loading")}</p>
        ) : id ? (
          <ImportView key={id} token={token} id={id} fileRef={fileRef} onOpen={open} />
        ) : (
          <StartView token={token} fileRef={fileRef} onOpen={open} />
        )}
      </div>
    </main>
  );
}

// ── Start: drop the file ─────────────────────────────────────────────────────

function StartView({
  token,
  fileRef,
  onOpen,
}: {
  token: string;
  fileRef: React.MutableRefObject<File | null>;
  onOpen: (id: string | null) => void;
}) {
  const t = useTranslations("CsvImport");
  const errorText = useErrorText();
  const queryClient = useQueryClient();
  const locale = useUiLocale();
  const [dragging, setDragging] = useState(false);
  const imports = useQuery({ queryKey: [...KEY, "list"], queryFn: () => listImports(token), staleTime: FRESHNESS.live });

  const upload = useMutation({
    mutationFn: async (file: File) => {
      fileRef.current = file;
      const created = await uploadImport(token, file, null);
      return previewImport(token, created.id);
    },
    onSuccess: (entry) => {
      queryClient.setQueryData([...KEY, entry.id], entry);
      void queryClient.invalidateQueries({ queryKey: [...KEY, "list"] });
      onOpen(entry.id);
    },
  });

  const take = (files: FileList | null) => {
    const file = files?.[0];
    if (file && !upload.isPending) upload.mutate(file);
  };

  const onDrop = (event: DragEvent<HTMLLabelElement>) => {
    event.preventDefault();
    setDragging(false);
    take(event.dataTransfer.files);
  };

  const dateFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium" });
  const previous = imports.data ?? [];

  return (
    <>
      <label
        data-testid="import-drop"
        onDragOver={(event) => {
          event.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        className="grid cursor-pointer place-items-center gap-2 rounded-2xl px-4 py-10 text-center"
        style={{
          background: dragging ? "color-mix(in srgb, var(--primary) 6%, var(--panel))" : "var(--panel)",
          border: `2px dashed ${dragging ? "var(--primary)" : "var(--border-strong)"}`,
          color: "var(--muted)",
        }}
      >
        <span style={{ color: "var(--primary)" }}>
          <LineIcon name="upload" size={30} />
        </span>
        <b className="text-base" style={{ color: "var(--text)" }}>
          {upload.isPending ? t("uploading") : t("dropTitle")}
        </b>
        <span className="text-sm">{t("dropHint")}</span>
        <input
          type="file"
          accept=".csv,.txt,text/csv,text/plain"
          aria-label={t("dropChoose")}
          className="sr-only"
          disabled={upload.isPending}
          onChange={(event) => {
            take(event.target.files);
            event.target.value = "";
          }}
        />
      </label>
      {upload.error ? <ErrorNotice>{errorText(upload.error)}</ErrorNotice> : null}
      <p className="text-sm" style={quiet}>{t("nothingChanges")}</p>

      {previous.length > 0 ? (
        <section className="space-y-2 rounded-2xl p-4" style={card} aria-labelledby="import-previous">
          <h2 id="import-previous" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("previous")}
          </h2>
          <ul className="divide-y" style={{ borderColor: "var(--border)" }}>
            {previous.map((entry) => (
              <li key={entry.id}>
                <button
                  type="button"
                  onClick={() => onOpen(entry.id)}
                  className="flex w-full items-center justify-between gap-3 py-2.5 text-start"
                >
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{entry.filename}</span>
                    <span className="block text-xs" style={quiet}>
                      {entry.inserted_at ? dateFormat.format(new Date(entry.inserted_at)) : null} · {t(`status.${entry.status}`)}
                    </span>
                  </span>
                  <span aria-hidden="true" style={quiet}>›</span>
                </button>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </>
  );
}

// ── One import ───────────────────────────────────────────────────────────────

function ImportView({
  token,
  id,
  fileRef,
  onOpen,
}: {
  token: string;
  id: string;
  fileRef: React.MutableRefObject<File | null>;
  onOpen: (id: string | null) => void;
}) {
  const t = useTranslations("CsvImport");
  const errorText = useErrorText();
  const queryClient = useQueryClient();
  const entryQuery = useQuery({
    queryKey: [...KEY, id],
    queryFn: () => fetchImport(token, id),
    refetchInterval: (query) => (query.state.data && phaseOf(query.state.data) === "applying" ? POLL_MS : false),
  });
  const entry = entryQuery.data;
  const phase = entry ? phaseOf(entry) : null;

  // A draft opened again without its dry run (the page was closed in between) runs it now.
  const dryRun = useMutation({
    mutationFn: () => previewImport(token, id),
    onSuccess: (next) => queryClient.setQueryData([...KEY, id], next),
  });
  const needsDryRun = entry && phase === "review" && !entry.preview;
  useEffect(() => {
    if (needsDryRun && dryRun.isIdle) dryRun.mutate();
  }, [needsDryRun, dryRun]);

  const sample = useQuery({
    queryKey: [...KEY, id, "sample", entry?.previewed_at ?? null],
    queryFn: () => fetchImportRows(token, id, { limit: SAMPLE_ROWS }),
    enabled: phase === "review" && Boolean(entry?.preview),
    placeholderData: keepPreviousData,
  });

  if (entryQuery.error) {
    return (
      <div className="space-y-3">
        <ErrorNotice>{errorText(entryQuery.error)}</ErrorNotice>
        <button type="button" className={ghostButton} style={ghostStyle} onClick={() => onOpen(null)}>
          {t("newImport")}
        </button>
      </div>
    );
  }
  if (dryRun.error) return <ErrorNotice>{errorText(dryRun.error)}</ErrorNotice>;
  if (!entry || (phase === "review" && !sample.data)) {
    return <p className="text-sm" style={quiet}>{t("checking")}</p>;
  }

  if (phase === "review") {
    return <ReviewView token={token} entry={entry} sample={sample.data!.rows} fileRef={fileRef} onOpen={onOpen} />;
  }
  if (phase === "applying") return <ApplyingView entry={entry} />;
  if (phase === "undone") return <UndoneView onOpen={onOpen} />;
  return <DoneView token={token} entry={entry} onOpen={onOpen} />;
}

// ── Review: the dry run and the cards that need the owner ────────────────────

function ReviewView({
  token,
  entry,
  sample,
  fileRef,
  onOpen,
}: {
  token: string;
  entry: PeopleImport;
  sample: ImportRow[];
  fileRef: React.MutableRefObject<File | null>;
  onOpen: (id: string | null) => void;
}) {
  const t = useTranslations("CsvImport");
  const errorText = useErrorText();
  const queryClient = useQueryClient();
  // Worked out once from the first dry run, so an answer never makes its own card disappear.
  const [decisions] = useState<Decision[]>(() => deriveDecisions(entry, sample));
  const [original] = useState<ImportMappingEntry[]>(() => entry.mapping);
  const [mapping, setMapping] = useState<ImportMappingEntry[]>(() => entry.mapping);
  const [dateOrder, setDateOrder] = useState<ImportDateOrder>(entry.date_order);
  const [answers, setAnswers] = useState<Answers>({});
  const [mapOpen, setMapOpen] = useState(false);
  const [rowsOpen, setRowsOpen] = useState(false);
  const [systemOpen, setSystemOpen] = useState(false);

  const catalog = useQuery({ queryKey: [...KEY, "catalog"], queryFn: () => fetchImportCatalog(token), staleTime: FRESHNESS.reference });

  const rerun = useMutation({
    mutationFn: (next: { mapping: ImportMappingEntry[]; date_order: ImportDateOrder }) => previewImport(token, entry.id, next),
    onSuccess: (next) => queryClient.setQueryData([...KEY, entry.id], next),
  });

  const run = (nextMapping: ImportMappingEntry[], nextOrder: ImportDateOrder = dateOrder) => {
    setMapping(nextMapping);
    setDateOrder(nextOrder);
    if (!sameMapping(nextMapping, entry.mapping) || nextOrder !== entry.date_order) {
      rerun.mutate({ mapping: nextMapping, date_order: nextOrder });
    }
  };

  const answer = (decision: Decision, value: string) => {
    setAnswers((current) => ({ ...current, [decisionKey(decision)]: value }));
    if (value === "map") setMapOpen(true);
    run(applyAnswer(mapping, original, decision, value));
  };

  const apply = useMutation({
    mutationFn: () => applyImport(token, entry.id),
    onSuccess: (next) => {
      queryClient.setQueryData([...KEY, entry.id], next);
      void queryClient.invalidateQueries({ queryKey: [...KEY, "list"] });
    },
  });

  const discard = useMutation({
    mutationFn: () => deleteImport(token, entry.id),
    onSuccess: () => {
      fileRef.current = null;
      void queryClient.invalidateQueries({ queryKey: [...KEY, "list"] });
      onOpen(null);
    },
  });

  const reupload = useMutation({
    mutationFn: async (source: ImportSource) => {
      const file = fileRef.current;
      if (!file) throw new Error("import_file_missing");
      const created = await uploadImport(token, file, source);
      const previewed = await previewImport(token, created.id);
      await deleteImport(token, entry.id).catch(() => undefined);
      return previewed;
    },
    onSuccess: (next) => {
      queryClient.setQueryData([...KEY, next.id], next);
      onOpen(next.id);
    },
  });

  const kpis = previewKpis(entry);
  const count = peopleToImport(entry);
  const left = decisions.filter((decision) => !answers[decisionKey(decision)]).length;
  const ready = left === 0 && count > 0 && !rerun.isPending;
  const sampleCell = (column: number) => sample.map((row) => row.cells[column]?.trim()).find((cell) => cell) ?? null;
  const datesMapped = mapping.some((entry) => entry.field && DATE_FIELDS.has(entry.field));
  const presets = catalog.data?.presets ?? [];

  return (
    <>
      <section className="space-y-3 rounded-2xl p-4" style={card} aria-label={entry.filename}>
        <div className="flex items-start gap-3">
          <span style={{ color: "var(--primary)" }}>
            <LineIcon name="file" />
          </span>
          <div className="min-w-0 flex-1">
            <b className="block truncate text-sm" style={{ color: "var(--text)" }}>{entry.filename}</b>
            <p className="text-xs leading-5" style={quiet} data-testid="import-recognized">
              {entry.source === "excel"
                ? t("recognizedExcel", { rows: entry.row_count })
                : t("recognized", { source: sourceName(t, entry.source), rows: entry.row_count })}
              {" · "}
              {fileRef.current ? (
                <>
                  <button type="button" className="font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => setSystemOpen((v) => !v)}>
                    {t("otherSystem")}
                  </button>
                  {" · "}
                </>
              ) : null}
              <button
                type="button"
                className="font-semibold underline disabled:opacity-50"
                style={{ color: "var(--primary)" }}
                disabled={discard.isPending}
                onClick={() => discard.mutate()}
              >
                {t("otherFile")}
              </button>
            </p>
          </div>
        </div>
        {systemOpen && fileRef.current ? (
          <div className="max-w-xs space-y-1">
            <span id="import-system-label" className="block text-xs font-semibold" style={quiet}>{t("systemLabel")}</span>
            <Select
              aria-labelledby="import-system-label"
              value={entry.source}
              disabled={reupload.isPending}
              onValueChange={(value) => value !== entry.source && reupload.mutate(value as ImportSource)}
            >
              {presets.map((preset) => (
                <option key={preset.key} value={preset.key}>{sourceName(t, preset.key)}</option>
              ))}
            </Select>
          </div>
        ) : null}
        {reupload.error ? <ErrorNotice variant="field">{errorText(reupload.error)}</ErrorNotice> : null}
        {discard.error ? <ErrorNotice variant="field">{errorText(discard.error)}</ErrorNotice> : null}
        <div className="grid grid-cols-[repeat(auto-fit,minmax(140px,1fr))] gap-2.5" data-testid="import-kpis">
          <Kpi value={kpis.created} label={t("kpiCreated")} />
          {kpis.matched > 0 ? <Kpi value={kpis.matched} label={t("kpiMatched")} /> : null}
          {kpis.packages > 0 ? <Kpi value={kpis.packages} label={t("kpiPackages")} /> : null}
        </div>
        <button type="button" className="text-xs font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => setRowsOpen(true)}>
          {t("seeRows")}
        </button>
      </section>

      {decisions.length > 0 ? (
        <h2 className="text-[15px] font-semibold" style={{ color: "var(--text)" }} data-testid="import-decisions-title">
          {left ? t("needDecision", { count: left }) : t("allReady")}
        </h2>
      ) : null}

      {decisions.map((decision) => (
        <DecisionCard
          key={decisionKey(decision)}
          decision={decision}
          answer={answers[decisionKey(decision)]}
          onAnswer={(value) => answer(decision, value)}
          onSeeRows={() => setRowsOpen(true)}
        />
      ))}

      <section className="space-y-2 rounded-2xl p-4" style={card}>
        <button
          type="button"
          aria-expanded={mapOpen}
          onClick={() => setMapOpen((v) => !v)}
          className="flex w-full items-center justify-between gap-3 text-start"
        >
          <b className="text-sm" style={{ color: "var(--text)" }}>{t("allMappings", { count: entry.header.length })}</b>
          <span aria-hidden="true" style={quiet}>{mapOpen ? "▴" : "▾"}</span>
        </button>
        {mapOpen ? (
          <div data-testid="import-mapping">
            {entry.header.map((header, column) => {
              const field = fieldOfColumn(mapping, column);
              const example = sampleCell(column);
              return (
                <div key={column} className="grid gap-2 border-b py-2 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-center" style={{ borderColor: "var(--border)" }}>
                  <span id={`import-col-${column}`} className="truncate rounded-lg px-2 py-1.5 font-mono text-xs" style={{ background: "var(--panel-muted)", color: "var(--text)" }} title={header}>
                    {header || t("unnamedColumn", { number: column + 1 })}
                  </span>
                  <Select
                    aria-labelledby={`import-col-${column}`}
                    value={field ?? ""}
                    disabled={rerun.isPending}
                    onValueChange={(value) => run(setColumnField(mapping, column, (value || null) as ImportField | null))}
                  >
                    <option value="">{t("ignore")}</option>
                    {FIELDS.map((key) => (
                      <option key={key} value={key}>{t(`fields.${key}`)}</option>
                    ))}
                  </Select>
                  <span className="truncate text-xs" style={quiet}>{example ? t("sample", { value: example }) : null}</span>
                </div>
              );
            })}
            {datesMapped ? (
              <div className="mt-3 max-w-xs space-y-1">
                <span id="import-date-order" className="block text-xs font-semibold" style={quiet}>{t("dateOrder")}</span>
                <Select aria-labelledby="import-date-order" value={dateOrder} disabled={rerun.isPending} onValueChange={(value) => run(mapping, value as ImportDateOrder)}>
                  {DATE_ORDERS.map((order) => (
                    <option key={order} value={order}>{t(`dateOrders.${order}`)}</option>
                  ))}
                </Select>
              </div>
            ) : null}
          </div>
        ) : null}
        {rerun.error ? <ErrorNotice variant="field">{errorText(rerun.error)}</ErrorNotice> : null}
      </section>

      <div
        className="sticky bottom-0 z-(--z-sticky) -mx-4 flex flex-wrap items-center gap-3 border-t px-4 py-3 text-sm sm:mx-0 sm:rounded-2xl sm:border"
        style={{ background: "var(--panel)", borderColor: "var(--border)", color: "var(--muted)" }}
      >
        <span>{rerun.isPending ? t("checking") : t("dryRunBar")}</span>
        <span className="flex-1" />
        <button
          type="button"
          data-testid="import-apply"
          className={primaryButton}
          style={SPARK_GO_STYLE}
          disabled={!ready || apply.isPending}
          onClick={() => apply.mutate()}
        >
          {t("importButton", { count })}
        </button>
        {apply.error ? <ErrorNotice variant="field" className="w-full">{errorText(apply.error)}</ErrorNotice> : null}
      </div>

      {rowsOpen ? <RowsDialog token={token} entry={entry} mapping={mapping} onClose={() => setRowsOpen(false)} /> : null}
    </>
  );
}

function Kpi({ value, label }: { value: number; label: string }) {
  return (
    <div className="grid min-w-0 gap-0.5 rounded-2xl px-3 py-2.5" style={card}>
      <b className="font-mono text-xl" style={{ color: "var(--text)" }}>{value}</b>
      <span className="text-xs" style={quiet}>{label}</span>
    </div>
  );
}

function DecisionCard({
  decision,
  answer,
  onAnswer,
  onSeeRows,
}: {
  decision: Decision;
  answer: string | undefined;
  onAnswer: (value: string) => void;
  onSeeRows: () => void;
}) {
  const t = useTranslations("CsvImport");
  const locale = useUiLocale();
  const list = (items: string[]) => new Intl.ListFormat(locale, { style: "long", type: "conjunction" }).format(items);
  let title: ReactNode;
  let hint: ReactNode;
  let choices: Array<[string, string]>;

  switch (decision.kind) {
    case "packages": {
      const one = decision.names.length === 1 && decision.count === 1;
      title = one
        ? t("packageOne", { name: decision.names[0]!, members: decision.members })
        : t("packageMany", { count: decision.count });
      hint = one ? t("packageHint") : decision.names.length ? `${t("packageHint")} ${list(decision.names.map((name) => `«${name}»`))}` : t("packageHint");
      choices = [
        ["create", one ? t("packageCreateOne", { name: decision.names[0]! }) : t("packageCreateMany")],
        ["skip", t("packageSkip")],
      ];
      break;
    }
    case "rows":
      title = t("rowsTitle", { count: decision.count });
      hint = (
        <>
          {decision.rows.length ? `${t("rowsHint", { rows: list(decision.rows.slice(0, 8).map(String)) })} ` : null}
          {t("rowsWhat")}{" "}
          <button type="button" className="font-semibold underline" style={{ color: "var(--primary)" }} onClick={onSeeRows}>
            {t("seeRows")}
          </button>
        </>
      );
      choices = [["ok", t("rowsOk")]];
      break;
    case "column":
      title = t("columnTitle", { header: decision.header });
      hint = decision.sample ? t("columnSample", { sample: decision.sample }) : null;
      choices = [...(decision.notesFree ? ([["notes", t("columnNotes")]] as Array<[string, string]>) : []), ["skip", t("columnSkip")]];
      break;
    case "columns":
      title = t("columnsTitle", { count: decision.columns.length });
      hint = list(decision.columns.slice(0, 6).map(({ header }) => `«${header}»`));
      choices = [
        ["skip", t("columnsSkip")],
        ["map", t("columnsMap")],
      ];
      break;
  }

  return (
    <section className="space-y-3 rounded-2xl p-4" style={answer ? card : highlighted} data-testid={`import-decision-${decision.kind}`}>
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <b className="block text-sm" style={{ color: "var(--text)" }}>{title}</b>
          {hint ? <div className="mt-0.5 text-xs leading-5" style={quiet}>{hint}</div> : null}
        </div>
        {answer ? <Done /> : null}
      </div>
      <div className="flex flex-wrap gap-2">
        {choices.map(([value, label]) => (
          <Chip key={value} on={answer === value} onClick={() => onAnswer(value)}>
            {label}
          </Chip>
        ))}
      </div>
    </section>
  );
}

// ── Applying: background job with progress ───────────────────────────────────

function ApplyingView({ entry }: { entry: PeopleImport }) {
  const t = useTranslations("CsvImport");
  const { done, percent } = applyProgress(entry);
  return (
    <section className="space-y-3 rounded-2xl p-4" style={card} data-testid="import-applying">
      <b className="block text-sm" style={{ color: "var(--text)" }}>{t("applyingTitle")}</b>
      <div
        role="progressbar"
        aria-label={t("applyingTitle")}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={percent}
        className="h-2 overflow-hidden rounded-full"
        style={{ background: "var(--panel-muted)" }}
      >
        <div className="h-full rounded-full transition-[width]" style={{ width: `${percent}%`, background: "var(--primary)" }} />
      </div>
      <p className="text-xs" style={quiet}>{t("applyingProgress", { done, total: entry.row_count })}</p>
      <p className="text-xs" style={quiet}>{t("applyingHint")}</p>
    </section>
  );
}

// ── Done: report, invitations, skipped rows, undo ────────────────────────────

function DoneView({ token, entry, onOpen }: { token: string; entry: PeopleImport; onOpen: (id: string | null) => void }) {
  const t = useTranslations("CsvImport");
  const errorText = useErrorText();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [later, setLater] = useState(false);
  const [sent, setSent] = useState<ImportInvitations | null>(null);
  const [rowsOpen, setRowsOpen] = useState(false);
  const [undoOpen, setUndoOpen] = useState(false);
  const [now] = useState(() => new Date());
  const report = reportOf(entry);
  const failed = entry.status === "failed";

  const invite = useMutation({ mutationFn: () => sendImportInvitations(token, entry.id), onSuccess: setSent });
  const retry = useMutation({
    mutationFn: () => applyImport(token, entry.id),
    onSuccess: (next) => queryClient.setQueryData([...KEY, entry.id], next),
  });
  const undo = useMutation({
    mutationFn: () => undoImport(token, entry.id),
    onSuccess: (next) => {
      setUndoOpen(false);
      queryClient.setQueryData([...KEY, entry.id], next);
      void queryClient.invalidateQueries({ queryKey: [...KEY, "list"] });
    },
  });
  const download = useMutation({
    mutationFn: async () => {
      const rows: ImportRow[] = [];
      for (const status of ["skipped", "failed"] as const) {
        let after: number | undefined;
        do {
          const page = await fetchImportRows(token, entry.id, { status, limit: SAMPLE_ROWS, after_row: after });
          rows.push(...page.rows);
          after = page.next_after_row ?? undefined;
        } while (after !== undefined);
      }
      rows.sort((a, b) => a.row_number - b.row_number);
      const csv = skippedRowsCsv(entry.header, rows, (row) => rowIssues(t, row));
      const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = entry.filename.replace(/\.[^.]+$/, "") + "-skipped.csv";
      link.click();
      URL.revokeObjectURL(url);
    },
  });

  const until = entry.undo_until ? new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(entry.undo_until)) : "";

  return (
    <>
      <section
        className="space-y-3 rounded-2xl p-4"
        style={{ ...card, borderColor: failed ? "var(--warning)" : "var(--success)" }}
        data-testid="import-report"
      >
        <div className="flex items-start gap-3">
          <span style={{ color: failed ? "var(--warning)" : "var(--success)" }}>
            <LineIcon name="check" />
          </span>
          <div className="min-w-0 flex-1">
            <b className="block text-sm" style={{ color: "var(--text)" }}>
              {failed
                ? t("failedTitle", { people: report.people })
                : report.packages > 0
                  ? t("doneTitleWithPackages", { people: report.people, packages: report.packages })
                  : t("doneTitle", { people: report.people })}
            </b>
            <p className="text-xs leading-5" style={quiet}>
              {failed ? t("failedHint") : report.skipped > 0 ? t("doneHint", { skipped: report.skipped }) : t("doneHintNoSkipped")}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {failed ? (
            <button type="button" className={primaryButton} style={primaryStyle} disabled={retry.isPending} onClick={() => retry.mutate()}>
              {t("continue")}
            </button>
          ) : null}
          {!later && (!sent || sent.remaining > 0) ? (
            <>
              <button type="button" className={primaryButton} style={primaryStyle} disabled={invite.isPending} onClick={() => invite.mutate()}>
                {t("inviteNow")}
              </button>
              {!sent ? (
                <button type="button" className={ghostButton} style={ghostStyle} onClick={() => setLater(true)}>
                  {t("inviteLater")}
                </button>
              ) : null}
            </>
          ) : null}
          {report.skipped > 0 ? (
            <button type="button" className={ghostButton} style={ghostStyle} disabled={download.isPending} onClick={() => download.mutate()}>
              <LineIcon name="download" size={15} /> {t("skippedRows")}
            </button>
          ) : null}
        </div>
        {sent ? (
          <p className="text-xs" role="status" style={{ color: "var(--success)" }}>
            {t("invitesSent", { sent: sent.sent })}
            {sent.failed > 0 ? ` · ${t("invitesFailed", { failed: sent.failed })}` : ""}
            {sent.remaining > 0 ? ` · ${t("invitesRemaining", { remaining: sent.remaining })}` : ""}
          </p>
        ) : later ? (
          <p className="text-xs" style={quiet}>
            {t("invitesLaterNote")}{" "}
            <button type="button" className="font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => setLater(false)}>
              {t("inviteLink")}
            </button>
          </p>
        ) : null}
        {invite.error ? <ErrorNotice variant="field">{errorText(invite.error)}</ErrorNotice> : null}
        {retry.error ? <ErrorNotice variant="field">{errorText(retry.error)}</ErrorNotice> : null}
        {download.error ? <ErrorNotice variant="field">{errorText(download.error)}</ErrorNotice> : null}
        <button type="button" className="text-xs font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => setRowsOpen(true)}>
          {t("seeRows")}
        </button>
      </section>

      <section className="space-y-2 rounded-2xl p-4" style={card}>
        <h2 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("nextTitle")}</h2>
        <p className="text-xs leading-5" style={quiet}>{t("nextHint")}</p>
        <button type="button" className={ghostButton} style={ghostStyle} onClick={() => onOpen(null)}>
          {t("newImport")}
        </button>
      </section>

      {canUndo(entry, now) ? (
        <p className="text-xs" style={quiet}>
          <button type="button" className="font-semibold underline" style={{ color: "var(--text-soft)" }} onClick={() => setUndoOpen(true)}>
            {t("undoLink")}
          </button>{" "}
          · {t("undoUntil", { date: until })}
        </p>
      ) : null}

      {undoOpen ? (
        <Dialog
          onClose={() => setUndoOpen(false)}
          title={t("undoTitle")}
          size="md"
          error={undo.error ? errorText(undo.error) : undefined}
          footer={
            <>
              <DialogButton tone="ghost" onClick={() => setUndoOpen(false)}>{t("cancel")}</DialogButton>
              <DialogButton tone="danger" disabled={undo.isPending} onClick={() => undo.mutate()} testId="import-undo-confirm">
                {t("undoConfirm")}
              </DialogButton>
            </>
          }
        >
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("undoBody")}</p>
        </Dialog>
      ) : null}

      {rowsOpen ? <RowsDialog token={token} entry={entry} mapping={entry.mapping} onClose={() => setRowsOpen(false)} /> : null}
    </>
  );
}

function UndoneView({ onOpen }: { onOpen: (id: string | null) => void }) {
  const t = useTranslations("CsvImport");
  return (
    <section className="space-y-3 rounded-2xl p-4" style={card} data-testid="import-undone">
      <b className="block text-sm" style={{ color: "var(--text)" }}>{t("undoneTitle")}</b>
      <p className="text-xs leading-5" style={quiet}>{t("undoneHint")}</p>
      <button type="button" className={ghostButton} style={ghostStyle} onClick={() => onOpen(null)}>
        {t("newImport")}
      </button>
    </section>
  );
}

// ── Rows, with filters ───────────────────────────────────────────────────────

type RowFilter = { key: string; filters: ImportRowFilters; count: number };

function rowFilters(entry: PeopleImport): RowFilter[] {
  const outcomes = entry.counts?.outcomes ?? entry.preview?.outcomes ?? {};
  const statuses = entry.counts?.statuses ?? {};
  const applied = phaseOf(entry) !== "review";
  const list: RowFilter[] = [
    { key: "all", filters: {}, count: entry.row_count },
    { key: "create_person", filters: { outcome: "create_person" }, count: outcomes.create_person ?? 0 },
    { key: "update_person", filters: { outcome: "update_person" }, count: outcomes.update_person ?? 0 },
    { key: "invalid", filters: { outcome: "invalid" }, count: outcomes.invalid ?? 0 },
    { key: "duplicate_row", filters: { outcome: "duplicate_row" }, count: outcomes.duplicate_row ?? 0 },
    { key: "already_imported", filters: { outcome: "already_imported" }, count: outcomes.already_imported ?? 0 },
  ];
  if (applied) {
    list.push({ key: "skipped", filters: { status: "skipped" }, count: statuses.skipped ?? 0 });
    list.push({ key: "failed", filters: { status: "failed" }, count: statuses.failed ?? 0 });
  }
  return list.filter((filter) => filter.key === "all" || filter.count > 0);
}

function RowsDialog({
  token,
  entry,
  mapping,
  onClose,
}: {
  token: string;
  entry: PeopleImport;
  mapping: ImportMappingEntry[];
  onClose: () => void;
}) {
  const t = useTranslations("CsvImport");
  const errorText = useErrorText();
  const filters = rowFilters(entry);
  const [active, setActive] = useState("all");
  const filter = filters.find((item) => item.key === active) ?? filters[0]!;
  const rows = useInfiniteQuery({
    queryKey: [...KEY, entry.id, "rows", active, entry.previewed_at ?? null, entry.status],
    queryFn: ({ pageParam }) => fetchImportRows(token, entry.id, { ...filter.filters, limit: 100, after_row: pageParam }),
    initialPageParam: undefined as number | undefined,
    getNextPageParam: (page) => page.next_after_row ?? undefined,
  });
  const list = rows.data?.pages.flatMap((page) => page.rows) ?? [];

  return (
    <Dialog onClose={onClose} title={t("rowsDialogTitle")} size="3xl" closeLabel={t("close")} testId="import-rows">
      <div className="space-y-3">
        <div className="flex flex-wrap gap-2" role="group" aria-label={t("rowsFilter")}>
          {filters.map((item) => (
            <Chip key={item.key} on={item.key === active} onClick={() => setActive(item.key)}>
              {t(`filters.${item.key}`)} · {item.count}
            </Chip>
          ))}
        </div>
        {rows.error ? <ErrorNotice>{errorText(rows.error)}</ErrorNotice> : null}
        {rows.isLoading ? <p className="text-sm" style={quiet}>{t("loading")}</p> : null}
        {!rows.isLoading && list.length === 0 ? <p className="text-sm" style={quiet}>{t("noRows")}</p> : null}
        {list.length > 0 ? (
          <div role="table" aria-label={t("rowsDialogTitle")} className="text-sm">
            <div role="row" className="hidden grid-cols-[3rem_minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1.4fr)] gap-2 border-b pb-1.5 text-xs font-semibold sm:grid" style={{ ...quiet, borderColor: "var(--border)" }}>
              <span role="columnheader">{t("rowsCol.row")}</span>
              <span role="columnheader">{t("rowsCol.person")}</span>
              <span role="columnheader">{t("rowsCol.result")}</span>
              <span role="columnheader">{t("rowsCol.issue")}</span>
            </div>
            {list.map((row) => (
              <div
                key={row.id}
                role="row"
                className="grid grid-cols-[3rem_minmax(0,1fr)] gap-x-2 gap-y-0.5 border-b py-2 sm:grid-cols-[3rem_minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1.4fr)]"
                style={{ borderColor: "var(--border)" }}
              >
                <span role="cell" className="font-mono text-xs" style={quiet}>{row.row_number}</span>
                <span role="cell" className="truncate" style={{ color: "var(--text)" }}>{rowPerson(mapping, row) || "—"}</span>
                <span role="cell" className="col-start-2 text-xs sm:col-start-auto sm:text-sm" style={quiet}>
                  {row.status !== "pending" ? t(`rowStatus.${row.status}`) : row.outcome ? t(`outcome.${row.outcome}`) : ""}
                </span>
                <span role="cell" className="col-start-2 text-xs sm:col-start-auto sm:text-sm" style={{ color: row.outcome === "invalid" || row.status === "failed" ? "var(--danger)" : "var(--text-soft)" }}>
                  {rowIssues(t, row)}
                </span>
              </div>
            ))}
          </div>
        ) : null}
        {rows.hasNextPage ? (
          <button type="button" className={ghostButton} style={ghostStyle} disabled={rows.isFetchingNextPage} onClick={() => void rows.fetchNextPage()}>
            {t("moreRows")}
          </button>
        ) : null}
      </div>
    </Dialog>
  );
}
