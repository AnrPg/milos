"use client";

import { useTranslations } from "next-intl";

import { roleLabel, semanticLabel } from "@/i18n/presentation";

export function SemanticLabel({ value }: { value: unknown }) {
  const translate = useTranslations("Ui");
  return <bdi>{semanticLabel(value, translate)}</bdi>;
}

/** A business role (owner … athlete) in the canonical wording. */
export function RoleLabel({ role }: { role: unknown }) {
  const translate = useTranslations("Ui");
  return <bdi>{roleLabel(role, translate)}</bdi>;
}
