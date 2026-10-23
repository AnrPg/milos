"use client";

import type { ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { EventScope } from "@/api/events";
import { asksCohosts, asksGoodForFriends, asksGuestPass, PROBLEM_STEP, type EventWizardStep } from "@/lib/event-wizard";
import { formatInZone, zoneLabel } from "@/lib/zoned-time";

import { ScopePicker, type EventLocation } from "../EventFormParts";
import { formAudience, formatPrice, localInstant, parsePriceCents } from "../events";
import type { StepProps } from "./types";
import { useDurationLabel } from "./WhenStep";
import { useAudienceOptions } from "./WhoStep";

/**
 * Step 7: everything on one screen, grouped as the steps asked it, each
 * group with «Αλλαγή» back to its step. A weekly event's edit asks here
 * whether it changes this one or the following too.
 */
export function ReviewStep({
  form,
  mode,
  context,
  problems,
  steps,
  stepLabel,
  hostLabel,
  clubLabel,
  locations,
  coverUrl,
  cohosts,
  gymZone,
  series,
  scope,
  onScope,
  onEdit,
}: StepProps & {
  steps: EventWizardStep[];
  stepLabel: (step: EventWizardStep) => string;
  hostLabel: string | null;
  clubLabel: string | null;
  locations: EventLocation[];
  coverUrl: string | null;
  cohosts: string[];
  gymZone: string | null;
  series: boolean;
  scope: EventScope;
  onScope: (scope: EventScope) => void;
  onEdit: (step: EventWizardStep) => void;
}) {
  const t = useTranslations("Events");
  const tw = useTranslations("EventWizard");
  const locale = useLocale();
  const durationLabel = useDurationLabel();
  const audiences = useAudienceOptions(mode);
  const zone = form.timeZone ?? gymZone;
  const start = localInstant(form.date, form.time, zone);
  const end = start ? new Date(start.getTime() + form.durationMinutes * 60_000) : null;
  const away = Boolean(gymZone && zone && zone !== gymZone);
  const place =
    form.place.kind === "location"
      ? (locations.find((location) => form.place.kind === "location" && location.id === form.place.locationId)?.name ?? null)
      : [form.place.name.trim(), form.place.address.trim()].filter(Boolean).join(" · ") || null;
  const audience = audiences.find((option) => option.value === formAudience(form, mode));
  const price = form.paid ? formatPrice(parsePriceCents(form.price) ?? 0, "EUR", locale) : t("free");
  const broken = (step: EventWizardStep) => problems.filter((problem) => PROBLEM_STEP[problem] === step);

  const sections: Record<Exclude<EventWizardStep, "review">, ReactNode[]> = {
    host: [hostLabel, clubLabel].filter(Boolean),
    basics: [
      form.title.trim() || null,
      form.coverMediaId ? (
        coverUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
          <img key="cover" src={coverUrl} alt="" className="aspect-[16/6] w-full rounded-xl object-cover" />
        ) : (
          t("fieldCover")
        )
      ) : (
        tw("reviewNoCover")
      ),
      form.description.trim() ? <span key="description" className="line-clamp-3 whitespace-pre-line">{form.description.trim()}</span> : tw("reviewNoDescription"),
    ],
    when: [
      start && end
        ? [
            formatInZone(start, zone, locale, { weekday: "long", day: "numeric", month: "long", year: "numeric" }),
            [formatInZone(start, zone, locale, "time"), formatInZone(end, zone, locale, "time")].join("–") + (away && zone ? ` ${zoneLabel(zone)}` : ""),
          ].join(" · ")
        : null,
      durationLabel(form.durationMinutes),
      !context.editing && form.repeatWeekly && form.repeatUntil
        ? tw("reviewRepeat", { date: formatInZone(localInstant(form.repeatUntil, "12:00", zone) ?? new Date(), zone, locale, { day: "numeric", month: "long", year: "numeric" }) })
        : null,
    ],
    where: [place],
    who: [
      audience ? `${audience.label} · ${audience.hint}` : null,
      price,
      asksGuestPass(form, mode) ? (form.guestPass ? t("guestPassLine", { count: form.guestsPerMember }) : tw("reviewNoGuests")) : null,
      asksGoodForFriends(form, mode) && form.goodForFriends ? t("fieldGoodForFriends") : null,
    ],
    capacity: [
      form.capacity.trim() ? tw("reviewCapacity", { count: Number(form.capacity.trim()) || 0 }) : tw("reviewNoLimit"),
      asksCohosts(form, context) ? (cohosts.length ? tw("reviewCohosts", { names: cohosts.join(", ") }) : tw("reviewNoCohosts")) : null,
    ],
  };

  return (
    <div className="flex flex-col gap-3">
      {steps
        .filter((step): step is Exclude<EventWizardStep, "review"> => step !== "review")
        .map((step) => {
          const lines = sections[step].filter((line) => line !== null && line !== "");
          const issues = broken(step);
          return (
            <section
              key={step}
              aria-labelledby={`review-${step}`}
              className="flex flex-col gap-1 rounded-2xl px-4 py-3"
              style={{ background: "var(--panel-raised)", border: `1px solid ${issues.length ? "var(--danger)" : "var(--border)"}` }}
            >
              <div className="flex items-center justify-between gap-2">
                <h4 id={`review-${step}`} className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
                  {stepLabel(step)}
                </h4>
                <button
                  type="button"
                  onClick={() => onEdit(step)}
                  aria-label={tw("reviewEditAria", { step: stepLabel(step) })}
                  className="-me-2 min-h-11 shrink-0 px-2 text-sm font-semibold"
                  style={{ color: "var(--primary)" }}
                >
                  {tw("reviewEdit")}
                </button>
              </div>
              <div className="flex flex-col gap-1 text-sm" style={{ color: "var(--text)" }}>
                {lines.map((line, index) => (
                  <div key={index} className="min-w-0 [overflow-wrap:anywhere]">
                    {line}
                  </div>
                ))}
              </div>
              {issues.map((problem) => (
                <p key={problem} className="text-sm" style={{ color: "var(--danger)" }}>
                  {t(["problem", problem].join("_"))}
                </p>
              ))}
            </section>
          );
        })}
      {series ? <ScopePicker value={scope} onChange={onScope} /> : null}
    </div>
  );
}
