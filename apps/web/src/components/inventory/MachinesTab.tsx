"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  archiveMachine,
  createMachine,
  fetchMachineEvents,
  fetchMachines,
  logMachineEvent,
  SEVERITIES,
  SYMPTOMS,
  updateMachine,
  type Machine,
  type MachineEvent,
  type MachineEventInput,
  type MachineEventKind,
  type MachineInput,
} from "@/api/inventory";
import { formatDateTime, formatDay } from "@/components/client/format";
import {
  centsToInput,
  eventKindHasCost,
  eventKindIsProblem,
  formatMoney,
  groupMachines,
  parseMoneyToCents,
  serviceState,
} from "@/components/inventory/inventory-helpers";
import { Details, Field, MachineStatusPill, rowStyle, SectionHeading, subtleText } from "@/components/inventory/inventory-ui";
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

export const MACHINES_KEY = ["staff", "inventory", "machines"] as const;
const eventsKey = (id: string) => ["staff", "inventory", "machines", id, "events"] as const;

type Props = { token: string; canManage: boolean; kinds: MachineEventKind[] };

export function MachinesTab({ token, canManage, kinds }: Props) {
  const i18n = useUiTranslations();
  const [adding, setAdding] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);
  const machines = useQuery({ queryKey: MACHINES_KEY, queryFn: () => fetchMachines(token) });
  const groups = groupMachines(machines.data ?? []);

  return (
    <div className="flex flex-col gap-4">
      {canManage ? (
        adding ? (
          <StaffPanel labelledBy="inv-new-machine" title={i18n("invNewMachine")}>
            <MachineForm token={token} onDone={() => setAdding(false)} />
          </StaffPanel>
        ) : (
          <div>
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setAdding(true)}>
              + {i18n("invAddMachine")}
            </button>
          </div>
        )
      ) : null}

      {machines.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : machines.isError ? (
        <StatusText tone="error">{localizeError(machines.error, i18n)}</StatusText>
      ) : groups.length === 0 ? (
        <StatusText tone="muted">{i18n("invNoMachines")}</StatusText>
      ) : (
        groups.map((group) => (
          <StaffPanel
            key={group.category}
            labelledBy={`inv-machines-${group.category}`}
            title={i18n(`invCategory_${group.category}`)}
            eyebrow={i18n("invMachineCount", { count: group.machines.length })}
          >
            <ul className="flex flex-col gap-2">
              {group.machines.map((machine) => (
                <MachineRow
                  key={machine.id}
                  token={token}
                  machine={machine}
                  canManage={canManage}
                  kinds={kinds}
                  open={openId === machine.id}
                  onToggle={() => setOpenId((current) => (current === machine.id ? null : machine.id))}
                />
              ))}
            </ul>
          </StaffPanel>
        ))
      )}
    </div>
  );
}

function MachineRow({
  token,
  machine,
  canManage,
  kinds,
  open,
  onToggle,
}: Props & { machine: Machine; open: boolean; onToggle: () => void }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const service = serviceState(machine);
  const subtitle = [machine.brand, machine.model].filter(Boolean).join(" · ");
  const archive = useMutation({
    mutationFn: () => archiveMachine(token, machine.id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: MACHINES_KEY }),
  });
  const day = (value?: string | null) => (value ? formatDay(value, locale) : null);

  return (
    <li className="rounded-2xl" style={rowStyle}>
      <button type="button" aria-expanded={open} onClick={onToggle} className="flex w-full flex-wrap items-center gap-2 px-4 py-3 text-start">
        <span className="min-w-0 flex-1">
          <span className="block truncate font-semibold" style={{ color: "var(--text)" }}>
            {machine.name}
            {machine.quantity > 1 ? <span style={subtleText}> ×{machine.quantity}</span> : null}
          </span>
          {subtitle ? (
            <span className="block truncate text-xs" style={subtleText}>
              {subtitle}
            </span>
          ) : null}
        </span>
        <span className="flex flex-wrap items-center gap-1.5">
          {service === "due" ? <Pill tone="warning">{i18n("invServiceDue")}</Pill> : null}
          {service === "soon" ? <Pill tone="neutral">{i18n("invServiceSoon")}</Pill> : null}
          <MachineStatusPill status={machine.status} />
        </span>
      </button>

      {open ? (
        <div className="flex flex-col gap-4 border-t px-4 pb-4 pt-3" style={{ borderColor: "var(--border)" }}>
          {editing ? (
            <MachineForm token={token} machine={machine} onDone={() => setEditing(false)} />
          ) : (
            <>
              <Details
                items={[
                  [i18n("invSerial"), machine.serial_number],
                  [i18n("invPurchasedOn"), day(machine.purchased_on)],
                  [i18n("invPurchasePrice"), machine.purchase_price_cents != null ? formatMoney(machine.purchase_price_cents, locale) : null],
                  [i18n("invWarrantyUntil"), day(machine.warranty_until)],
                  [i18n("invServiceContact"), machine.service_contact],
                  [i18n("invServiceInterval"), machine.service_interval_days ? i18n("invEveryDays", { count: machine.service_interval_days }) : null],
                  [i18n("invLastServiced"), day(machine.last_serviced_on)],
                  [i18n("invNextService"), day(machine.next_service_on)],
                  [i18n("invNotes"), machine.notes],
                ]}
              />
              {canManage ? (
                <div className="flex flex-wrap gap-2">
                  <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setEditing(true)}>
                    {i18n("invEdit")}
                  </button>
                  <button
                    type="button"
                    className={secondaryButtonClass}
                    style={dangerButtonStyle}
                    disabled={archive.isPending}
                    onClick={() => {
                      if (window.confirm(i18n("invArchiveConfirm", { name: machine.name }))) archive.mutate();
                    }}
                  >
                    {i18n("invArchive")}
                  </button>
                </div>
              ) : null}
              {archive.isError ? <StatusText tone="error">{localizeError(archive.error, i18n)}</StatusText> : null}
            </>
          )}
          {kinds.length > 0 ? <EventForm token={token} machine={machine} kinds={kinds} /> : null}
          <EventLog token={token} machineId={machine.id} />
        </div>
      ) : null}
    </li>
  );
}

function EventForm({ token, machine, kinds }: { token: string; machine: Machine; kinds: MachineEventKind[] }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<MachineEventKind>(kinds[0]);
  const [severity, setSeverity] = useState("");
  const [symptom, setSymptom] = useState("");
  const [usable, setUsable] = useState(true);
  const [cost, setCost] = useState("");
  const [body, setBody] = useState("");

  const reset = () => {
    setKind(kinds[0]);
    setSeverity("");
    setSymptom("");
    setUsable(true);
    setCost("");
    setBody("");
    setOpen(false);
  };

  const log = useMutation({
    mutationFn: () => {
      const input: MachineEventInput = { kind, body: body.trim() || null };
      if (eventKindIsProblem(kind)) {
        input.severity = (severity || null) as MachineEventInput["severity"];
        input.symptom = (symptom || null) as MachineEventInput["symptom"];
        input.usable = kind === "out_of_order" ? false : usable;
      }
      if (eventKindHasCost(kind)) input.cost_cents = parseMoneyToCents(cost);
      return logMachineEvent(token, machine.id, input);
    },
    onSuccess: async () => {
      reset();
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: MACHINES_KEY }),
        queryClient.invalidateQueries({ queryKey: eventsKey(machine.id) }),
      ]);
    },
  });

  if (!open) {
    return (
      <div>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setOpen(true)}>
          + {i18n("invAddNote")}
        </button>
      </div>
    );
  }

  const problem = eventKindIsProblem(kind);
  return (
    <form
      className="grid gap-3 rounded-2xl p-3 sm:grid-cols-2"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      onSubmit={(event) => {
        event.preventDefault();
        log.mutate();
      }}
    >
      <Field label={i18n("invKind")}>
        <select className={inputClass} style={inputStyle} value={kind} onChange={(event) => setKind(event.target.value as MachineEventKind)}>
          {kinds.map((option) => (
            <option key={option} value={option}>
              {i18n(`invKind_${option}`)}
            </option>
          ))}
        </select>
      </Field>
      {problem ? (
        <>
          <Field label={i18n("invSeverity")}>
            <select className={inputClass} style={inputStyle} value={severity} onChange={(event) => setSeverity(event.target.value)}>
              <option value="">—</option>
              {SEVERITIES.map((option) => (
                <option key={option} value={option}>
                  {i18n(`invSeverity_${option}`)}
                </option>
              ))}
            </select>
          </Field>
          <Field label={i18n("invSymptom")}>
            <select className={inputClass} style={inputStyle} value={symptom} onChange={(event) => setSymptom(event.target.value)}>
              <option value="">—</option>
              {SYMPTOMS.map((option) => (
                <option key={option} value={option}>
                  {i18n(`invSymptom_${option}`)}
                </option>
              ))}
            </select>
          </Field>
          {kind === "issue" ? (
            <label className="flex items-center gap-2 self-end pb-2 text-sm" style={{ color: "var(--text-soft)" }}>
              <input type="checkbox" checked={usable} onChange={(event) => setUsable(event.target.checked)} />
              {i18n("invStillUsable")}
            </label>
          ) : null}
        </>
      ) : null}
      {eventKindHasCost(kind) ? (
        <Field label={i18n("invCost")}>
          <input className={inputClass} style={inputStyle} inputMode="decimal" value={cost} onChange={(event) => setCost(event.target.value)} placeholder="0.00" />
        </Field>
      ) : null}
      <Field label={i18n("invWhatHappened")} className="sm:col-span-2">
        <textarea className={inputClass} style={inputStyle} rows={2} maxLength={2000} value={body} onChange={(event) => setBody(event.target.value)} />
      </Field>
      <div className="flex flex-wrap items-center gap-2 sm:col-span-2">
        <button type="submit" className={primaryButtonClass} style={primaryButtonStyle} disabled={log.isPending}>
          {i18n("invSave")}
        </button>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={reset}>
          {i18n("invCancel")}
        </button>
      </div>
      {log.isError ? <StatusText tone="error">{localizeError(log.error, i18n)}</StatusText> : null}
    </form>
  );
}

function EventLog({ token, machineId }: { token: string; machineId: string }) {
  const i18n = useUiTranslations();
  const events = useQuery({ queryKey: eventsKey(machineId), queryFn: () => fetchMachineEvents(token, machineId) });

  return (
    <div className="flex flex-col gap-2">
      <SectionHeading>{i18n("invLog")}</SectionHeading>
      {events.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : events.isError ? (
        <StatusText tone="error">{localizeError(events.error, i18n)}</StatusText>
      ) : events.data.length === 0 ? (
        <StatusText tone="muted">{i18n("invNoEvents")}</StatusText>
      ) : (
        <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          {events.data.map((event) => (
            <EventItem key={event.id} event={event} />
          ))}
        </ul>
      )}
    </div>
  );
}

const KIND_TONE: Partial<Record<MachineEventKind, "danger" | "warning" | "success" | "primary">> = {
  issue: "warning",
  out_of_order: "danger",
  repair_requested: "primary",
  maintenance: "success",
  repaired: "success",
};

function EventItem({ event }: { event: MachineEvent }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const facts = [
    event.severity ? i18n(`invSeverity_${event.severity}`) : null,
    event.symptom ? i18n(`invSymptom_${event.symptom}`) : null,
    event.usable === true ? i18n("invUsable") : event.usable === false ? i18n("invNotUsable") : null,
    event.cost_cents != null ? formatMoney(event.cost_cents, locale) : null,
  ].filter(Boolean);

  return (
    <li className="flex flex-col gap-1 py-2 text-sm">
      <span className="flex flex-wrap items-center gap-2">
        <Pill tone={KIND_TONE[event.kind] ?? "neutral"}>{i18n(`invKind_${event.kind}`)}</Pill>
        <span className="text-xs" style={subtleText}>
          {formatDateTime(event.occurred_at, locale)}
          {event.nickname ? ` · ${event.nickname}` : ""}
        </span>
      </span>
      {facts.length > 0 ? (
        <span className="text-xs" style={{ color: "var(--text-soft)" }}>
          {facts.join(" · ")}
        </span>
      ) : null}
      {event.body ? (
        <span className="whitespace-pre-line break-words" style={{ color: "var(--muted)" }}>
          {event.body}
        </span>
      ) : null}
    </li>
  );
}

function MachineForm({ token, machine, onDone }: { token: string; machine?: Machine; onDone: () => void }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    name: machine?.name ?? "",
    category: machine?.category ?? ("training" as Machine["category"]),
    brand: machine?.brand ?? "",
    model: machine?.model ?? "",
    serial_number: machine?.serial_number ?? "",
    quantity: String(machine?.quantity ?? 1),
    purchased_on: machine?.purchased_on ?? "",
    purchase_price: centsToInput(machine?.purchase_price_cents),
    warranty_until: machine?.warranty_until ?? "",
    service_contact: machine?.service_contact ?? "",
    service_interval_days: machine?.service_interval_days ? String(machine.service_interval_days) : "",
    last_serviced_on: machine?.last_serviced_on ?? "",
    notes: machine?.notes ?? "",
  });
  const set = (key: keyof typeof form) => (event: { target: { value: string } }) => setForm((current) => ({ ...current, [key]: event.target.value }));
  const text = (value: string) => value.trim() || null;

  const save = useMutation({
    mutationFn: () => {
      const body: MachineInput = {
        name: form.name.trim(),
        category: form.category,
        brand: text(form.brand),
        model: text(form.model),
        serial_number: text(form.serial_number),
        quantity: Math.max(1, Math.round(Number(form.quantity) || 1)),
        purchased_on: text(form.purchased_on),
        purchase_price_cents: parseMoneyToCents(form.purchase_price),
        warranty_until: text(form.warranty_until),
        service_contact: text(form.service_contact),
        service_interval_days: form.service_interval_days ? Math.round(Number(form.service_interval_days)) || null : null,
        last_serviced_on: text(form.last_serviced_on),
        notes: text(form.notes),
      };
      return machine ? updateMachine(token, machine.id, body) : createMachine(token, body);
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: MACHINES_KEY });
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
      <Field label={i18n("invCategory")}>
        <select className={inputClass} style={inputStyle} value={form.category} onChange={set("category")}>
          <option value="training">{i18n("invCategory_training")}</option>
          <option value="appliance">{i18n("invCategory_appliance")}</option>
        </select>
      </Field>
      <Field label={i18n("invBrand")}>
        <input className={inputClass} style={inputStyle} maxLength={120} value={form.brand} onChange={set("brand")} />
      </Field>
      <Field label={i18n("invModel")}>
        <input className={inputClass} style={inputStyle} maxLength={120} value={form.model} onChange={set("model")} />
      </Field>
      <Field label={i18n("invQuantity")}>
        <input className={inputClass} style={inputStyle} type="number" min={1} step={1} value={form.quantity} onChange={set("quantity")} />
      </Field>
      <Field label={i18n("invSerial")}>
        <input className={inputClass} style={inputStyle} maxLength={120} value={form.serial_number} onChange={set("serial_number")} />
      </Field>
      <Field label={i18n("invPurchasedOn")}>
        <input className={inputClass} style={inputStyle} type="date" value={form.purchased_on} onChange={set("purchased_on")} />
      </Field>
      <Field label={i18n("invPurchasePrice")}>
        <input className={inputClass} style={inputStyle} inputMode="decimal" placeholder="0.00" value={form.purchase_price} onChange={set("purchase_price")} />
      </Field>
      <Field label={i18n("invWarrantyUntil")}>
        <input className={inputClass} style={inputStyle} type="date" value={form.warranty_until} onChange={set("warranty_until")} />
      </Field>
      <Field label={i18n("invServiceContact")}>
        <input className={inputClass} style={inputStyle} maxLength={200} value={form.service_contact} onChange={set("service_contact")} />
      </Field>
      <Field label={i18n("invServiceIntervalDays")}>
        <input className={inputClass} style={inputStyle} type="number" min={1} step={1} value={form.service_interval_days} onChange={set("service_interval_days")} />
      </Field>
      <Field label={i18n("invLastServiced")}>
        <input className={inputClass} style={inputStyle} type="date" value={form.last_serviced_on} onChange={set("last_serviced_on")} />
      </Field>
      <Field label={i18n("invNotes")} className="sm:col-span-2">
        <textarea className={inputClass} style={inputStyle} rows={2} maxLength={2000} value={form.notes} onChange={set("notes")} />
      </Field>
      <div className="flex flex-wrap items-center gap-2 sm:col-span-2">
        <button type="submit" className={primaryButtonClass} style={primaryButtonStyle} disabled={!form.name.trim() || save.isPending}>
          {i18n("invSave")}
        </button>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={onDone}>
          {i18n("invCancel")}
        </button>
      </div>
      {save.isError ? <StatusText tone="error">{localizeError(save.error, i18n)}</StatusText> : null}
    </form>
  );
}
