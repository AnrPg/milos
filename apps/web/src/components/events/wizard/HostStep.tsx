"use client";

import { useTranslations } from "next-intl";

import { FieldGroup, Hint, SegmentGrid } from "./fields";
import type { EventWizardClubs, EventWizardHosts } from "./types";

/** Step 1, «Διοργάνωση ως» (ADR-185): «Ως εγώ» or a business, then the club it goes in. */
export function HostStep({ hosts, hint, clubs }: { hosts: EventWizardHosts | null; hint?: string | null; clubs: EventWizardClubs | null }) {
  const t = useTranslations("Events");
  return (
    <div className="flex flex-col gap-5">
      {hosts && hosts.options.length > 1 ? (
        <FieldGroup legend={t("hostAs")}>
          <SegmentGrid
            label={t("hostAs")}
            value={hosts.value}
            onChange={hosts.onChange}
            stack
            options={hosts.options.map((option) => ({ value: option.id, label: option.label, hint: option.hint }))}
          />
          {hint ? <Hint>{hint}</Hint> : null}
        </FieldGroup>
      ) : null}
      {clubs && clubs.options.length > 1 ? (
        <FieldGroup legend={t("fieldClub")}>
          <SegmentGrid
            label={t("fieldClub")}
            value={clubs.value ?? null}
            onChange={clubs.onChange}
            stack
            options={clubs.options.map((club) => ({ value: club.id, label: club.name || "?" }))}
          />
        </FieldGroup>
      ) : null}
    </div>
  );
}
