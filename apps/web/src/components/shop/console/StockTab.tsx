"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { ShopStockItem } from "@/api/shop";
import type { BranchFilterState } from "@/components/admin/BranchFilter";
import { Segmented } from "@/components/admin/finance/packages/package-ui";
import { formatDateTime } from "@/components/client/format";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { formatMoney, parseMoneyToCents } from "@/components/inventory/inventory-helpers";
import { Field } from "@/components/inventory/inventory-ui";
import { branchName } from "@/components/shop/console/ShopConsole";
import { useRecordMovement, useShopMovements, useShopStock } from "@/components/shop/console/use-shop";
import { ProductThumb, StockBadge } from "@/components/shop/shared/ShopBits";
import { inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { movementFor, type StockFormKind } from "@/lib/shop/console";

type View = "attention" | "all";
type Kind = StockFormKind;
const KINDS: Kind[] = ["receive", "recount", "damage", "loss", "return"];

function itemName(item: Pick<ShopStockItem, "product_title" | "variant_title">) {
  return [item.product_title, item.variant_title].filter(Boolean).join(" · ");
}

export function StockTab({ locationIds, branchFilter }: { locationIds?: string; branchFilter: BranchFilterState }) {
  const t = useTranslations("ShopConsole.stock");
  const i18n = useUiTranslations();
  const [view, setView] = useState<View>("attention");
  const [adjusting, setAdjusting] = useState<ShopStockItem | null>(null);
  const [history, setHistory] = useState<ShopStockItem | null>(null);
  const attention = useShopStock(true, locationIds);
  const all = useShopStock(false, locationIds);
  const items = view === "attention" ? attention : all;
  const branchOf = (id: string | null) => (branchFilter.visible ? branchName(branchFilter, id) : null);

  return (
    <section className="flex flex-col gap-4" aria-label={t("title")}>
      <SegmentPicker
        ariaLabel={t("filter")}
        semantics="radiogroup"
        value={view}
        onChange={setView}
        options={[
          { value: "attention", label: t("views.attention"), count: attention.data?.length ?? null },
          { value: "all", label: t("views.all"), count: all.data?.length ?? null },
        ]}
      />
      {items.isLoading ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : items.error ? (
        <StatusText tone="error">{localizeError(items.error, i18n)}</StatusText>
      ) : (items.data ?? []).length === 0 ? (
        <StatusText tone="muted">{t(`none.${view}`)}</StatusText>
      ) : (
        <ul className="flex flex-col gap-2" data-testid="shop-stock">
          {(items.data ?? []).map((item) => (
            <li
              key={`${item.variant_id}-${item.location_id ?? "all"}`}
              className="grid grid-cols-[auto_minmax(0,1fr)] items-center gap-3 rounded-2xl p-3 sm:grid-cols-[auto_minmax(0,1fr)_auto]"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <ProductThumb src={item.thumb_url} alt={item.product_title} size={40} />
              <span className="flex min-w-0 flex-col">
                <b className="truncate text-sm" style={{ color: "var(--text)" }}>{itemName(item)}</b>
                <span className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>
                  {[
                    t("units", { count: item.on_hand }),
                    item.days_of_stock_left !== null && item.days_of_stock_left !== undefined ? t("daysLeft", { count: item.days_of_stock_left }) : null,
                    item.reserved > 0 ? t("reserved", { count: item.reserved }) : null,
                    branchOf(item.location_id),
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </span>
              </span>
              <span className="col-span-2 flex flex-wrap items-center gap-2 sm:col-span-1 sm:justify-end">
                <StockBadge status={item.stock_status} />
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setHistory(item)}>
                  {t("history")}
                </button>
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setAdjusting(item)}>
                  {t("adjust")}
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("policyNote")}</p>

      <MovementList title={history ? t("historyOf", { item: itemName(history) }) : t("recent")} variantId={history?.variant_id ?? null} locationIds={locationIds} onClear={history ? () => setHistory(null) : undefined} />

      {adjusting ? <AdjustDialog item={adjusting} onClose={() => setAdjusting(null)} /> : null}
    </section>
  );
}

function MovementList({ title, variantId, locationIds, onClear }: { title: string; variantId: string | null; locationIds?: string; onClear?: () => void }) {
  const t = useTranslations("ShopConsole.stock");
  const locale = useUiLocale();
  const movements = useShopMovements(variantId, locationIds);
  return (
    <section className="flex flex-col gap-2 rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-label={title}>
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{title}</h2>
        {onClear ? (
          <button type="button" className="text-xs font-semibold" style={{ color: "var(--primary)" }} onClick={onClear}>
            {t("allMovements")}
          </button>
        ) : null}
      </div>
      {movements.isLoading ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : (movements.data ?? []).length === 0 ? (
        <StatusText tone="muted">{t("noMovements")}</StatusText>
      ) : (
        <ul className="flex flex-col" data-testid="shop-movements">
          {(movements.data ?? []).map((movement) => {
            const sign = movement.kind === "sale" || movement.kind === "reserve" ? -1 : 1;
            const delta = movement.kind === "adjustment" || movement.kind === "transfer" ? movement.quantity : sign * Math.abs(movement.quantity);
            const what = movement.kind === "adjustment" && movement.reason ? t(`reasons.${movement.reason}`) : t(`kinds.${movement.kind}`);
            return (
              <li key={movement.id} className="flex items-baseline justify-between gap-3 py-2 text-sm" style={{ borderTop: "1px solid var(--border)" }}>
                <span className="flex min-w-0 flex-col">
                  <span className="truncate" style={{ color: "var(--text)" }}>
                    {[what, movement.order_number ? `K-${movement.order_number}` : null, movement.actor_name].filter(Boolean).join(" · ")}
                  </span>
                  <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                    {[variantId ? null : [movement.product_title, movement.variant_title].filter(Boolean).join(" · "), movement.note, formatDateTime(movement.occurred_at, locale)].filter(Boolean).join(" · ")}
                  </span>
                </span>
                <b className="tabular-nums" style={{ color: delta < 0 ? "var(--danger)" : "var(--success)" }}>
                  {delta > 0 ? `+${delta}` : delta}
                </b>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function AdjustDialog({ item, onClose }: { item: ShopStockItem; onClose: () => void }) {
  const t = useTranslations("ShopConsole.stock");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const record = useRecordMovement();
  const [kind, setKind] = useState<Kind>("receive");
  const [amount, setAmount] = useState("");
  const [cost, setCost] = useState(item.unit_cost_cents ? (item.unit_cost_cents / 100).toFixed(2) : "");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const parsed = amount.trim() === "" ? Number.NaN : Number.parseInt(amount, 10);
  const movement = Number.isNaN(parsed) ? null : movementFor(item, kind, parsed, cost.trim() ? parseMoneyToCents(cost) : null, note);
  const after = movement ? item.on_hand + movement.quantity : null;

  const submit = () => {
    setError(null);
    if (!movement) return setError(t("errors.amount"));
    record.mutate(movement, { onSuccess: onClose });
  };

  return (
    <Dialog
      onClose={onClose}
      eyebrow={t("adjustEyebrow")}
      title={itemName(item)}
      size="md"
      testId="shop-adjust"
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton tone="primary" disabled={record.isPending} onClick={submit}>{t("record")}</DialogButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("reason")}</span>
          <Segmented label={t("reason")} value={kind} onChange={setKind} options={KINDS.map((value) => ({ value, label: t(`form.${value}`) }))} />
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label={kind === "recount" ? t("counted") : t("quantity")}>
            <input className={inputClass} style={inputStyle} inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value.replace(/\D/g, ""))} />
          </Field>
          {kind === "receive" ? (
            <Field label={t("unitCost")}>
              <input className={inputClass} style={inputStyle} inputMode="decimal" value={cost} onChange={(event) => setCost(event.target.value)} />
            </Field>
          ) : null}
        </div>
        <Field label={t("note")}>
          <input className={inputClass} style={inputStyle} value={note} onChange={(event) => setNote(event.target.value)} placeholder={t("noteHint")} maxLength={200} />
        </Field>
        <p className="text-sm tabular-nums" style={{ color: "var(--text-soft)" }} aria-live="polite">
          {after === null ? t("now", { count: item.on_hand }) : t("after", { from: item.on_hand, to: after })}
          {kind === "receive" && movement && cost.trim() && parseMoneyToCents(cost) !== null ? ` · ${formatMoney((parseMoneyToCents(cost) ?? 0) * movement.quantity, locale)}` : ""}
        </p>
        {error ? <StatusText tone="error">{error}</StatusText> : null}
        {record.error ? <StatusText tone="error">{localizeError(record.error, i18n)}</StatusText> : null}
      </div>
    </Dialog>
  );
}
