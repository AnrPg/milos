"use client";

import { useTranslations } from "next-intl";

import { formatScore } from "@/i18n/presentation";

export function LocalizedScore({
  value,
  scoreType,
  unit,
}: {
  value: unknown;
  scoreType?: unknown;
  unit?: unknown;
}) {
  const translate = useTranslations("Ui");
  return <bdi>{formatScore(value, scoreType, unit, translate)}</bdi>;
}
