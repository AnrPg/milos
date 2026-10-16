"use client";

import { useTranslations } from "next-intl";

import { NewEntryButton } from "@/components/member-app/journal/NewEntrySheet";
import { useSelectedMembershipRole } from "@/lib/membership-role";

export function JournalHeader() {
  const t = useTranslations("MemberApp");
  const { role } = useSelectedMembershipRole();
  if (role === "admin") return null;
  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-4 px-4 pt-4 md:px-10">
      <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("journalTitle")}</h1>
      <NewEntryButton />
    </div>
  );
}
