"use client";

import { useTranslations } from "next-intl";

import { semanticLabel } from "@/i18n/presentation";

export function SemanticLabel({ value }: { value: unknown }) {
  const translate = useTranslations("Ui");
  return <bdi>{semanticLabel(value, translate)}</bdi>;
}
