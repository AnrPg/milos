"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import type { ShopOption, ShopProduct, ShopProductInput, ShopProductStatus, ShopVisibility } from "@/api/shop-admin";
import { useBranchFilter } from "@/components/admin/BranchFilter";
import { Segmented, Toggle } from "@/components/admin/finance/packages/package-ui";
import { centsToInput, formatMoney, parseMoneyToCents } from "@/components/inventory/inventory-helpers";
import { Field } from "@/components/inventory/inventory-ui";
import { PromotePanel } from "@/components/shop/console/PromotePanel";
import { Shell } from "@/components/shop/console/ShopConsole";
import { useProductPhotos, MAX_PRODUCT_PHOTOS } from "@/components/shop/console/use-product-photos";
import { useDemoGate, useProductStatus, useSaveProduct, useShopAccess, useShopProduct } from "@/components/shop/console/use-shop";
import { ProductThumb } from "@/components/shop/shared/ShopBits";
import {
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
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { addOptionValue, draftsFromProduct, MAX_OPTIONS, reconcileVariants, type VariantDraft } from "@/lib/shop/console";
import { guideAnchor } from "@/lib/guides/anchors";

type Channel = "both" | "app" | "desk";

function channelOf(product: Pick<ShopProduct, "sell_in_app" | "sell_at_desk">): Channel {
  if (product.sell_in_app && !product.sell_at_desk) return "app";
  if (!product.sell_in_app && product.sell_at_desk) return "desk";
  return "both";
}

/** `/admin/shop/products/new` and `/admin/shop/products/:id`. */
export function ProductEditorPage({ productId }: { productId: string | null }) {
  const t = useTranslations("ShopConsole.editor");
  const i18n = useUiTranslations();
  const access = useShopAccess();
  const product = useShopProduct(productId);

  if (access.isLoading || (productId && product.isLoading)) {
    return (
      <Shell>
        <StatusText tone="muted">{t("loading")}</StatusText>
      </Shell>
    );
  }
  if (!access.manage) {
    return (
      <Shell>
        <StatusText tone="muted">{t("noAccess")}</StatusText>
      </Shell>
    );
  }
  if (productId && product.error) {
    return (
      <Shell>
        <StatusText tone="error">{localizeError(product.error, i18n)}</StatusText>
      </Shell>
    );
  }
  return (
    <Shell>
      <ProductEditor key={product.data?.id ?? "new"} product={product.data ?? null} />
    </Shell>
  );
}

function ProductEditor({ product }: { product: ShopProduct | null }) {
  const t = useTranslations("ShopConsole.editor");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const gate = useDemoGate();
  const branches = useBranchFilter("shop").locations;
  const save = useSaveProduct(product);
  const status = useProductStatus(product?.id ?? null);
  const photos = useProductPhotos(product?.media);
  const fileRef = useRef<HTMLInputElement>(null);
  const [promoting, setPromoting] = useState(false);

  const first = product?.variants.find((variant) => !variant.archived_at);
  const basePrice = product ? Math.min(...product.variants.map((variant) => variant.price_cents)) : null;
  const [title, setTitle] = useState(product?.title ?? "");
  const [description, setDescription] = useState(product?.description ?? "");
  const [category, setCategory] = useState(product?.category ?? "");
  const [price, setPrice] = useState(centsToInput(basePrice));
  const [compareAt, setCompareAt] = useState(centsToInput(first?.compare_at_price_cents));
  const [cost, setCost] = useState(centsToInput(first?.cost_price_cents));
  const [options, setOptions] = useState<ShopOption[]>(product?.options ?? []);
  const [variants, setVariants] = useState<VariantDraft[]>(() => (product ? draftsFromProduct(product) : [{ key: "", option_values: {}, price_cents: 0 }]));
  // Price overrides as typed; blank = the product price ("ίδια").
  const [overrides, setOverrides] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      (product ? draftsFromProduct(product) : []).filter((variant) => variant.price_cents !== basePrice).map((variant) => [variant.key, centsToInput(variant.price_cents)]),
    ),
  );
  // Opening stock of new variants, per variant and branch.
  const [opening, setOpening] = useState<Record<string, string>>({});
  const [channel, setChannel] = useState<Channel>(product ? channelOf(product) : "both");
  const [visibility, setVisibility] = useState<ShopVisibility>(product?.visibility ?? "members_only");
  const [memberDiscount, setMemberDiscount] = useState(product?.member_discount_applies ?? true);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const priceCents = parseMoneyToCents(price);
  useEffect(() => {
    queueMicrotask(() => setVariants((current) => reconcileVariants(options, current, priceCents ?? 0)));
  }, [options, priceCents]);

  const branchSlots: { id: string | null; name: string | null }[] = branches.length > 0 ? branches.map((branch) => ({ id: branch.id, name: branch.name })) : [{ id: null, name: null }];
  const existingById = new Map((product?.variants ?? []).map((variant) => [variant.id, variant]));

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);
    setSaved(false);
    if (!title.trim()) return setError(t("errors.title"));
    if (priceCents === null || priceCents <= 0) return setError(t("errors.price"));
    const compareCents = compareAt.trim() ? parseMoneyToCents(compareAt) : null;
    const costCents = cost.trim() ? parseMoneyToCents(cost) : null;
    if (compareAt.trim() && compareCents === null) return setError(t("errors.compareAt"));
    if (cost.trim() && costCents === null) return setError(t("errors.cost"));
    const rows = [];
    for (const variant of variants) {
      const override = overrides[variant.key]?.trim();
      const overrideCents = override ? parseMoneyToCents(override) : null;
      if (override && (overrideCents === null || overrideCents <= 0)) return setError(t("errors.variantPrice", { variant: variant.key }));
      rows.push({
        id: variant.id,
        option_values: variant.option_values,
        sku: variant.sku ?? null,
        price_cents: overrideCents ?? priceCents,
        compare_at_price_cents: compareCents,
        cost_price_cents: costCents,
        low_stock_threshold: variant.low_stock_threshold ?? null,
        track_inventory: variant.track_inventory ?? true,
        ...(variant.id
          ? {}
          : {
              initial_stock: branchSlots
                .map((slot) => ({ location_id: slot.id, quantity: Number.parseInt(opening[`${variant.key}|${slot.id ?? ""}`] ?? "", 10) || 0 }))
                .filter((entry) => entry.quantity > 0),
            }),
      });
    }
    const input: ShopProductInput = {
      title: title.trim(),
      description: description.trim() || null,
      category: category.trim() || null,
      media_ids: photos.mediaIds,
      options: options.filter((option) => option.name.trim() && option.values.length > 0).map((option) => ({ ...option, name: option.name.trim() })),
      // New products start as drafts; the status control below publishes.
      status: product?.status ?? "draft",
      visibility,
      sell_in_app: channel !== "desk",
      sell_at_desk: channel !== "app",
      member_discount_applies: memberDiscount,
      per_person_limit: product?.per_person_limit ?? null,
      all_locations: product?.all_locations ?? true,
      location_ids: product?.location_ids ?? [],
      variants: rows,
    };
    save.mutate(input, {
      onSuccess: (next) => {
        setSaved(true);
        if (!product) router.replace(adminHref(`/admin/shop/products/${next.id}`, organizationSlug));
      },
    });
  };

  const changeStatus = (next: ShopProductStatus) => {
    if (!product || next === product.status) return;
    const run = () => status.mutate(next);
    // ADR-184: a demo business keeps building the catalog; publishing waits for activation.
    if (next === "published") gate(run);
    else run();
  };

  const busy = save.isPending || photos.busy;
  const failure = save.error ?? status.error;

  return (
    <form className="flex flex-col gap-5" onSubmit={submit} aria-labelledby="shop-editor-title">
      <div className="flex flex-col gap-2">
        <Link href={adminHref("/admin/shop", organizationSlug)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
          ‹ {t("back")}
        </Link>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h1 id="shop-editor-title" className="min-w-0 text-2xl font-semibold tracking-tight md:text-3xl" style={{ color: "var(--text)" }}>
            {product ? product.title : t("newTitle")}
          </h1>
          {product ? (
            <div className="flex flex-wrap items-center gap-2">
              <Pill tone={product.status === "published" ? "success" : product.status === "draft" ? "neutral" : "warning"}>{t(`status.${product.status}`)}</Pill>
              {product.status === "published" ? (
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setPromoting(true)}>
                  {t("promote")}
                </button>
              ) : null}
            </div>
          ) : null}
        </div>
      </div>

      <StaffPanel guide="shop.editor.photos" labelledBy="shop-photos" title={t("photos.title")}>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("photos.hint")}</p>
        <ul className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
          {photos.photos.map((photo, index) => (
            <li key={photo.key} className="flex flex-col items-center gap-1">
              <ProductThumb src={photo.previewUrl} alt={t("photos.alt", { index: index + 1 })} size={88} />
              <span className="text-[11px] font-semibold" style={{ color: photo.state === "failed" ? "var(--danger)" : "var(--dim)" }}>
                {photo.state === "uploading" ? t("photos.uploading") : photo.state === "failed" ? t("photos.failed") : index === 0 ? t("photos.cover") : ""}
              </span>
              <span className="flex gap-1">
                {index > 0 && photo.state === "ready" ? (
                  <button type="button" className="text-[11px] font-semibold" style={{ color: "var(--primary)" }} onClick={() => photos.makeFirst(photo.key)}>
                    {t("photos.makeCover")}
                  </button>
                ) : null}
                <button type="button" className="text-[11px] font-semibold" style={{ color: "var(--danger)" }} onClick={() => photos.remove(photo.key)}>
                  {t("photos.remove")}
                </button>
              </span>
            </li>
          ))}
          {photos.photos.length < MAX_PRODUCT_PHOTOS ? (
            <li>
              <button
                type="button"
                onClick={() => fileRef.current?.click()}
                className="flex h-[88px] w-[88px] items-center justify-center rounded-xl text-xs font-semibold"
                style={{ border: "1px dashed var(--border-strong)", color: "var(--text-soft)", background: "var(--panel-muted)" }}
              >
                + {t("photos.add")}
              </button>
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                multiple
                className="hidden"
                aria-label={t("photos.add")}
                onChange={(event) => {
                  photos.add(Array.from(event.target.files ?? []));
                  event.target.value = "";
                }}
              />
            </li>
          ) : null}
        </ul>
      </StaffPanel>

      <StaffPanel guide="shop.editor.basics" labelledBy="shop-basics" title={t("basics.title")}>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label={t("basics.name")} className="sm:col-span-2">
            <input className={inputClass} style={inputStyle} value={title} onChange={(event) => setTitle(event.target.value)} required maxLength={120} />
          </Field>
          <Field label={t("basics.description")} className="sm:col-span-2">
            <textarea className={inputClass} style={inputStyle} rows={3} value={description} onChange={(event) => setDescription(event.target.value)} maxLength={2000} />
          </Field>
          <Field label={t("basics.category")}>
            <input className={inputClass} style={inputStyle} value={category} onChange={(event) => setCategory(event.target.value)} placeholder={t("basics.categoryHint")} maxLength={60} />
          </Field>
        </div>
      </StaffPanel>

      <StaffPanel guide="shop.editor.price" labelledBy="shop-price" title={t("price.title")}>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label={t("price.price")}>
            <input className={inputClass} style={inputStyle} inputMode="decimal" value={price} onChange={(event) => setPrice(event.target.value)} required />
          </Field>
          <Field label={t("price.compareAt")}>
            <input className={inputClass} style={inputStyle} inputMode="decimal" value={compareAt} onChange={(event) => setCompareAt(event.target.value)} />
          </Field>
          <Field label={t("price.cost")}>
            <input className={inputClass} style={inputStyle} inputMode="decimal" value={cost} onChange={(event) => setCost(event.target.value)} />
          </Field>
        </div>
        <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("price.hint")}</p>
      </StaffPanel>

      <StaffPanel guide="shop.editor.variants" labelledBy="shop-variants" title={t("variants.title")}>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("variants.hint")}</p>
        <div className="mt-3 flex flex-col gap-3">
          {options.map((option, index) => (
            <OptionEditor
              key={index}
              option={option}
              onChange={(next) => setOptions((current) => current.map((entry, at) => (at === index ? next : entry)))}
              onRemove={() => setOptions((current) => current.filter((_, at) => at !== index))}
            />
          ))}
          {options.length < MAX_OPTIONS ? (
            <div>
              <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setOptions((current) => [...current, { name: "", values: [] }])}>
                + {t(options.length === 0 ? "variants.addSize" : "variants.addColour")}
              </button>
            </div>
          ) : null}
        </div>

        <ul className="mt-4 flex flex-col gap-2" aria-label={t("variants.list")} data-testid="shop-variant-rows">
          {variants.map((variant) => {
            const existing = variant.id ? existingById.get(variant.id) : undefined;
            const label = variant.key || t("variants.single");
            return (
              <li key={variant.key} className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <b className="text-sm" style={{ color: "var(--text)" }}>{label}</b>
                  <Field label={t("variants.price")} className="w-36">
                    <input
                      className={inputClass}
                      style={inputStyle}
                      inputMode="decimal"
                      value={overrides[variant.key] ?? ""}
                      placeholder={priceCents ? t("variants.same", { price: formatMoney(priceCents, locale) }) : ""}
                      aria-label={t("variants.priceOf", { variant: label })}
                      onChange={(event) => setOverrides((current) => ({ ...current, [variant.key]: event.target.value }))}
                    />
                  </Field>
                </div>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  {branchSlots.map((slot) => {
                    const level = existing?.stock.find((entry) => entry.location_id === slot.id);
                    const slotLabel = slot.name ?? t("variants.stock");
                    return existing ? (
                      <span key={slot.id ?? "all"} className="flex flex-col text-xs" style={{ color: "var(--muted)" }}>
                        <span className="font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{slotLabel}</span>
                        <span className="tabular-nums" style={{ color: "var(--text)" }}>
                          {t("variants.onHand", { count: level?.on_hand ?? 0, reserved: level?.reserved ?? 0 })}
                        </span>
                      </span>
                    ) : (
                      <Field key={slot.id ?? "all"} label={slotLabel}>
                        <input
                          className={inputClass}
                          style={inputStyle}
                          inputMode="numeric"
                          value={opening[`${variant.key}|${slot.id ?? ""}`] ?? ""}
                          placeholder="0"
                          aria-label={t("variants.openingOf", { variant: label, branch: slotLabel })}
                          onChange={(event) => setOpening((current) => ({ ...current, [`${variant.key}|${slot.id ?? ""}`]: event.target.value.replace(/\D/g, "") }))}
                        />
                      </Field>
                    );
                  })}
                </div>
              </li>
            );
          })}
        </ul>
        {product ? <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("variants.ledgerNote")}</p> : null}
      </StaffPanel>

      <StaffPanel guide="shop.editor.selling" labelledBy="shop-selling" title={t("selling.title")}>
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("selling.channel")}</span>
            <Segmented
              label={t("selling.channel")}
              value={channel}
              onChange={setChannel}
              options={(["both", "app", "desk"] as const).map((value) => ({ value, label: t(`selling.channels.${value}`) }))}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("selling.visibility")}</span>
            <Segmented
              label={t("selling.visibility")}
              value={visibility}
              onChange={setVisibility}
              options={(["members_only", "anyone"] as const).map((value) => ({ value, label: t(`selling.visibilities.${value}`) }))}
            />
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("selling.visibilityHint")}</span>
          </div>
          <label className="flex items-center justify-between gap-3">
            <span className="flex flex-col">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("selling.memberDiscount")}</span>
              <span className="text-xs" style={{ color: "var(--dim)" }}>{t("selling.memberDiscountHint")}</span>
            </span>
            <Toggle checked={memberDiscount} onChange={setMemberDiscount} label={t("selling.memberDiscount")} />
          </label>
          <div className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("selling.status")}</span>
            {product ? (
              <Segmented
                label={t("selling.status")}
                value={product.status}
                onChange={changeStatus}
                options={(["draft", "published", "archived"] as const).map((value) => ({ value, label: t(`status.${value}`) }))}
              />
            ) : (
              <span className="text-sm" style={{ color: "var(--muted)" }}>{t("selling.newIsDraft")}</span>
            )}
          </div>
        </div>
      </StaffPanel>

      <div
        {...guideAnchor("shop.editor.save")}
        className="sticky bottom-[calc(var(--bottom-float-inset,0px)+0.5rem)] z-10 flex flex-wrap items-center justify-end gap-3 rounded-2xl p-3"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", boxShadow: "var(--shadow-md)" }}
      >
        {error ? <StatusText tone="error">{error}</StatusText> : null}
        {failure ? <StatusText tone="error">{localizeError(failure, i18n)}</StatusText> : null}
        {saved && !failure ? <StatusText tone="success">{t("saved")}</StatusText> : null}
        <button type="submit" className={primaryButtonClass} style={primaryButtonStyle} disabled={busy}>
          {save.isPending ? t("saving") : product ? t("save") : t("create")}
        </button>
      </div>

      {promoting && product ? <PromotePanel product={product} onClose={() => setPromoting(false)} /> : null}
    </form>
  );
}

function OptionEditor({ option, onChange, onRemove }: { option: ShopOption; onChange: (option: ShopOption) => void; onRemove: () => void }) {
  const t = useTranslations("ShopConsole.editor.variants");
  const [value, setValue] = useState("");
  const commit = () => {
    onChange(addOptionValue(option, value));
    setValue("");
  };
  return (
    <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
      <div className="flex items-end gap-2">
        <Field label={t("optionName")} className="flex-1">
          <input className={inputClass} style={inputStyle} value={option.name} onChange={(event) => onChange({ ...option, name: event.target.value })} placeholder={t("optionNameHint")} maxLength={30} />
        </Field>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={onRemove}>
          {t("removeOption")}
        </button>
      </div>
      <ul className="flex flex-wrap gap-1.5" aria-label={t("values")}>
        {option.values.map((entry) => (
          <li key={entry} className="inline-flex items-center gap-1 rounded-full px-3 py-1 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text)" }}>
            {entry}
            <button
              type="button"
              aria-label={t("removeValue", { value: entry })}
              style={{ color: "var(--dim)" }}
              onClick={() => onChange({ ...option, values: option.values.filter((item) => item !== entry) })}
            >
              ×
            </button>
          </li>
        ))}
      </ul>
      <div className="flex gap-2">
        <input
          className={inputClass}
          style={inputStyle}
          value={value}
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              commit();
            }
          }}
          aria-label={t("newValue")}
          placeholder={t("newValueHint")}
          maxLength={30}
        />
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={commit} disabled={!value.trim()}>
          {t("addValue")}
        </button>
      </div>
    </div>
  );
}
