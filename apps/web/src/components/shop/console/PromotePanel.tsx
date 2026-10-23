"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { PromoteTarget, ShopProduct } from "@/api/shop-admin";
import { Segmented, Toggle } from "@/components/admin/finance/packages/package-ui";
import { formatMoney } from "@/components/inventory/inventory-helpers";
import { Field } from "@/components/inventory/inventory-ui";
import { useDemoGate, useMemberGroups, usePromoteProduct } from "@/components/shop/console/use-shop";
import { ProductThumb } from "@/components/shop/shared/ShopBits";
import { inputClass, inputStyle, StatusText } from "@/components/staff/staff-ui";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { endOfDayIso, priceRange } from "@/lib/shop/console";

/**
 * «Προώθηση» (proposal §2, no campaign system): a post with the product card
 * attached, in the club's announcements by default, a member group or the
 * Feed, plus an optional product-scoped code in Οικονομικά › Προσφορές. The
 * shop shows «Νέο» on its own for 14 days after publishing.
 */
export function PromotePanel({ product, onClose }: { product: ShopProduct; onClose: () => void }) {
  const t = useTranslations("ShopConsole.promote");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const gate = useDemoGate();
  const promote = usePromoteProduct(product.id);
  const [target, setTarget] = useState<PromoteTarget>("announcements");
  const groups = useMemberGroups(target === "channel");
  const [groupId, setGroupId] = useState("");
  const [body, setBody] = useState(t("defaultBody", { product: product.title }));
  const [withCode, setWithCode] = useState(false);
  const [code, setCode] = useState("");
  const [percent, setPercent] = useState("10");
  const [endsOn, setEndsOn] = useState("");
  const [error, setError] = useState<string | null>(null);
  const range = priceRange(product.variants);

  const submit = () => {
    setError(null);
    if (!body.trim()) return setError(t("errors.body"));
    if (target === "channel" && !groupId) return setError(t("errors.group"));
    const percentOff = Number.parseInt(percent, 10);
    if (withCode && (!code.trim() || !(percentOff > 0 && percentOff <= 100))) return setError(t("errors.code"));
    gate(() =>
      promote.mutate(
        {
          target,
          channel_id: target === "channel" ? groupId : null,
          body: body.trim(),
          promotion_code: withCode ? { code: code.trim().toUpperCase(), discount_percent: percentOff, ends_at: endsOn ? endOfDayIso(endsOn) : null } : null,
        },
        { onSuccess: onClose },
      ),
    );
  };

  return (
    <Dialog
      onClose={onClose}
      eyebrow={t("eyebrow")}
      title={product.title}
      size="lg"
      testId="shop-promote"
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton tone="primary" disabled={promote.isPending} onClick={submit}>
            {promote.isPending ? t("posting") : t("post")}
          </DialogButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("where")}</span>
          <Segmented
            label={t("where")}
            value={target}
            onChange={setTarget}
            options={(["announcements", "channel", "feed"] as const).map((value) => ({ value, label: t(`targets.${value}`) }))}
          />
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t(`targetHints.${target}`)}</span>
        </div>
        {target === "channel" ? (
          <Field label={t("group")}>
            <Select className={inputClass} style={inputStyle} value={groupId} onValueChange={setGroupId} placeholder={t("groupPick")}>
              {(groups.data ?? []).map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name}
                </option>
              ))}
            </Select>
          </Field>
        ) : null}
        <Field label={t("text")}>
          <textarea className={inputClass} style={inputStyle} rows={3} value={body} onChange={(event) => setBody(event.target.value)} maxLength={1000} />
        </Field>

        <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }} aria-label={t("preview")}>
          <span className="text-[11px] font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("preview")}</span>
          <p className="whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>{body}</p>
          <div className="flex items-center gap-3 rounded-xl p-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <ProductThumb src={product.media[0]?.thumb_url} alt={product.title} size={40} />
            <span className="flex min-w-0 flex-1 flex-col">
              <b className="truncate text-sm" style={{ color: "var(--text)" }}>{product.title}</b>
              <span className="text-xs" style={{ color: "var(--muted)" }}>{range ? formatMoney(range.min, locale) : ""}</span>
            </span>
            <span className="text-xs font-semibold" style={{ color: "var(--primary)" }}>{t("cardCta")}</span>
          </div>
        </div>

        <label className="flex items-center justify-between gap-3">
          <span className="flex flex-col">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("code")}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("codeHint")}</span>
          </span>
          <Toggle checked={withCode} onChange={setWithCode} label={t("code")} />
        </label>
        {withCode ? (
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label={t("codeValue")}>
              <input className={inputClass} style={inputStyle} value={code} onChange={(event) => setCode(event.target.value)} maxLength={24} />
            </Field>
            <Field label={t("percent")}>
              <input className={inputClass} style={inputStyle} inputMode="numeric" value={percent} onChange={(event) => setPercent(event.target.value.replace(/\D/g, ""))} />
            </Field>
            <Field label={t("endsOn")}>
              <DateInput className={inputClass} style={inputStyle} value={endsOn} onValueChange={setEndsOn} />
            </Field>
          </div>
        ) : null}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("newLabel")}</p>
        {error ? <StatusText tone="error">{error}</StatusText> : null}
        {promote.error ? <StatusText tone="error">{localizeError(promote.error, i18n)}</StatusText> : null}
      </div>
    </Dialog>
  );
}
