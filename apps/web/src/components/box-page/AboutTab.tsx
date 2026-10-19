"use client";

import dynamic from "next/dynamic";
import { useMemo, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { PublicBoxPage } from "@/api/social";
import { languageNames } from "@/components/admin/public-page/languages";
import { PersonAvatar } from "@/components/social/PersonAvatar";

import { Icon } from "./Icon";

const PlacesMap = dynamic(() => import("@/components/member-app/box/schedule/PlacesMap"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse" style={{ background: "var(--panel-raised)" }} />,
});

type Location = PublicBoxPage["locations"][number];
type Span = { weekday: number; opens: string; closes: string };

const SHOWN_DISCIPLINES = 6;
const ABOUT_PREVIEW = 320;

/**
 * «Σχετικά» (plan §5a board 4 Q3): text, photo strip, disciplines, who it
 * welcomes, services, coaches, amenities, languages, then locations with the
 * map and opening hours. Only what the owner published.
 */
export function AboutTab({ page, onOpenPhoto }: { page: PublicBoxPage; onOpenPhoto: (index: number) => void }) {
  const t = useTranslations("BoxPage");
  const tags = useTranslations("BoxTags");
  const locale = useLocale();
  const profile = page.profile;
  const [aboutOpen, setAboutOpen] = useState(false);
  const [allDisciplines, setAllDisciplines] = useState(false);
  const names = useMemo(() => languageNames(locale), [locale]);
  const about = profile.about ?? "";
  const longAbout = about.length > ABOUT_PREVIEW;
  const photoOffset = profile.cover ? 1 : 0;
  const disciplines = allDisciplines ? profile.disciplines : profile.disciplines.slice(0, SHOWN_DISCIPLINES);
  const hiddenDisciplines = profile.disciplines.length - disciplines.length;

  return (
    <div className="flex flex-col gap-7">
      {about ? (
        <section className="flex flex-col gap-2">
          <p
            className={`whitespace-pre-line text-[15px] leading-relaxed ${longAbout && !aboutOpen ? "line-clamp-5" : ""}`}
            style={{ color: "var(--text)" }}
          >
            {about}
          </p>
          {longAbout ? (
            <button
              type="button"
              onClick={() => setAboutOpen((open) => !open)}
              aria-expanded={aboutOpen}
              className="self-start text-sm font-bold"
              style={{ color: "var(--primary-strong)" }}
            >
              {aboutOpen ? t("less") : t("more")}
            </button>
          ) : null}
        </section>
      ) : null}

      {profile.photos.length > 0 ? (
        <section aria-label={t("photosTitle")}>
          <ul className="-mx-4 flex snap-x gap-2 overflow-x-auto px-4 pb-1 lg:mx-0 lg:px-0">
            {profile.photos.map((photo, index) => (
              <li key={photo.id} className="shrink-0 snap-start">
                <button
                  type="button"
                  onClick={() => onOpenPhoto(index + photoOffset)}
                  aria-label={t("photoAlt", { current: index + 1 })}
                  className="block h-32 w-44 overflow-hidden rounded-2xl"
                  style={{ background: "var(--panel-raised)" }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element -- media from the gym's storage */}
                  <img src={photo.url} alt="" loading="lazy" className="h-full w-full object-cover" />
                </button>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {profile.disciplines.length > 0 ? (
        <Section title={t("disciplines")}>
          <ul className="flex flex-wrap gap-2">
            {disciplines.map((key) => (
              <li key={key} className="rounded-full px-3 py-1.5 text-sm font-semibold" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
                {tags(`discipline.${key}`)}
              </li>
            ))}
            {hiddenDisciplines > 0 ? (
              <li>
                <button
                  type="button"
                  onClick={() => setAllDisciplines(true)}
                  className="rounded-full px-3 py-1.5 text-sm font-bold"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  aria-label={t("moreDisciplines", { count: hiddenDisciplines })}
                >
                  +{hiddenDisciplines}
                </button>
              </li>
            ) : null}
          </ul>
        </Section>
      ) : null}

      {profile.audiences.length > 0 ? (
        <p className="text-[15px]" style={{ color: "var(--text)" }}>
          <span className="font-bold">{t("welcomes")}</span> {profile.audiences.map((key) => tags(`audience.${key}`)).join(", ")}
        </p>
      ) : null}

      {profile.services.length > 0 ? (
        <Section title={t("services")}>
          <ul className="flex flex-wrap gap-2">
            {profile.services.map((key) => (
              <li key={key} className="rounded-full px-3 py-1.5 text-sm" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                {tags(`service.${key}`)}
              </li>
            ))}
          </ul>
        </Section>
      ) : null}

      {profile.coaches.length > 0 ? (
        <Section title={t("coaches")}>
          <ul className="-mx-4 flex gap-3 overflow-x-auto px-4 pb-1 lg:mx-0 lg:grid lg:grid-cols-2 lg:px-0">
            {profile.coaches.map((coach) => (
              <li
                key={coach.id}
                className="flex w-56 shrink-0 items-center gap-3 rounded-2xl p-3 lg:w-auto"
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              >
                <PersonAvatar name={coach.nickname ?? "?"} url={coach.avatar_url} size={48} />
                <span className="flex min-w-0 flex-col">
                  <span className="truncate font-bold" style={{ color: "var(--text)" }}>{coach.nickname ?? "?"}</span>
                  {coach.class_types.length > 0 ? (
                    <span className="line-clamp-2 text-xs" style={{ color: "var(--dim)" }}>{coach.class_types.join(" · ")}</span>
                  ) : null}
                </span>
              </li>
            ))}
          </ul>
        </Section>
      ) : null}

      {profile.amenities.length > 0 ? (
        <Section title={t("amenities")}>
          <ul className="grid grid-cols-2 gap-x-4 gap-y-3">
            {profile.amenities.map((key) => (
              <li key={key} className="flex items-center gap-2.5 text-sm" style={{ color: "var(--text)" }}>
                <span style={{ color: "var(--text-soft)" }}>
                  <Icon amenity={key} />
                </span>
                <span className="min-w-0">{tags(`amenity.${key}`)}</span>
              </li>
            ))}
          </ul>
        </Section>
      ) : null}

      {profile.languages.length > 0 ? (
        <Section title={t("languages")}>
          <p className="text-[15px]" style={{ color: "var(--text)" }}>
            {profile.languages.map((code) => names(code).own).join(" · ")}
          </p>
        </Section>
      ) : null}

      {page.locations.length > 0 ? (
        <Section title={page.locations.length > 1 ? t("locations") : t("location")}>
          <Locations locations={page.locations} />
        </Section>
      ) : null}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{title}</h2>
      {children}
    </section>
  );
}

function Locations({ locations }: { locations: Location[] }) {
  const t = useTranslations("BoxPage");
  const pinned = locations.filter((location) => location.latitude != null && location.longitude != null);
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      {pinned.length > 0 ? (
        <div className="h-52 overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
          <PlacesMap
            places={pinned.map((location) => ({
              id: location.id,
              name: location.name,
              latitude: location.latitude!,
              longitude: location.longitude!,
              selected: location.id === selected,
            }))}
            ariaLabel={t("mapAria")}
            onBoundsChange={() => undefined}
            onSelect={setSelected}
          />
        </div>
      ) : null}
      <ul className="flex flex-col gap-3">
        {locations.map((location) => (
          <LocationCard key={location.id} location={location} single={locations.length === 1} />
        ))}
      </ul>
    </div>
  );
}

function LocationCard({ location, single }: { location: Location; single: boolean }) {
  const t = useTranslations("BoxPage");
  const place = [location.address, location.neighbourhood ?? location.city].filter(Boolean).join(", ");
  const directions =
    location.latitude != null && location.longitude != null
      ? `https://www.google.com/maps/dir/?api=1&destination=${location.latitude},${location.longitude}`
      : null;
  const spans = (location.opening_hours ?? []) as Span[];

  return (
    <li className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-start gap-3">
        <span className="mt-0.5" style={{ color: "var(--text-soft)" }}>
          <Icon name="map-pin" />
        </span>
        <span className="flex min-w-0 flex-1 flex-col">
          {single ? null : <span className="font-bold" style={{ color: "var(--text)" }}>{location.name}</span>}
          <span className="text-sm" style={{ color: single ? "var(--text)" : "var(--text-soft)" }}>{place || location.name}</span>
        </span>
        {directions ? (
          <a
            href={directions}
            target="_blank"
            rel="noreferrer"
            className="shrink-0 rounded-full px-3 py-1.5 text-xs font-bold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("directions")}
          </a>
        ) : null}
      </div>
      {spans.length > 0 ? <OpeningHours spans={spans} /> : null}
    </li>
  );
}

/** Today's hours on one line; the whole week opens under it. Monday first (ISO weekday). */
export function OpeningHours({ spans }: { spans: Span[] }) {
  const t = useTranslations("BoxPage");
  const locale = useLocale();
  const dayName = new Intl.DateTimeFormat(locale, { weekday: "long" });
  // 2024-01-01 was a Monday.
  const label = (weekday: number) => dayName.format(new Date(2024, 0, weekday));
  const today = ((new Date().getDay() + 6) % 7) + 1;
  const hours = (weekday: number) => {
    const day = spans.filter((span) => span.weekday === weekday).sort((a, b) => a.opens.localeCompare(b.opens));
    return day.length > 0 ? day.map((span) => `${span.opens}–${span.closes}`).join(", ") : t("closed");
  };

  return (
    <details className="group">
      <summary className="flex cursor-pointer list-none items-center gap-3 text-sm" style={{ color: "var(--text)" }}>
        <span style={{ color: "var(--text-soft)" }}>
          <Icon name="clock" />
        </span>
        <span className="flex-1">
          <span className="font-bold">{t("today")}</span> {hours(today)}
        </span>
        <span className="text-xs font-semibold group-open:hidden" style={{ color: "var(--primary-strong)" }}>{t("allWeek")}</span>
      </summary>
      <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 ps-8 text-sm">
        {[1, 2, 3, 4, 5, 6, 7].map((weekday) => (
          <div key={weekday} className="contents" style={{ fontWeight: weekday === today ? 700 : 400 }}>
            <dt className="first-letter:uppercase" style={{ color: "var(--text-soft)" }}>{label(weekday)}</dt>
            <dd style={{ color: "var(--text)" }}>{hours(weekday)}</dd>
          </div>
        ))}
      </dl>
    </details>
  );
}
