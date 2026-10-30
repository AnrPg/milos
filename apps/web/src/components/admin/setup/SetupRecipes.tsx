"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useState, type CSSProperties } from "react";

import { ApiError } from "@/api/client";
import {
  applySetupRecipe,
  fetchSetupRecipes,
  previewSetupRecipe,
  type AppliedRecipe,
  type RecipeChange,
  type RecipeMode,
  type SetupRecipe,
} from "@/api/setup";
import { fetchPaymentAccount, isConnected } from "@/api/online-payments";
import { LineIcon } from "@/components/admin/imports/ImportIcons";
import { PAYMENT_ACCOUNT_KEY } from "@/components/admin/payments/OnlinePaymentsSettings";
import { useSession } from "@/components/session-provider";
import { BackButton } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";
import { SPARK_GO_STYLE } from "@/lib/spark";

import {
  RECIPE_ICONS,
  appliedCounts,
  changedPrices,
  formatPrice,
  labelKey,
  ownerChanges,
  previewOf,
  type PreviewRule,
} from "./recipe-model";

// First setup (ADR-255), mockup s10 option A: «Τι είδους box έχεις;» as
// cards, a preview of what will be set up whose prices can change, then
// «Εφαρμογή» (owner only). Everything changes later in Ρυθμίσεις.

export const RECIPES_KEY = ["admin", "setup", "recipes"] as const;

const card: CSSProperties = { background: "var(--panel)", border: "1px solid var(--border)" };
const quiet: CSSProperties = { color: "var(--muted)" };
const button = ["inline-flex", "min-h-10 items-center justify-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-50"].join(" ");

type Step = "pick" | "preview" | "done";

export function SetupRecipes() {
  const t = useTranslations("SetupRecipes");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);
  const [step, setStep] = useState<Step>("pick");
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [invalid, setInvalid] = useState<string[]>([]);
  // Product decision 2026-10-29: applying asks what happens to the settings the owner changed.
  const [mode, setMode] = useState<RecipeMode | null>(null);
  const [modeMissing, setModeMissing] = useState(false);
  const [applied, setApplied] = useState<AppliedRecipe | null>(null);

  const recipes = useQuery({
    queryKey: RECIPES_KEY,
    queryFn: () => fetchSetupRecipes(token!),
    enabled: Boolean(token),
    staleTime: FRESHNESS.reference,
  });
  // ADR-271: «Τι πωλείται online» in the next steps shows how many packages are sold online.
  const payments = useQuery({
    queryKey: PAYMENT_ACCOUNT_KEY,
    queryFn: () => fetchPaymentAccount(token!),
    enabled: Boolean(token && step === "done"),
    staleTime: FRESHNESS.reference,
    retry: false,
  });
  const recipe = recipes.data?.recipes.find((entry) => entry.key === selected);
  const plan = useQuery({
    queryKey: [...RECIPES_KEY, "preview", selected],
    queryFn: () => previewSetupRecipe(token!, selected!),
    enabled: Boolean(token && selected && step === "preview"),
    staleTime: 0,
  });
  const preview = plan.data ? previewOf(plan.data, recipe) : null;
  const owned = plan.data ? ownerChanges(plan.data) : [];

  const apply = useMutation({
    mutationFn: ({ prices, mode }: { prices: Record<string, number>; mode: RecipeMode }) =>
      applySetupRecipe(token!, selected!, prices, mode),
    onSuccess: (result) => {
      setApplied(result);
      setStep("done");
      void queryClient.invalidateQueries({ queryKey: RECIPES_KEY });
      void queryClient.invalidateQueries({ queryKey: ["admin", "settings"] });
    },
  });

  const currency = recipes.data?.currency ?? "EUR";
  const symbol =
    new Intl.NumberFormat(locale, { style: "currency", currency }).formatToParts(0).find((part) => part.type === "currency")?.value ?? currency;
  const nameOf = (entry: SetupRecipe) => (locale.startsWith("el") ? entry.names.el : entry.names.en);
  const summaryOf = (entry: SetupRecipe) => (locale.startsWith("el") ? entry.summaries.el : entry.summaries.en);
  const canApply = recipes.data?.can_apply ?? false;

  const errorText = (error: unknown) => {
    const code = error instanceof ApiError ? error.payload.code : undefined;
    if (code === "recipe_owner_only" || code === "recipe_step_failed" || code === "invalid_recipe_prices") return t(`errors.${code}`);
    return localizeError(error, i18n);
  };

  const ruleText = (rule: PreviewRule) => {
    const value = rule.value;
    switch (rule.key) {
      case "provider.kind":
        return value === "coach" ? t("rules.providerCoach") : t("rules.providerGym");
      case "scheduling.default_auto_approve":
        return value ? t("rules.autoApproveOn") : t("rules.autoApproveOff");
      case "scheduling.default_booking_window_days":
        return typeof value === "number" ? t("rules.bookingWindow", { days: value }) : t("rules.bookingWindowNone");
      case "scheduling.default_cancellation_cutoff_minutes":
        if (typeof value !== "number") return t("rules.cutoffNone");
        return value % 60 === 0 ? t("rules.cutoffHours", { hours: value / 60 }) : t("rules.cutoffMinutes", { minutes: value });
      case "scheduling.default_capacity":
        return t("rules.capacity", { count: Number(value) });
      case "gamification.leaderboard_enabled":
        return value ? t("rules.leaderboardOn") : t("rules.leaderboardOff");
      case "trials.enabled":
        return value ? t("rules.trialsOn") : t("rules.trialsOff");
      case "trials.seats_per_class":
        return t("rules.trialSeats", { count: Number(value) });
      default:
        return rule.key;
    }
  };

  // A setting's value in words for the «already changed» list.
  const valueText = (change: RecipeChange, value: unknown): string => {
    if (value === null || value === undefined) return t("ownerValues.none");
    if (typeof value === "boolean") return value ? t("ownerValues.on") : t("ownerValues.off");
    if (change.key === "provider.kind") return t(`ownerValues.kind_${String(value)}`);
    if (change.key === "community.member_groups") return t(`ownerValues.groups_${String(value)}`);
    if (change.key === "trials.approval") return t(`ownerValues.approval_${String(value)}`);
    if (Array.isArray(value)) return value.map((module) => i18n(`pkgModule_${String(module)}`)).join(", ");
    if (typeof value === "number") {
      if (change.key.endsWith("_minutes")) return t("ownerValues.minutes", { count: value });
      if (change.key.endsWith("_days")) return t("ownerValues.days", { count: value });
    }
    return String(value);
  };

  const onApply = () => {
    if (!preview) return;
    const result = changedPrices(preview.packages, drafts);
    if ("invalid" in result && result.invalid) {
      setInvalid(result.invalid);
      return;
    }
    setInvalid([]);
    if (owned.length > 0 && !mode) {
      setModeMissing(true);
      return;
    }
    apply.mutate({ prices: result.prices ?? {}, mode: owned.length > 0 && mode ? mode : "all" });
  };

  let body;
  if (!token || recipes.isLoading) {
    body = <p className="text-sm" style={quiet}>{t("loading")}</p>;
  } else if (recipes.error) {
    body = <ErrorNotice>{errorText(recipes.error)}</ErrorNotice>;
  } else if (step === "pick") {
    body = (
      <>
        <p className="text-xs font-semibold" style={{ color: "var(--text)" }}>{t("welcome")}</p>
        <h1 className="text-2xl font-semibold tracking-tight md:text-3xl" style={{ color: "var(--text)" }}>{t("title")}</h1>
        <p className="text-sm" style={quiet}>{t("intro")}</p>
        <div className="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-2.5" role="group" aria-label={t("title")}>
          {recipes.data!.recipes.map((entry) => {
            const on = entry.key === selected;
            return (
              <button
                key={entry.key}
                type="button"
                aria-pressed={on}
                data-testid={`recipe-${entry.key}`}
                onClick={() => setSelected(entry.key)}
                className="grid min-w-0 content-start gap-1.5 rounded-2xl p-3 text-start"
                style={
                  on
                    ? { background: "color-mix(in srgb, var(--primary) 6%, var(--panel))", border: "1px solid var(--primary)", boxShadow: "inset 0 0 0 1px var(--primary)" }
                    : card
                }
              >
                <span style={{ color: "var(--primary)" }}>
                  <LineIcon name={RECIPE_ICONS[entry.key] ?? "sparkle"} />
                </span>
                <b className="text-sm leading-tight" style={{ color: "var(--text)" }}>{nameOf(entry)}</b>
                <span className="text-xs" style={quiet}>{summaryOf(entry)}</span>
              </button>
            );
          })}
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <Link href={adminHref("/admin/settings", slug)} className="text-sm font-semibold underline" style={{ color: "var(--primary)" }}>
            {t("fromScratch")}
          </Link>
          <span className="flex-1" />
          <button
            type="button"
            className={button}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={!selected}
            onClick={() => {
              setDrafts({});
              setInvalid([]);
              setMode(null);
              setModeMissing(false);
              setStep("preview");
            }}
          >
            {t("continue")}
          </button>
        </div>
      </>
    );
  } else if (step === "preview" && recipe) {
    body = (
      <>
        <BackButton className="self-start text-sm font-semibold" onClick={() => setStep("pick")}>
          {t("backToKinds")}
        </BackButton>
        <h1 className="text-2xl font-semibold tracking-tight md:text-3xl" style={{ color: "var(--text)" }}>
          {t("previewTitle", { name: nameOf(recipe) })}
        </h1>
        <p className="text-sm" style={quiet}>{t("previewIntro")}</p>
        {plan.error ? <ErrorNotice>{errorText(plan.error)}</ErrorNotice> : null}
        {!preview ? (
          <p className="text-sm" style={quiet}>{t("loading")}</p>
        ) : (
          <>
            <div className="grid gap-3 md:grid-cols-2">
              <section className="space-y-2 rounded-2xl p-4" style={card} aria-labelledby="recipe-packages">
                <h2 id="recipe-packages" className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("packages")}</h2>
                {preview.packages.length === 0 ? <p className="text-xs" style={quiet}>{t("packagesInPlace")}</p> : null}
                {preview.packages.map((pkg) => {
                  const wrong = invalid.includes(pkg.code);
                  return (
                    <div key={pkg.code} className="space-y-1">
                      <div className="flex items-center gap-3">
                        <label htmlFor={`price-${pkg.code}`} className="min-w-0 flex-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                          {pkg.name}
                        </label>
                        <span className="inline-flex items-center gap-1 font-mono text-sm" style={{ color: "var(--text-soft)" }}>
                          <input
                            id={`price-${pkg.code}`}
                            inputMode="decimal"
                            aria-invalid={wrong || undefined}
                            aria-describedby={wrong ? ["price", pkg.code, "error"].join("-") : undefined}
                            className="w-20 rounded-lg px-2 py-1.5 text-end font-mono text-sm"
                            style={{ background: "var(--panel-muted)", border: `1px solid ${wrong ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
                            value={drafts[pkg.code] ?? formatPrice(pkg.cents)}
                            onChange={(event) => setDrafts((current) => ({ ...current, [pkg.code]: event.target.value }))}
                          />
                          {symbol}
                          {pkg.period === "monthly" ? t("perMonth") : pkg.period === "annual" ? t("perYear") : ""}
                        </span>
                      </div>
                      {wrong ? (
                        <ErrorNotice variant="field" id={["price", pkg.code, "error"].join("-")}>{t("priceInvalid")}</ErrorNotice>
                      ) : null}
                    </div>
                  );
                })}
              </section>
              <section className="space-y-2 rounded-2xl p-4" style={card} aria-labelledby="recipe-rules">
                <h2 id="recipe-rules" className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("typesAndRules")}</h2>
                {preview.classTypes.length ? (
                  <div className="flex flex-wrap gap-1.5">
                    {preview.classTypes.map((name) => (
                      <span
                        key={name}
                        className="inline-flex rounded-full px-2.5 py-1 text-xs font-bold"
                        style={{ color: "var(--text)", border: "1px solid var(--primary)", background: "color-mix(in srgb, var(--primary) 12%, var(--panel))" }}
                      >
                        {name}
                      </span>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs" style={quiet}>{t("noClassTypes")}</p>
                )}
                <ul className="grid list-disc gap-1 ps-5 text-sm" style={{ color: "var(--text-soft)" }}>
                  {preview.rules.map((rule) => (
                    <li key={rule.key}>{ruleText(rule)}</li>
                  ))}
                  {preview.advanced > 0 ? <li>{t("advancedCount", { count: preview.advanced })}</li> : null}
                </ul>
              </section>
            </div>
            {owned.length > 0 ? (
              <section
                className="space-y-3 rounded-2xl p-4"
                style={{ ...card, borderColor: modeMissing ? "var(--danger)" : "var(--border)" }}
                aria-labelledby="recipe-owner-values"
                data-testid="recipe-owner-values"
              >
                <div>
                  <h2 id="recipe-owner-values" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {t("ownerValues.title", { count: owned.length })}
                  </h2>
                  <p className="text-xs" style={quiet}>{t("ownerValues.intro")}</p>
                </div>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-start text-xs" style={quiet}>
                      <th className="py-1 text-start font-semibold">{t("ownerValues.setting")}</th>
                      <th className="py-1 text-start font-semibold">{t("ownerValues.current")}</th>
                      <th className="py-1 text-start font-semibold">{t("ownerValues.proposed")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {owned.map((change) => (
                      <tr key={change.key} style={{ borderTop: "1px solid var(--border)" }} data-testid={`owner-value-${change.key}`}>
                        <td className="py-1.5 pe-3" style={{ color: "var(--text)" }}>{t(`ownerValues.labels.${labelKey(change.key)}`)}</td>
                        <td className="py-1.5 pe-3 font-semibold" style={{ color: "var(--text)" }}>{valueText(change, change.from)}</td>
                        <td className="py-1.5" style={{ color: "var(--text-soft)" }}>{valueText(change, change.to)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div role="radiogroup" aria-labelledby="recipe-owner-values" className="grid gap-2 sm:grid-cols-2">
                  {(["all", "defaults_only"] as const).map((value) => (
                    <label
                      key={value}
                      className="flex cursor-pointer items-start gap-3 rounded-xl px-3 py-2.5"
                      style={{ background: "var(--panel-muted)", border: `1px solid ${mode === value ? "var(--primary)" : "var(--border)"}` }}
                    >
                      <input
                        type="radio"
                        name="recipe-mode"
                        className="mt-1"
                        checked={mode === value}
                        onChange={() => {
                          setMode(value);
                          setModeMissing(false);
                        }}
                      />
                      <span>
                        <b className="block text-sm" style={{ color: "var(--text)" }}>{t(`ownerValues.${value}`)}</b>
                        <span className="block text-xs" style={quiet}>{t(`ownerValues.${value}Hint`)}</span>
                      </span>
                    </label>
                  ))}
                </div>
                {modeMissing ? <ErrorNotice variant="field">{t("ownerValues.choose")}</ErrorNotice> : null}
              </section>
            ) : null}
            {plan.data && plan.data.change_count === 0 ? <p className="text-sm" style={quiet}>{t("nothingToChange")}</p> : null}
            {!canApply ? <p className="text-sm" style={quiet}>{t("ownerOnly")}</p> : null}
            {apply.error ? <ErrorNotice>{errorText(apply.error)}</ErrorNotice> : null}
            <div className="flex justify-end">
              <button
                type="button"
                data-testid="recipe-apply"
                className={button}
                style={SPARK_GO_STYLE}
                disabled={!canApply || apply.isPending || plan.data?.change_count === 0}
                onClick={onApply}
              >
                {t("apply")}
              </button>
            </div>
          </>
        )}
      </>
    );
  } else if (step === "done" && applied && recipe) {
    const counts = appliedCounts(applied);
    const steps = [
      { href: "/admin/settings/billing", title: t("next.billing"), hint: t("next.billingHint") },
      { href: "/admin/settings?tab=payments", title: t("next.payments"), hint: t("next.paymentsHint") },
      {
        href: "/admin/finance?tab=packages",
        title: t("next.soldOnline"),
        hint:
          isConnected(payments.data) && payments.data?.online_sales
            ? t("next.soldOnlineHint", { count: payments.data.online_sales.sold_online, total: payments.data.online_sales.packages })
            : t("next.soldOnlineLater"),
      },
      { href: "/admin/users/import", title: t("next.import"), hint: t("next.importHint") },
      { href: "/admin/settings/box-screens", title: t("next.screens"), hint: t("next.screensHint") },
    ];
    body = (
      <>
        <section className="space-y-2 rounded-2xl p-4" style={{ ...card, borderColor: "var(--success)" }} data-testid="recipe-applied">
          <div className="flex flex-wrap items-start gap-3">
            <span style={{ color: "var(--success)" }}>
              <LineIcon name="check" />
            </span>
            <div className="min-w-0 flex-1">
              <b className="block text-sm" style={{ color: "var(--text)" }}>{t("appliedTitle", { name: nameOf(recipe) })}</b>
              <p className="text-xs" style={quiet}>
                {t("appliedCounts", { packages: counts.packages, types: counts.classTypes, rules: counts.rules })}
              </p>
              {applied.plan.kept.length > 0 ? (
                <p className="text-xs" style={quiet} data-testid="recipe-kept">{t("ownerValues.kept", { count: applied.plan.kept.length })}</p>
              ) : null}
            </div>
            <button
              type="button"
              className={button}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              onClick={() => {
                setApplied(null);
                setStep("pick");
              }}
            >
              {t("otherRecipe")}
            </button>
          </div>
        </section>
        <section className="space-y-2 rounded-2xl p-4" style={card} aria-labelledby="recipe-next">
          <h2 id="recipe-next" className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("next.title")}</h2>
          <ol className="space-y-1">
            {steps.map((entry, index) => (
              <li key={entry.title}>
                <Link href={adminHref(entry.href, slug)} className="flex items-center gap-3 rounded-xl py-2">
                  <span
                    className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                    style={{ border: "1.5px solid var(--border-strong)", color: "var(--muted)" }}
                  >
                    {index + 1}
                  </span>
                  <span className="min-w-0 flex-1">
                    <b className="block text-sm" style={{ color: "var(--text)" }}>{entry.title}</b>
                    <span className="block text-xs" style={quiet}>{entry.hint}</span>
                  </span>
                  <span aria-hidden="true" style={{ color: "var(--primary)" }}>›</span>
                </Link>
              </li>
            ))}
          </ol>
        </section>
      </>
    );
  }

  return (
    <main className="min-h-screen px-4 py-8 sm:px-6 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-4">{body}</div>
    </main>
  );
}
