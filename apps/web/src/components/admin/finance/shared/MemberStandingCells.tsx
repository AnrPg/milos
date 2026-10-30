"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";

import { resetFinanceOverride, setFinanceOverride } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Popover } from "@/components/ui/Popover";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

import { commitmentConflict } from "./membership-commitment";
import { OVERRIDABLE_STATUSES, statusTone, toneStyle, type ValueOverride } from "./member-standing";
import { OverrideNote } from "./OverrideNote";

type Field = "status" | "ends_on";

/** The calendar day of an ISO date, at midnight UTC (shown in UTC, so it never shifts). */
function utcDay(iso: string) {
  const [year, month, day] = iso.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

const CONTROL = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border-strong)" };

/** Every finance read that shows a member's status or dates. */
function useStandingMutations(userId: string, field: Field, subscriptionId?: string) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const refresh = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "users", userId] }),
    ]);
  };

  const save = useMutation({
    mutationFn: (body: { value: string; reason?: string; commitment_override_reason?: string }) =>
      setFinanceOverride(token, userId, field, { ...body, ...(subscriptionId ? { subscription_id: subscriptionId } : {}) }),
    onSuccess: refresh,
  });
  const reset = useMutation({
    mutationFn: () => resetFinanceOverride(token, userId, field, subscriptionId),
    onSuccess: refresh,
  });
  return { save, reset };
}

function useCanOverride() {
  const { membership } = useSelectedMembershipRole();
  return can(membership, "manage_billing");
}

export function useStatusLabel() {
  const t = useTranslations("MemberStanding");
  return (value: string | null) => (value ? t(`status_${value}` as "status_active") : t("statusNone"));
}

/**
 * ADR-274: the member's status, worked out from their subscription and what
 * they owe. Whoever manages billing may set it by hand; the cell then shows
 * the corner dot and its history.
 */
export function MemberStatusCell({
  userId,
  status,
  override,
}: {
  userId: string;
  status: string;
  override: ValueOverride | null;
}) {
  const t = useTranslations("MemberStanding");
  const i18n = useUiTranslations();
  const label = useStatusLabel();
  const canEdit = useCanOverride();
  const { save, reset } = useStandingMutations(userId, "status");
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const [commitmentReason, setCommitmentReason] = useState("");
  const conflict = commitmentConflict(save.error);
  const automatic = override ? override.computed_value : status;

  const close = () => {
    setOpen(false);
    setValue("");
    setReason("");
    setCommitmentReason("");
    save.reset();
  };
  const submit = () => {
    if (!value) return;
    save.mutate(
      { value, reason, ...(conflict ? { commitment_override_reason: commitmentReason } : {}) },
      { onSuccess: close },
    );
  };

  const pill = (
    <span className="rounded-full px-3 py-1 text-xs font-semibold" data-member-status={status} style={toneStyle(statusTone(status))}>
      {label(status)}
    </span>
  );

  return (
    <OverrideNote
      override={override}
      formatValue={label}
      onReset={canEdit ? () => reset.mutate() : undefined}
      resetting={reset.isPending}
    >
      {canEdit ? (
        <button ref={anchorRef} type="button" onClick={() => (open ? close() : setOpen(true))} aria-label={t("setStatus")}>
          {pill}
        </button>
      ) : (
        pill
      )}
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={close}
        width={280}
        role="dialog"
        ariaLabel={t("setStatus")}
        className="space-y-3 rounded-xl p-3 text-sm shadow-xl"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)", boxShadow: "var(--shadow-md)" }}
      >
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("automatic", { value: label(automatic) })}
        </p>
        <Select aria-label={t("setStatus")} value={value} onValueChange={setValue} className="w-full rounded-lg px-3 py-2 text-sm" style={CONTROL}>
          <option value="">{t("chooseStatus")}</option>
          {OVERRIDABLE_STATUSES.map((option) => (
            <option key={option} value={option}>
              {label(option)}
            </option>
          ))}
        </Select>
        <input
          aria-label={t("reasonOptional")}
          placeholder={t("reasonOptional")}
          value={reason}
          maxLength={500}
          onChange={(event) => setReason(event.target.value)}
          className="w-full rounded-lg px-3 py-2 text-sm outline-none"
          style={CONTROL}
        />
        {conflict ? (
          <div className="space-y-2">
            <p className="text-xs" style={{ color: "var(--warning)" }}>
              {conflict.endsOn ? i18n("admCommitmentActiveUntil", { date: conflict.endsOn }) : i18n("admCommitmentActive")}
            </p>
            <input
              aria-label={i18n("admCommitmentOverrideHint")}
              placeholder={i18n("admCommitmentOverrideHint")}
              value={commitmentReason}
              onChange={(event) => setCommitmentReason(event.target.value)}
              className="w-full rounded-lg px-3 py-2 text-sm outline-none"
              style={{ ...CONTROL, borderColor: "var(--danger)" }}
            />
          </div>
        ) : save.error ? (
          <ErrorNotice variant="field">{localizeError(save.error, i18n)}</ErrorNotice>
        ) : null}
        <div className="flex gap-2">
          <button
            type="button"
            onClick={submit}
            disabled={!value || save.isPending || Boolean(conflict && !commitmentReason.trim())}
            className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-40"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {save.isPending ? t("saving") : t("save")}
          </button>
          <button type="button" onClick={close} className="rounded-full px-4 py-2 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text)" }}>
            {t("cancel")}
          </button>
        </div>
      </Popover>
    </OverrideNote>
  );
}

/**
 * ADR-274: the subscription's last day, from the package: the end of the
 * current period («ανανεώνεται» while it renews) or its own end date.
 * Whoever manages billing may set a different last day.
 */
export function SubscriptionEndCell({
  userId,
  subscriptionId,
  endsOn,
  renews,
  override,
}: {
  userId: string;
  subscriptionId: string;
  endsOn: string;
  renews: boolean;
  override: ValueOverride | null;
}) {
  const t = useTranslations("MemberStanding");
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const canEdit = useCanOverride();
  const { save, reset } = useStandingMutations(userId, "ends_on", subscriptionId);
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState(endsOn);
  const [reason, setReason] = useState("");
  const formatDate = (iso: string | null) =>
    iso
      ? new Intl.DateTimeFormat(uiLocale, { dateStyle: "short", timeZone: "UTC" }).format(utcDay(iso))
      : t("noEnd");

  const close = () => {
    setOpen(false);
    setValue(endsOn);
    setReason("");
    save.reset();
  };

  const shown = (
    <span className="text-xs" data-subscription-ends={endsOn || "none"} style={{ color: endsOn ? "var(--text)" : "var(--dim)" }}>
      {formatDate(endsOn || null)}
      {endsOn && renews ? <span style={{ color: "var(--dim)" }}> · {t("renews")}</span> : null}
    </span>
  );

  return (
    <OverrideNote
      override={override}
      formatValue={formatDate}
      onReset={canEdit ? () => reset.mutate() : undefined}
      resetting={reset.isPending}
    >
      {canEdit ? (
        <button ref={anchorRef} type="button" onClick={() => (open ? close() : setOpen(true))} aria-label={t("setEnd")}>
          {shown}
        </button>
      ) : (
        shown
      )}
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={close}
        width={280}
        role="dialog"
        ariaLabel={t("setEnd")}
        className="space-y-3 rounded-xl p-3 text-sm shadow-xl"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)", boxShadow: "var(--shadow-md)" }}
      >
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("automatic", { value: formatDate(override ? override.computed_value : endsOn || null) })}
        </p>
        <DateInput aria-label={t("setEnd")} value={value} onValueChange={setValue} className="w-full rounded-lg px-3 py-2 text-sm" style={CONTROL} />
        <input
          aria-label={t("reasonOptional")}
          placeholder={t("reasonOptional")}
          value={reason}
          maxLength={500}
          onChange={(event) => setReason(event.target.value)}
          className="w-full rounded-lg px-3 py-2 text-sm outline-none"
          style={CONTROL}
        />
        {save.error ? <ErrorNotice variant="field">{localizeError(save.error, i18n)}</ErrorNotice> : null}
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => value && save.mutate({ value, reason }, { onSuccess: close })}
            disabled={!value || value === endsOn || save.isPending}
            className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-40"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {save.isPending ? t("saving") : t("save")}
          </button>
          <button type="button" onClick={close} className="rounded-full px-4 py-2 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text)" }}>
            {t("cancel")}
          </button>
        </div>
      </Popover>
    </OverrideNote>
  );
}
