"use client";

import { useTranslations } from "next-intl";
import { useCallback } from "react";

import type { PlanText } from "@/lib/structured-plan";

/** Words a translatable `PlanText` (an i18n key with values) from the structured-plan core. */
export function usePlanText(): (text: PlanText) => string {
  const t = useTranslations();
  return useCallback((text: PlanText) => t(text.key, text.values), [t]);
}

/** Translates a full message key (`PlanCore.flow.sets`). */
export function useKeyText(): (key: string, values?: Record<string, string | number>) => string {
  const t = useTranslations();
  return useCallback((key: string, values?: Record<string, string | number>) => t(key, values), [t]);
}
