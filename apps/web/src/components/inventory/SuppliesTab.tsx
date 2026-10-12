"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  archiveSupply,
  CONSUMPTION_SPEEDS,
  createSupply,
  fetchSupplyMovements,
  fetchSupplies,
  LOW_LEVELS,
  recordSupplyMovement,
  reportSupplyLow,
  updateSupply,
  type LowReport,
  type Supply,
  type SupplyInput,
  type SupplyMovementInput,
} from "@/api/inventory";
import { formatDateTime } from "@/components/client/format";
import {
  centsToInput,
  formatMoney,
  parseMoneyToCents,
  parseQuantity,
  sortByUrgency,
  stockStatus,
} from "@/components/inventory/inventory-helpers";
import { Details, Field, rowStyle, SectionHeading, StockPill, subtleText } from "@/components/inventory/inventory-ui";
import {
  dangerButtonStyle,
  inputClass,
  inputStyle,
  Pill,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

export const SUPPLIES_KEY = ["staff", "inventory", "supplies"] as const;
const movementsKey = (id: string) => ["staff", "inventory", "supplies", id, "movements"] as const;
const REPORT_KEY = ["staff", "inventory", "report"] as const;

type Action = "report" | "restock" | "consume" | "adjust" | "edit";

function useQuantityFormat() {
  const locale = useUiLocale();
  return (value: number) => new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(value);
}

export function SuppliesTab({ token, canManage }: { token: string; canManage: boolean }) {
  const i18n = useUiTranslations();
  const [adding, setAdding] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);
  const supplies = useQuery({ queryKey: SUPPLIES_KEY, queryFn: () => fetchSupplies(token) });
  const sorted = sortByUrgency((supplies.data ?? []).filter((supply) => !supply.archived_at));
  const attention = sorted.filter((supply) => stockStatus(supply) !== "ok").length;

  return (
    <div className="flex flex-col gap-4">
      {canManage ? (
        adding ? (
          <StaffPanel labelledBy="inv-new-supply" title={i18n("invNewSupply")}>
            <SupplyForm token={token} onDone={() => setAdding(false)} />
          </StaffPanel>
        ) : (
          <div>
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setAdding(true)}>
              + {i18n("invAddSupply")}
            </button>
          </div>
        )
      ) : null}

      <StaffPanel
        labelledBy="inv-supplies"
        title={i18n("invSuppliesTitle")}
        eyebrow={supplies.data ? i18n("invNeedAttention", { count: attention }) : undefined}
      >
        {supplies.isPending ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : supplies.isError ? (
          <StatusText tone="error">{localizeError(supplies.error, i18n)}</StatusText>
        ) : sorted.length === 0 ? (
          <StatusText tone="muted">{i18n("invNoSupplies")}</StatusText>
        ) : (
          <ul className="flex flex-col gap-2">
            {sorted.map((supply) => (
              <SupplyRow
                key={supply.id}
                token={token}
                supply={supply}
                canManage={canManage}
                open={openId === supply.id}
                onToggle={() => setOpenId((current) => (current === supply.id ? null : supply.id))}
              />
            ))}
          </ul>
        )}
      </StaffPanel>
    </div>
  );
}

function SupplyRow({
  token,
  supply,
  canManage,
  open,
  onToggle,
}: {
  token: string;
  supply: Supply;
  canManage: boolean;
  open: boolean;
  onToggle: () => void;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const quantity = useQuantityFormat();
  const queryClient = useQueryClient();
  const [action, setAction] = useState<Action | null>(null);
  const reports = supply.open_reports ?? [];
  const latest = reports.reduce<LowReport | undefined>((newest, report) => (!newest || report.reported_at > newest.reported_at ? report : newest), undefined);
  const daysLeft = supply.stock?.days_left;
  const archive = useMutation({
    mutationFn: () => archiveSupply(token, supply.id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: SUPPLIES_KEY }),
  });

  const actions: Action[] = ["report", ...(canManage ? (["restock", "consume", "adjust", "edit"] as const) : [])];

  return (
    <li className="rounded-2xl" style={rowStyle}>
      <button type="button" aria-expanded={open} onClick={onToggle} className="flex w-full flex-wrap items-center gap-2 px-4 py-3 text-start">
        <span className="min-w-0 flex-1">
          <span className="block truncate font-semibold" style={{ color: "var(--text)" }}>
            {supply.name}
          </span>
          <span className="block text-xs" style={subtleText}>
            {quantity(supply.quantity)}
            {supply.unit ? ` ${supply.unit}` : ""}
            {daysLeft != null ? ` · ${i18n("invDaysLeft", { count: Math.max(0, Math.floor(daysLeft)) })}` : ""}
          </span>
        </span>
        <span className="flex flex-wrap items-center gap-1.5">
          {latest ? <Pill tone="warning">{i18n(latest.level === "empty" ? "invReportedEmpty" : "invReportedLow")}</Pill> : null}
          <StockPill status={stockStatus(supply)} />
        </span>
        {latest ? (
          <span className="w-full text-xs" style={subtleText}>
            {i18n("invReportedBy", { name: latest.nickname ?? "—", when: formatDateTime(latest.reported_at, locale) })}
          </span>
        ) : null}
      </button>

      {open ? (
        <div className="flex flex-col gap-4 border-t px-4 pb-4 pt-3" style={{ borderColor: "var(--border)" }}>
          {supply.description ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>
              {supply.description}
            </p>
          ) : null}
          <Details
            items={[
              [i18n("invBrand"), supply.brand],
              [
                i18n("invShop"),
                supply.url ? (
                  <a href={supply.url} target="_blank" rel="noopener noreferrer" className="underline" style={{ color: "var(--primary)" }}>
                    {supply.shop || i18n("invOpenLink")}
                  </a>
                ) : (
                  supply.shop
                ),
              ],
              [i18n("invUnitPrice"), supply.unit_price_cents != null ? formatMoney(supply.unit_price_cents, locale) : null],
              [i18n("invSpeed"), i18n(`invSpeed_${supply.consumption_speed}`)],
              [i18n("invReorderLevel"), supply.reorder_level != null ? quantity(supply.reorder_level) : null],
              [
                i18n("invDailyUse"),
                supply.stock && supply.stock.daily_use > 0
                  ? `${quantity(supply.stock.daily_use)} · ${i18n(`invBasis_${supply.stock.basis}`)}`
                  : null,
              ],
            ]}
          />

          {reports.length > 0 ? (
            <div className="flex flex-col gap-2">
              <SectionHeading>{i18n("invOpenReports")}</SectionHeading>
              <ul className="flex flex-col gap-2">
                {reports.map((report) => (
                  <ReportItem key={report.id} report={report} unit={supply.unit} />
                ))}
              </ul>
            </div>
          ) : null}

          <div className="flex flex-wrap gap-2" role="group" aria-label={i18n("invActions")}>
            {actions.map((option) => (
              <button
                key={option}
                type="button"
                aria-pressed={action === option}
                className={secondaryButtonClass}
                style={action === option ? { ...secondaryButtonStyle, borderColor: "var(--primary)", color: "var(--primary)" } : secondaryButtonStyle}
                onClick={() => setAction((current) => (current === option ? null : option))}
              >
                {i18n(`invAction_${option}`)}
              </button>
            ))}
            {canManage ? (
              <button
                type="button"
                className={secondaryButtonClass}
                style={dangerButtonStyle}
                disabled={archive.isPending}
                onClick={() => {
                  if (window.confirm(i18n("invArchiveConfirm", { name: supply.name }))) archive.mutate();
                }}
              >
                {i18n("invArchive")}
              </button>
            ) : null}
          </div>
          {archive.isError ? <StatusText tone="error">{localizeError(archive.error, i18n)}</StatusText> : null}

          {action === "report" ? <LowReportForm token={token} supply={supply} onDone={() => setAction(null)} /> : null}
          {action === "restock" || action === "consume" || action === "adjust" ? (
            <MovementForm key={action} token={token} supply={supply} kind={action} onDone={() => setAction(null)} />
          ) : null}
          {action === "edit" ? <SupplyForm token={token} supply={supply} onDone={() => setAction(null)} /> : null}

          {canManage ? <MovementHistory token={token} supply={supply} /> : null}
        </div>
      ) : null}
    </li>
  );
}

function ReportItem({ report, unit }: { report: LowReport; unit?: string | null }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const quantity = useQuantityFormat();
  const facts = [
    i18n(`invLevel_${report.level}`),
    report.seen_quantity != null ? i18n("invSeen", { quantity: `${quantity(report.seen_quantity)}${unit ? ` ${unit}` : ""}` }) : null,
    report.place ? i18n("invAtPlace", { place: report.place }) : null,
  ].filter(Boolean);
  return (
    <li className="rounded-xl p-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p style={{ color: "var(--text-soft)" }}>{facts.join(" · ")}</p>
      {report.note ? (
        <p className="break-words" style={{ color: "var(--muted)" }}>
          {report.note}
        </p>
      ) : null}
      <p className="text-xs" style={subtleText}>
        {i18n("invReportedBy", { name: report.nickname ?? "—", when: formatDateTime(report.reported_at, locale) })}
      </p>
    </li>
  );
}

function FormShell({ onSubmit, children }: { onSubmit: () => void; children: React.ReactNode }) {
  return (
    <form
      className="grid gap-3 rounded-2xl p-3 sm:grid-cols-2"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit();
      }}
    >
      {children}
    </form>
  );
}

function FormButtons({ pending, disabled, onCancel, error }: { pending: boolean; disabled?: boolean; onCancel: () => void; error: unknown }) {
  const i18n = useUiTranslations();
  return (
    <div className="flex flex-col gap-2 sm:col-span-2">
      <div className="flex flex-wrap items-center gap-2">
        <button type="submit" className={primaryButtonClass} style={primaryButtonStyle} disabled={pending || disabled}>
          {i18n("invSave")}
        </button>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={onCancel}>
          {i18n("invCancel")}
        </button>
      </div>
      {error ? <StatusText tone="error">{localizeError(error, i18n)}</StatusText> : null}
    </div>
  );
}

function useRefreshSupply(supplyId: string) {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: SUPPLIES_KEY }),
      queryClient.invalidateQueries({ queryKey: movementsKey(supplyId) }),
      queryClient.invalidateQueries({ queryKey: REPORT_KEY }),
    ]);
}

function LowReportForm({ token, supply, onDone }: { token: string; supply: Supply; onDone: () => void }) {
  const i18n = useUiTranslations();
  const refresh = useRefreshSupply(supply.id);
  const [level, setLevel] = useState<(typeof LOW_LEVELS)[number]>("running_low");
  const [seen, setSeen] = useState("");
  const [place, setPlace] = useState("");
  const [note, setNote] = useState("");
  const report = useMutation({
    mutationFn: () =>
      reportSupplyLow(token, supply.id, {
        level,
        seen_quantity: parseQuantity(seen),
        place: place.trim() || null,
        note: note.trim() || null,
      }),
    onSuccess: async () => {
      await refresh();
      onDone();
    },
  });

  return (
    <FormShell onSubmit={() => report.mutate()}>
      <Field label={i18n("invLevel")}>
        <select className={inputClass} style={inputStyle} value={level} onChange={(event) => setLevel(event.target.value as typeof level)}>
          {LOW_LEVELS.map((option) => (
            <option key={option} value={option}>
              {i18n(`invLevel_${option}`)}
            </option>
          ))}
        </select>
      </Field>
      <Field label={i18n("invSeenQuantity", { unit: supply.unit ?? "" })}>
        <input className={inputClass} style={inputStyle} type="number" min={0} step="any" value={seen} onChange={(event) => setSeen(event.target.value)} />
      </Field>
      <Field label={i18n("invPlace")}>
        <input className={inputClass} style={inputStyle} maxLength={120} placeholder={i18n("invPlaceHint")} value={place} onChange={(event) => setPlace(event.target.value)} />
      </Field>
      <Field label={i18n("invNote")}>
        <input className={inputClass} style={inputStyle} maxLength={1000} value={note} onChange={(event) => setNote(event.target.value)} />
      </Field>
      <FormButtons pending={report.isPending} onCancel={onDone} error={report.error} />
    </FormShell>
  );
}

function MovementForm({
  token,
  supply,
  kind,
  onDone,
}: {
  token: string;
  supply: Supply;
  kind: SupplyMovementInput["kind"];
  onDone: () => void;
}) {
  const i18n = useUiTranslations();
  const refresh = useRefreshSupply(supply.id);
  const [amount, setAmount] = useState(kind === "adjust" ? String(supply.quantity) : "");
  const [priceMode, setPriceMode] = useState<"unit" | "total">("unit");
  const [price, setPrice] = useState(kind === "restock" ? centsToInput(supply.unit_price_cents) : "");
  const [note, setNote] = useState("");
  const parsed = parseQuantity(amount);
  const valid = parsed !== null && (kind === "adjust" ? Number.isInteger(parsed) : parsed > 0);

  const record = useMutation({
    mutationFn: () => {
      const body: SupplyMovementInput = { kind, quantity: parsed ?? 0, note: note.trim() || null };
      if (kind === "restock") {
        const cents = parseMoneyToCents(price);
        if (priceMode === "unit") body.unit_price_cents = cents;
        else body.total_cents = cents;
      }
      return recordSupplyMovement(token, supply.id, body);
    },
    onSuccess: async () => {
      await refresh();
      onDone();
    },
  });

  const unit = supply.unit ?? "";
  return (
    <FormShell onSubmit={() => valid && record.mutate()}>
      <Field label={i18n(kind === "adjust" ? "invCountedQuantity" : kind === "restock" ? "invAddedQuantity" : "invUsedQuantity", { unit })}>
        <input
          className={inputClass}
          style={inputStyle}
          type="number"
          min={0}
          step={kind === "adjust" ? 1 : "any"}
          required
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
        />
      </Field>
      {kind === "restock" ? (
        <Field label={i18n(priceMode === "unit" ? "invUnitPrice" : "invTotalPrice")}>
          <span className="flex gap-2">
            <input className={inputClass} style={inputStyle} inputMode="decimal" placeholder="0.00" value={price} onChange={(event) => setPrice(event.target.value)} />
            <select
              aria-label={i18n("invPriceMode")}
              className="rounded-xl px-2 py-2 text-sm"
              style={inputStyle}
              value={priceMode}
              onChange={(event) => setPriceMode(event.target.value as "unit" | "total")}
            >
              <option value="unit">{i18n("invPerUnit")}</option>
              <option value="total">{i18n("invTotal")}</option>
            </select>
          </span>
        </Field>
      ) : null}
      <Field label={i18n("invNote")} className={kind === "restock" ? "sm:col-span-2" : undefined}>
        <input className={inputClass} style={inputStyle} maxLength={1000} value={note} onChange={(event) => setNote(event.target.value)} />
      </Field>
      {kind === "restock" && (supply.open_reports ?? []).length > 0 ? (
        <p className="text-xs sm:col-span-2" style={subtleText}>
          {i18n("invRestockResolves")}
        </p>
      ) : null}
      <FormButtons pending={record.isPending} disabled={!valid} onCancel={onDone} error={record.error} />
    </FormShell>
  );
}

function MovementHistory({ token, supply }: { token: string; supply: Supply }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const quantity = useQuantityFormat();
  const [open, setOpen] = useState(false);
  const movements = useQuery({
    queryKey: movementsKey(supply.id),
    enabled: open,
    queryFn: () => fetchSupplyMovements(token, supply.id),
  });

  return (
    <div className="flex flex-col gap-2">
      <button type="button" aria-expanded={open} className="self-start text-xs font-semibold underline" style={subtleText} onClick={() => setOpen((value) => !value)}>
        {open ? i18n("invHideHistory") : i18n("invShowHistory")}
      </button>
      {open ? (
        movements.isPending ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : movements.isError ? (
          <StatusText tone="error">{localizeError(movements.error, i18n)}</StatusText>
        ) : movements.data.length === 0 ? (
          <StatusText tone="muted">{i18n("invNoMovements")}</StatusText>
        ) : (
          <ul className="flex flex-col divide-y text-sm" style={{ borderColor: "var(--border)" }}>
            {movements.data.map((movement) => {
              const sign = movement.kind === "restock" ? "+" : movement.kind === "consume" ? "−" : "=";
              const cost = movement.total_cents ?? (movement.unit_price_cents != null ? Math.round(movement.unit_price_cents * movement.quantity) : null);
              return (
                <li key={movement.id} className="flex flex-col gap-0.5 py-2">
                  <span className="flex flex-wrap items-center gap-2">
                    <span className="font-semibold" style={{ color: "var(--text)" }}>
                      {i18n(`invMovement_${movement.kind}`)} {sign}
                      {quantity(movement.quantity)}
                      {supply.unit ? ` ${supply.unit}` : ""}
                    </span>
                    {movement.kind === "restock" && cost != null ? (
                      <span style={{ color: "var(--text-soft)" }}>{formatMoney(cost, locale)}</span>
                    ) : null}
                  </span>
                  <span className="text-xs" style={subtleText}>
                    {formatDateTime(movement.occurred_at, locale)}
                    {movement.nickname ? ` · ${movement.nickname}` : ""}
                  </span>
                  {movement.note ? (
                    <span className="break-words text-xs" style={{ color: "var(--muted)" }}>
                      {movement.note}
                    </span>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )
      ) : null}
    </div>
  );
}

function SupplyForm({ token, supply, onDone }: { token: string; supply?: Supply; onDone: () => void }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    name: supply?.name ?? "",
    description: supply?.description ?? "",
    brand: supply?.brand ?? "",
    shop: supply?.shop ?? "",
    url: supply?.url ?? "",
    unit: supply?.unit ?? "",
    unit_price: centsToInput(supply?.unit_price_cents),
    quantity: "",
    consumption_speed: supply?.consumption_speed ?? ("regular" as Supply["consumption_speed"]),
    reorder_level: supply?.reorder_level != null ? String(supply.reorder_level) : "",
  });
  const set = (key: keyof typeof form) => (event: { target: { value: string } }) => setForm((current) => ({ ...current, [key]: event.target.value }));
  const text = (value: string) => value.trim() || null;

  const save = useMutation({
    mutationFn: () => {
      const body: SupplyInput = {
        name: form.name.trim(),
        description: text(form.description),
        brand: text(form.brand),
        shop: text(form.shop),
        url: text(form.url),
        unit: text(form.unit),
        unit_price_cents: parseMoneyToCents(form.unit_price),
        consumption_speed: form.consumption_speed,
        reorder_level: parseQuantity(form.reorder_level),
      };
      if (!supply) body.quantity = parseQuantity(form.quantity) ?? 0;
      return supply ? updateSupply(token, supply.id, body) : createSupply(token, body);
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: SUPPLIES_KEY });
      onDone();
    },
  });

  return (
    <form
      className="grid gap-3 sm:grid-cols-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (form.name.trim()) save.mutate();
      }}
    >
      <Field label={i18n("invName")}>
        <input className={inputClass} style={inputStyle} required maxLength={120} value={form.name} onChange={set("name")} />
      </Field>
      <Field label={i18n("invUnit")}>
        <input className={inputClass} style={inputStyle} maxLength={40} placeholder={i18n("invUnitHint")} value={form.unit} onChange={set("unit")} />
      </Field>
      {!supply ? (
        <Field label={i18n("invQuantityNow")}>
          <input className={inputClass} style={inputStyle} type="number" min={0} step="any" value={form.quantity} onChange={set("quantity")} />
        </Field>
      ) : null}
      <Field label={i18n("invReorderLevel")}>
        <input className={inputClass} style={inputStyle} type="number" min={0} step="any" value={form.reorder_level} onChange={set("reorder_level")} />
      </Field>
      <Field label={i18n("invSpeed")}>
        <select className={inputClass} style={inputStyle} value={form.consumption_speed} onChange={set("consumption_speed")}>
          {CONSUMPTION_SPEEDS.map((option) => (
            <option key={option} value={option}>
              {i18n(`invSpeed_${option}`)}
            </option>
          ))}
        </select>
      </Field>
      <Field label={i18n("invUnitPrice")}>
        <input className={inputClass} style={inputStyle} inputMode="decimal" placeholder="0.00" value={form.unit_price} onChange={set("unit_price")} />
      </Field>
      <Field label={i18n("invBrand")}>
        <input className={inputClass} style={inputStyle} maxLength={120} value={form.brand} onChange={set("brand")} />
      </Field>
      <Field label={i18n("invShop")}>
        <input className={inputClass} style={inputStyle} maxLength={120} value={form.shop} onChange={set("shop")} />
      </Field>
      <Field label={i18n("invUrl")} className="sm:col-span-2">
        <input className={inputClass} style={inputStyle} type="url" maxLength={500} placeholder="https://" value={form.url} onChange={set("url")} />
      </Field>
      <Field label={i18n("invDescription")} className="sm:col-span-2">
        <textarea className={inputClass} style={inputStyle} rows={2} maxLength={1000} value={form.description} onChange={set("description")} />
      </Field>
      <FormButtons pending={save.isPending} disabled={!form.name.trim()} onCancel={onDone} error={save.error} />
    </form>
  );
}
