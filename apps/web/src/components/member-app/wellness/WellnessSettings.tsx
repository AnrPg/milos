"use client";

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  eraseWellness,
  exportWellness,
  grantHealthDataConsent,
  updateWellnessPreferences,
  WELLNESS_ITEMS,
  type WellnessItem,
  type WellnessPreferences,
  type WellnessSection,
} from "@/api/wellness";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { wellnessErrorMessage } from "./wellness-errors";
import { fullOrder, moveItem } from "./wellness-model";
import { ErrorLine, PrimaryButton, QuietButton, SheetSection, WellnessSheet } from "./WellnessSheet";

const GLASS_SIZES = [200, 250, 330, 500];

function Toggle({ on, label, onChange }: { on: boolean; label: string; onChange: (on: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={() => onChange(!on)}
      className="relative h-7 w-12 shrink-0 rounded-full"
      style={{ background: on ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
    >
      <span
        className="absolute top-0.5 h-5 w-5 rounded-full transition-all"
        style={{ background: "var(--bg)", insetInlineStart: on ? "1.5rem" : "0.2rem" }}
      />
    </button>
  );
}

/**
 * First visit (board 14, Q9 «ask»): what Ευεξία keeps and who sees it, the
 * health-data consent it needs, and which items to show, all on by default.
 */
export function WellnessConsentCard({ preferences, onDone }: { preferences: WellnessPreferences; onDone: () => void }) {
  const t = useTranslations("MemberApp.wellness");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const [hidden, setHidden] = useState<WellnessItem[]>(preferences.hidden_items);

  const start = useMutation({
    mutationFn: async () => {
      await grantHealthDataConsent(tokens!.access_token);
      await updateWellnessPreferences(tokens!.access_token, { hidden_items: hidden });
    },
    onSuccess: onDone,
  });

  return (
    <section
      aria-labelledby="wellness-consent-title"
      className="flex flex-col gap-4 rounded-3xl p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("eyebrow")}</p>
        <h2 id="wellness-consent-title" className="text-xl font-extrabold" style={{ color: "var(--text)" }}>
          {t("consent.title")}
        </h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("consent.body")}</p>
      </div>
      <SheetSection label={t("consent.items")}>
        <ul className="flex flex-col gap-2">
          {WELLNESS_ITEMS.map((item) => (
            <li key={item} className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`item.${item}`)}</span>
              <Toggle
                on={!hidden.includes(item)}
                label={t(`item.${item}`)}
                onChange={(on) => setHidden((current) => (on ? current.filter((entry) => entry !== item) : [...current, item]))}
              />
            </li>
          ))}
        </ul>
      </SheetSection>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("consent.later")}</p>
      <ErrorLine message={start.error ? wellnessErrorMessage(start.error, (key) => t(key), ui) : null} />
      <PrimaryButton disabled={start.isPending} onClick={() => start.mutate()}>
        {start.isPending ? t("saving") : t("consent.agree")}
      </PrimaryButton>
    </section>
  );
}

function download(name: string, data: unknown) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = name;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}

/**
 * «Προσαρμογή» (board 14, Q1 order, Q2, Q9): which items show and in what
 * order, the member's own targets, the opt-in water reminder, and per
 * section export and delete-all. Turning an item off keeps its data.
 */
export function WellnessCustomizeSheet({
  preferences,
  onClose,
  onSaved,
}: {
  preferences: WellnessPreferences;
  onClose: () => void;
  onSaved: () => void;
}) {
  const t = useTranslations("MemberApp.wellness");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const [order, setOrder] = useState<WellnessItem[]>(preferences.item_order);
  const [hidden, setHidden] = useState<WellnessItem[]>(preferences.hidden_items);
  const [glass, setGlass] = useState(preferences.glass_ml);
  const [goalGlasses, setGoalGlasses] = useState(Math.round(preferences.water_goal_ml / preferences.glass_ml));
  const [sleepHours, setSleepHours] = useState(preferences.sleep_goal_minutes / 60);
  const [reminder, setReminder] = useState(preferences.water_reminder);
  const [confirming, setConfirming] = useState<WellnessSection | null>(null);
  const [erased, setErased] = useState<WellnessSection | null>(null);

  const save = useMutation({
    mutationFn: async () =>
      updateWellnessPreferences(tokens!.access_token, {
        item_order: order,
        hidden_items: hidden,
        glass_ml: glass,
        water_goal_ml: Math.min(8000, Math.max(250, goalGlasses * glass)),
        sleep_goal_minutes: Math.round(sleepHours * 60),
        water_reminder: reminder,
      }),
    onSuccess: () => {
      onSaved();
      onClose();
    },
  });

  const exporter = useMutation({
    mutationFn: async (section: WellnessSection) => exportWellness(tokens!.access_token, [section]),
    onSuccess: (data, section) => download(`milos-${section}.json`, data),
  });

  const eraser = useMutation({
    mutationFn: async (section: WellnessSection) => eraseWellness(tokens!.access_token, [section]),
    onSuccess: (_data, section) => {
      setConfirming(null);
      setErased(section);
      onSaved();
    },
  });

  const error = save.error ?? exporter.error ?? eraser.error;

  return (
    <WellnessSheet title={t("customize")} onClose={onClose}>
      <SheetSection label={t("settings.items")}>
        <ul className="flex flex-col gap-2">
          {fullOrder(order).map((item, index, all) => (
              <li key={item} className="flex items-center justify-between gap-2">
                <span className="text-sm font-semibold" style={{ color: hidden.includes(item) ? "var(--dim)" : "var(--text)" }}>
                  {t(`item.${item}`)}
                </span>
                <span className="flex items-center gap-1">
                  <button
                    type="button"
                    aria-label={t("settings.moveUp", { item: t(`item.${item}`) })}
                    disabled={index === 0}
                    onClick={() => setOrder(moveItem(order, item, -1))}
                    className="h-8 w-8 rounded-full disabled:opacity-30"
                    style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    aria-label={t("settings.moveDown", { item: t(`item.${item}`) })}
                    disabled={index === all.length - 1}
                    onClick={() => setOrder(moveItem(order, item, 1))}
                    className="h-8 w-8 rounded-full disabled:opacity-30"
                    style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    ↓
                  </button>
                  <Toggle
                    on={!hidden.includes(item)}
                    label={t(`item.${item}`)}
                    onChange={(on) => setHidden((current) => (on ? current.filter((entry) => entry !== item) : [...current, item]))}
                  />
                </span>
              </li>
            ))}
        </ul>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.hiddenKeeps")}</p>
      </SheetSection>

      <SheetSection label={t("settings.water")}>
        <label className="flex items-center justify-between gap-3 text-sm" style={{ color: "var(--text)" }}>
          {t("settings.glass")}
          <select
            value={glass}
            onChange={(event) => setGlass(Number(event.target.value))}
            className="min-h-10 rounded-xl px-3"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {GLASS_SIZES.map((size) => (
              <option key={size} value={size}>{t("settings.ml", { ml: size })}</option>
            ))}
          </select>
        </label>
        <label className="flex items-center justify-between gap-3 text-sm" style={{ color: "var(--text)" }}>
          {t("settings.goalGlasses")}
          <input
            type="number"
            min={1}
            max={20}
            value={goalGlasses}
            onChange={(event) => setGoalGlasses(Math.max(1, Math.min(20, Number(event.target.value) || 1)))}
            className="min-h-10 w-20 rounded-xl px-3 text-end"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
        <div className="flex items-center justify-between gap-3">
          <span className="text-sm" style={{ color: "var(--text)" }}>
            {t("settings.reminder")}
            <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("settings.reminderHint")}</span>
          </span>
          <Toggle on={reminder} label={t("settings.reminder")} onChange={setReminder} />
        </div>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.goalYours")}</p>
      </SheetSection>

      <SheetSection label={t("settings.sleep")}>
        <label className="flex items-center justify-between gap-3 text-sm" style={{ color: "var(--text)" }}>
          {t("settings.sleepGoal")}
          <input
            type="number"
            min={4}
            max={12}
            step={0.5}
            value={sleepHours}
            onChange={(event) => setSleepHours(Math.max(4, Math.min(12, Number(event.target.value) || 7)))}
            className="min-h-10 w-20 rounded-xl px-3 text-end"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
      </SheetSection>

      <ErrorLine message={error ? wellnessErrorMessage(error, (key) => t(key), ui) : null} />
      <PrimaryButton disabled={save.isPending} onClick={() => save.mutate()}>
        {save.isPending ? t("saving") : t("save")}
      </PrimaryButton>

      <SheetSection label={t("settings.data")}>
        {(["wellness", "cravings"] as WellnessSection[]).map((section) => (
          <div key={section} className="flex flex-col gap-2 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`settings.section.${section}`)}</span>
            <div className="flex flex-wrap gap-2">
              <QuietButton disabled={exporter.isPending} onClick={() => exporter.mutate(section)}>
                {t("settings.export")}
              </QuietButton>
              {confirming === section ? (
                <>
                  <QuietButton danger disabled={eraser.isPending} onClick={() => eraser.mutate(section)}>
                    {t("settings.eraseConfirm")}
                  </QuietButton>
                  <QuietButton onClick={() => setConfirming(null)}>{t("cancel")}</QuietButton>
                </>
              ) : (
                <QuietButton danger onClick={() => setConfirming(section)}>
                  {t("settings.erase")}
                </QuietButton>
              )}
            </div>
            {confirming === section ? (
              <p className="text-xs" style={{ color: "var(--danger)" }}>{t("settings.eraseWarning")}</p>
            ) : null}
            {erased === section ? (
              <p role="status" className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.erased")}</p>
            ) : null}
          </div>
        ))}
      </SheetSection>
    </WellnessSheet>
  );
}
