"use client";

import { useTranslations } from "next-intl";
import { useRef, useState, type ReactNode } from "react";

import { Popover } from "@/components/ui/Popover";
import { clockFormat } from "@/lib/clock";
import { useUiLocale } from "@/i18n/use-ui-locale";

import type { ValueOverride } from "./member-standing";

/**
 * ADR-274: a value staff set by hand carries a small dot in its corner
 * (product owner, 2026-10-29: no separate edit icon). Hovering, focusing or
 * tapping it shows who changed it, when, from what to what and why, with
 * «Επαναφορά στο αυτόματο» for whoever may change it.
 */
export function OverrideNote({
  override,
  formatValue,
  onReset,
  resetting = false,
  children,
}: {
  override: ValueOverride | null;
  /** Turns a stored value (a status key, an ISO date) into its label. */
  formatValue: (value: string | null) => string;
  /** Omitted when the viewer may not change the value. */
  onReset?: () => void;
  resetting?: boolean;
  children: ReactNode;
}) {
  const t = useTranslations("MemberStanding");
  const uiLocale = useUiLocale();
  const anchorRef = useRef<HTMLSpanElement>(null);
  const [open, setOpen] = useState(false);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  if (!override) return <>{children}</>;

  const keepOpen = () => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    setOpen(true);
  };
  const closeSoon = () => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    closeTimer.current = setTimeout(() => setOpen(false), 150);
  };
  const when = clockFormat(uiLocale, { dateStyle: "short", timeStyle: "short" }).format(new Date(override.set_at));

  return (
    <span
      ref={anchorRef}
      className="relative inline-flex"
      data-override-field={override.field}
      onMouseEnter={keepOpen}
      onMouseLeave={closeSoon}
      onFocus={keepOpen}
      onBlur={closeSoon}
    >
      {children}
      <button
        type="button"
        aria-label={t("changedByHand")}
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
        className="absolute -end-1 -top-1 h-2.5 w-2.5 rounded-full"
        style={{ background: "var(--warning)", border: "2px solid var(--panel)" }}
      />
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={() => setOpen(false)}
        width={300}
        role="dialog"
        ariaLabel={t("changedByHand")}
        className="rounded-xl p-3 text-xs shadow-xl"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)", boxShadow: "var(--shadow-md)" }}
      >
        <div className="space-y-2" onMouseEnter={keepOpen} onMouseLeave={closeSoon}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("changedByHand")}</p>
          <Row label={t("by")} value={override.set_by_name || t("someone")} />
          <Row label={t("when")} value={when} />
          <Row
            label={t("change")}
            value={
              <>
                <span style={{ textDecoration: "line-through", color: "var(--dim)" }}>{formatValue(override.computed_value)}</span>
                {" → "}
                <strong>{formatValue(override.value)}</strong>
              </>
            }
          />
          {override.reason ? <Row label={t("reason")} value={override.reason} /> : null}
          {onReset ? (
            <div className="pt-2" style={{ borderTop: "1px solid var(--border)" }}>
              <button
                type="button"
                onClick={onReset}
                disabled={resetting}
                className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {resetting ? t("resetting") : t("reset")}
              </button>
            </div>
          ) : null}
        </div>
      </Popover>
    </span>
  );
}

function Row({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex justify-between gap-3">
      <span style={{ color: "var(--dim)" }}>{label}</span>
      <span className="text-end" style={{ color: "var(--text)" }}>{value}</span>
    </div>
  );
}
