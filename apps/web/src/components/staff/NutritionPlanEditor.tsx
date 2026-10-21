"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";
import { useTranslations } from "next-intl";

import { fetchClientNutritionPlan, saveClientNutritionPlan, type NutritionPlan } from "@/api/staff";
import { PORTION_KEYS, type MealSlot, type PortionKey } from "@/api/wellness";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { portionsFromGrams } from "@/components/member-app/wellness/wellness-model";
import { useSession } from "@/components/session-provider";
import { optionalInt, staffErrorMessage } from "@/components/staff/staff-helpers";
import {
  inputClass,
  inputStyle,
  captionClass,
  captionStyle,
  primaryButtonClass,
  primaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

type PlanForm = {
  title: string;
  body: string;
  daily_calories: string;
  protein_grams: string;
  carbs_grams: string;
  fat_grams: string;
  portions: Record<PortionKey, string>;
  meal_slots: MealSlot[];
};

const NO_PORTIONS: Record<PortionKey, string> = { protein: "", carbs: "", veg: "", fat: "" };
const PLAN_SLOTS: MealSlot[] = [
  "breakfast",
  "morning_snack",
  "lunch",
  "afternoon_snack",
  "dinner",
  "evening_snack",
  "pre_workout",
  "post_workout",
  "snack",
];

const EMPTY_FORM: PlanForm = {
  title: "",
  body: "",
  daily_calories: "",
  protein_grams: "",
  carbs_grams: "",
  fat_grams: "",
  portions: NO_PORTIONS,
  meal_slots: [],
};

function formFromPlan(plan: NutritionPlan | null): PlanForm {
  if (!plan) return EMPTY_FORM;
  const text = (value: number | null | undefined) => (typeof value === "number" ? String(value) : "");
  return {
    title: plan.title,
    body: plan.body,
    daily_calories: text(plan.daily_calories),
    protein_grams: text(plan.protein_grams),
    carbs_grams: text(plan.carbs_grams),
    fat_grams: text(plan.fat_grams),
    portions: Object.fromEntries(
      PORTION_KEYS.map((key) => [key, text(plan.portion_targets?.[key])]),
    ) as Record<PortionKey, string>,
    meal_slots: plan.meal_slots ?? [],
  };
}

function portionNumber(value: string): number | null {
  if (!value.trim()) return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 && number <= 20 && Number.isInteger(number * 2) ? number : NaN;
}

const NUMBER_FIELDS: Array<{
  key: "daily_calories" | "protein_grams" | "carbs_grams" | "fat_grams";
  labelKey: string;
  max: number;
}> = [
  { key: "daily_calories", labelKey: "stfDailyCalories", max: 10000 },
  { key: "protein_grams", labelKey: "stfProteinGrams", max: 1000 },
  { key: "carbs_grams", labelKey: "stfCarbsGrams", max: 2000 },
  { key: "fat_grams", labelKey: "stfFatGrams", max: 1000 },
];

function PlanEditor({ userId, plan }: { userId: string; plan: NutritionPlan | null }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const baseId = useId();
  const [form, setForm] = useState<PlanForm>(() => formFromPlan(plan));
  const tWellness = useTranslations("MemberApp.wellness");

  const numbers = Object.fromEntries(NUMBER_FIELDS.map(({ key }) => [key, optionalInt(form[key])])) as Record<
    string,
    number | null
  >;
  const numbersValid = NUMBER_FIELDS.every(({ key, max }) => {
    const value = numbers[key];
    return value === null || (Number.isFinite(value) && value <= max && (key !== "daily_calories" || value >= 1));
  });
  const portions = Object.fromEntries(PORTION_KEYS.map((key) => [key, portionNumber(form.portions[key])])) as Record<
    PortionKey,
    number | null
  >;
  const portionsValid = PORTION_KEYS.every((key) => !Number.isNaN(portions[key]));
  const portionTargets = Object.fromEntries(
    PORTION_KEYS.flatMap((key) => (portions[key] !== null && portions[key]! > 0 ? [[key, portions[key]]] : [])),
  );
  const valid = form.title.trim().length >= 2 && form.body.trim().length >= 2 && numbersValid && portionsValid;

  const mutation = useMutation({
    mutationFn: () =>
      saveClientNutritionPlan(tokens!.access_token, userId, {
        title: form.title.trim(),
        body: form.body.trim(),
        daily_calories: numbers.daily_calories,
        protein_grams: numbers.protein_grams,
        carbs_grams: numbers.carbs_grams,
        fat_grams: numbers.fat_grams,
        portion_targets: Object.keys(portionTargets).length ? portionTargets : null,
        meal_slots: form.meal_slots,
      }),
    onSuccess: (saved) => {
      queryClient.setQueryData(["staff", "nutrition-plan", userId], saved);
    },
  });

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid) mutation.mutate();
      }}
    >
      {plan?.updated_at ? (
        <StatusText tone="muted">
          {i18n("stfPlanLastUpdated", {
            time: new Intl.DateTimeFormat(uiLocale, { dateStyle: "medium", timeStyle: "short" }).format(
              new Date(plan.updated_at),
            ),
          })}
        </StatusText>
      ) : (
        <StatusText tone="muted">{i18n("stfNoPlanYet")}</StatusText>
      )}
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-title`} style={captionStyle}>
          {i18n("title768e0c1")}
        </label>
        <input
          id={`${baseId}-title`}
          className={inputClass}
          maxLength={120}
          onChange={(event) => setForm({ ...form, title: event.target.value })}
          required
          style={inputStyle}
          value={form.title}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-body`} style={captionStyle}>
          {i18n("stfPlanText")}
        </label>
        <textarea
          id={`${baseId}-body`}
          className={`${inputClass} min-h-48`}
          maxLength={20000}
          onChange={(event) => setForm({ ...form, body: event.target.value })}
          placeholder={i18n("stfPlanTextPlaceholder")}
          required
          style={inputStyle}
          value={form.body}
        />
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {NUMBER_FIELDS.map(({ key, labelKey, max }) => (
          <div key={key} className="space-y-1">
            <label className={captionClass} htmlFor={`${baseId}-${key}`} style={captionStyle}>
              {i18n(labelKey)}
            </label>
            <input
              id={`${baseId}-${key}`}
              className={inputClass}
              inputMode="numeric"
              max={max}
              min={key === "daily_calories" ? 1 : 0}
              onChange={(event) => setForm({ ...form, [key]: event.target.value })}
              style={inputStyle}
              type="number"
              value={form[key]}
            />
          </div>
        ))}
      </div>
      {!numbersValid ? <StatusText tone="error">{i18n("stfInvalidNumbers")}</StatusText> : null}
      <fieldset className="space-y-2">
        <legend className={captionClass} style={captionStyle}>{i18n("stfPortionsTitle")}</legend>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("stfPortionsHint")}</p>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {PORTION_KEYS.map((key) => (
            <div key={key} className="space-y-1">
              <label className={captionClass} htmlFor={`${baseId}-portion-${key}`} style={captionStyle}>
                {tWellness(`portion.${key}`)}
              </label>
              <input
                id={`${baseId}-portion-${key}`}
                className={inputClass}
                inputMode="decimal"
                max={20}
                min={0}
                step={0.5}
                onChange={(event) => setForm({ ...form, portions: { ...form.portions, [key]: event.target.value } })}
                style={inputStyle}
                type="number"
                value={form.portions[key]}
              />
            </div>
          ))}
        </div>
        <button
          type="button"
          className="rounded-full px-3 py-1.5 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          onClick={() => {
            const derived = portionsFromGrams(numbers);
            setForm({
              ...form,
              portions: Object.fromEntries(
                PORTION_KEYS.map((key) => [key, derived[key] !== undefined ? String(derived[key]) : form.portions[key]]),
              ) as Record<PortionKey, string>,
            });
          }}
        >
          {i18n("stfPortionsFromGrams")}
        </button>
        {!portionsValid ? <StatusText tone="error">{i18n("stfInvalidPortions")}</StatusText> : null}
      </fieldset>
      <fieldset className="space-y-2">
        <legend className={captionClass} style={captionStyle}>{i18n("stfMealSlots")}</legend>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("stfMealSlotsHint")}</p>
        <div className="flex flex-wrap gap-2">
          {PLAN_SLOTS.map((slot) => {
            const on = form.meal_slots.includes(slot);
            return (
              <button
                key={slot}
                type="button"
                aria-pressed={on}
                onClick={() =>
                  setForm({
                    ...form,
                    meal_slots: on
                      ? form.meal_slots.filter((entry) => entry !== slot)
                      : PLAN_SLOTS.filter((entry) => entry === slot || form.meal_slots.includes(entry)),
                  })
                }
                className="rounded-full px-3 py-1.5 text-sm font-semibold"
                style={{
                  background: on ? "var(--primary)" : "var(--panel-raised)",
                  color: on ? "var(--bg)" : "var(--text)",
                  border: "1px solid var(--border)",
                }}
              >
                {tWellness(`slot.${slot}`)}
              </button>
            );
          })}
        </div>
      </fieldset>
      <div className="flex flex-wrap items-center gap-3">
        <button className={primaryButtonClass} disabled={!valid || mutation.isPending} style={primaryButtonStyle} type="submit">
          {mutation.isPending ? i18n("stfSaving") : i18n("stfSavePlan")}
        </button>
        {mutation.isSuccess ? <StatusText tone="success">{i18n("stfPlanSaved")}</StatusText> : null}
        {mutation.isError ? <StatusText tone="error">{staffErrorMessage(mutation.error, i18n)}</StatusText> : null}
      </div>
    </form>
  );
}

export function NutritionPlanEditor() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [clientId, setClientId] = useState("");

  const planQuery = useQuery({
    queryKey: ["staff", "nutrition-plan", clientId],
    enabled: Boolean(token && clientId),
    queryFn: () => fetchClientNutritionPlan(token, clientId),
  });

  return (
    <StaffPanel eyebrow={i18n("stfNutritionEyebrow")} labelledBy="staff-nutrition" title={i18n("stfNutritionTitle")}>
      <div className="space-y-5">
        <div className="max-w-md">
          {token ? (
            <UserSearchField
              label={i18n("stfClient")}
              onChange={(id) => setClientId(id)}
              token={token}
              value={clientId}
            />
          ) : null}
        </div>
        {!clientId ? (
          <StatusText tone="muted">{i18n("stfPickClientForPlan")}</StatusText>
        ) : planQuery.isPending ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : planQuery.isError ? (
          <StatusText tone="error">{staffErrorMessage(planQuery.error, i18n)}</StatusText>
        ) : (
          <PlanEditor
            key={clientId}
            plan={planQuery.data ?? null}
            userId={clientId}
          />
        )}
      </div>
    </StaffPanel>
  );
}
