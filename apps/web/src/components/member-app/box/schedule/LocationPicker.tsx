"use client";

import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { useMemo, useState, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useDrag } from "@use-gesture/react";

import { fetchBookablePlaces, setMyHomeLocation, type BookablePlace } from "@/api/places";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { rememberSelectedOrganization } from "@/lib/organization-slug";

import type { MapBounds } from "./PlacesMap";
import { useRememberScheduleLocation } from "./use-schedule-preferences";
import { Layer } from "@/components/ui/Layer";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const PlacesMap = dynamic(() => import("./PlacesMap"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse" style={{ background: "var(--panel)" }} />,
});

type Position = { latitude: number; longitude: number };

/** Where the list sits over the map: hidden (full map), the middle by default, or most of the screen. */
type Sheet = "hidden" | "middle" | "full";
const SHEET_HEIGHT: Record<Sheet, string> = { hidden: "2.75rem", middle: "50%", full: "85%" };
const SHEET_UP: Record<Sheet, Sheet> = { hidden: "middle", middle: "full", full: "full" };
const SHEET_DOWN: Record<Sheet, Sheet> = { hidden: "hidden", middle: "hidden", full: "middle" };

function inBounds(place: BookablePlace, bounds: MapBounds | null) {
  if (!bounds || typeof place.latitude !== "number" || typeof place.longitude !== "number") return false;
  return (
    place.latitude >= bounds.south &&
    place.latitude <= bounds.north &&
    place.longitude >= bounds.west &&
    place.longitude <= bounds.east
  );
}

/**
 * The Πρόγραμμα location screen (plan §5a decision 6): a street map behind a
 * list that opens in the middle, drags up for more list and down to hide, with «Σε αυτή την περιοχή» (live with the map frame) and
 * «Πιο μακριά». Only places the person can book are listed, nearest first.
 */
export function LocationPicker() {
  const t = useTranslations("LocationPicker");
  const locale = useLocale();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { membership } = useSelectedMembershipRole();
  const rememberLocation = useRememberScheduleLocation(token);
  const [position, setPosition] = useState<Position | null>(null);
  const [locating, setLocating] = useState(false);
  const [bounds, setBounds] = useState<MapBounds | null>(null);
  const [sheet, setSheet] = useState<Sheet>("middle");
  const [error, setError] = useState<string | null>(null);

  const placesQuery = useQuery({
    queryKey: ["bookable-places", position],
    enabled: Boolean(token),
    queryFn: () => fetchBookablePlaces(token!, position),
  });
  const places = useMemo(() => placesQuery.data ?? [], [placesQuery.data]);
  const currentGymId = membership?.organization.id ?? null;
  const gymLocationCount = places.filter((place) => place.organization.id === currentGymId).length;
  const severalGyms = new Set(places.map((place) => place.organization.id)).size > 1;
  const nearby = places.filter((place) => inBounds(place, bounds));
  const further = places.filter((place) => !inBounds(place, bounds));
  const km = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 });

  const mapPlaces = useMemo(
    () =>
      places.flatMap((place) =>
        typeof place.latitude === "number" && typeof place.longitude === "number"
          ? [{ id: place.id, name: place.name, latitude: place.latitude, longitude: place.longitude, selected: place.home }]
          : [],
      ),
    [places],
  );

  const bind = useDrag(({ last, movement: [, dy], tap }) => {
    if (tap) setSheet((value) => (value === "full" ? "middle" : SHEET_UP[value]));
    else if (last && Math.abs(dy) > 40) setSheet((value) => (dy < 0 ? SHEET_UP[value] : SHEET_DOWN[value]));
  });

  function locate() {
    if (!("geolocation" in navigator)) return;
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (result) => {
        setPosition({ latitude: result.coords.latitude, longitude: result.coords.longitude });
        setLocating(false);
      },
      () => setLocating(false),
      { maximumAge: 5 * 60_000, timeout: 10_000 },
    );
  }

  async function choose(place: BookablePlace | null) {
    setError(null);
    const organization = place?.organization ?? membership?.organization;
    if (!organization) return;
    try {
      await rememberLocation(organization.id, place?.id ?? null);
      if (organization.id !== currentGymId) {
        rememberSelectedOrganization(organization.slug);
        await queryClient.invalidateQueries({ queryKey: ["organization-memberships"] });
      }
      router.push("/box/schedule");
    } catch {
      setError(t("chooseFailed"));
    }
  }

  async function makeHome(place: BookablePlace) {
    if (!token) return;
    setError(null);
    try {
      await setMyHomeLocation(token, place.id);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["bookable-places"] }),
        queryClient.invalidateQueries({ queryKey: ["organization-memberships"] }),
      ]);
    } catch {
      setError(t("homeFailed"));
    }
  }

  const row = (place: BookablePlace) => (
    <li key={place.id} className="flex items-stretch gap-2">
      <button
        type="button"
        onClick={() => void choose(place)}
        className="flex min-h-14 flex-1 items-center justify-between gap-3 rounded-2xl px-4 py-2.5 text-left"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>
            {place.name}
          </span>
          <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
            {[severalGyms ? place.organization.name : null, place.neighbourhood ?? place.address].filter(Boolean).join(" · ")}
          </span>
        </span>
        <span className="flex shrink-0 flex-col items-end text-xs" style={{ color: "var(--dim)" }}>
          {typeof place.distance_km === "number" ? t("distance", { km: km.format(place.distance_km) }) : null}
          {place.home ? (
            <span className="font-bold" style={{ color: "var(--primary-strong)" }}>
              {t("home")}
            </span>
          ) : null}
        </span>
      </button>
      {!place.home && place.organization.id === currentGymId && gymLocationCount > 1 ? (
        <button
          type="button"
          onClick={() => void makeHome(place)}
          aria-label={t("makeHome", { name: place.name })}
          title={t("makeHome", { name: place.name })}
          className="grid w-11 place-items-center rounded-2xl text-lg"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }}
        >
          <span aria-hidden="true">☆</span>
        </button>
      ) : null}
    </li>
  );

  return (
    <Layer>
    <main className="fixed inset-0 z-(--z-drawer) flex flex-col" style={{ background: "var(--bg)" }}>
      <header className="z-10 flex items-center gap-2 px-4 pb-2 pt-4" style={{ background: "var(--bg)" }}>
        <button
          type="button"
          onClick={() => router.back()}
          aria-label={t("back")}
          className="grid h-10 w-10 place-items-center rounded-full text-xl"
          style={{ color: "var(--text)" }}
        >
          <span aria-hidden="true">‹</span>
        </button>
        <h1 className="flex-1 text-xl font-extrabold" style={{ color: "var(--text)" }}>
          {t("title")}
        </h1>
        <button
          type="button"
          onClick={locate}
          disabled={locating}
          className="min-h-11 rounded-full px-3 text-xs font-bold disabled:opacity-60"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {position ? t("usingMyLocation") : t("useMyLocation")}
        </button>
      </header>

      <div className="relative flex-1">
        <div className="absolute inset-0">
          <PlacesMap
            places={mapPlaces}
            ariaLabel={t("mapAria")}
            onBoundsChange={setBounds}
            onSelect={(id) => {
              const place = places.find((candidate) => candidate.id === id);
              if (place) void choose(place);
            }}
          />
        </div>

        <section
          aria-label={t("listAria")}
          className="absolute inset-x-0 bottom-0 flex flex-col rounded-t-3xl shadow-[var(--shadow-md)] transition-[height] duration-200"
          style={{
            height: SHEET_HEIGHT[sheet],
            background: "var(--bg)",
            borderTop: "1px solid var(--border)",
          }}
        >
          <button
            type="button"
            {...bind()}
            aria-expanded={sheet !== "hidden"}
            aria-label={sheet === "full" ? t("collapseList") : t("expandList")}
            className="flex h-11 shrink-0 touch-none items-center justify-center"
          >
            <span className="h-1 w-10 rounded-full" style={{ background: "var(--border)" }} />
          </button>
          <div
            hidden={sheet === "hidden"}
            className="mx-auto flex w-full max-w-xl flex-1 flex-col gap-4 overflow-y-auto px-4 pb-6"
          >
            {error ? (
              <ErrorNotice>{error}</ErrorNotice>
            ) : null}
            {gymLocationCount > 1 ? (
              <button
                type="button"
                onClick={() => void choose(null)}
                className="min-h-12 rounded-2xl px-4 text-left text-sm font-bold"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {t("allLocations", { gym: membership?.organization.name ?? "" })}
              </button>
            ) : null}
            {placesQuery.isPending ? (
              <div className="h-14 animate-pulse rounded-2xl" style={{ background: "var(--panel)" }} />
            ) : places.length === 0 ? (
              <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>
                {t("noPlaces")}
              </p>
            ) : null}
            {bounds === null ? (
              // Until the map reports its frame (or if it cannot load), one plain list.
              places.length > 0 ? <ul className="flex flex-col gap-2">{places.map(row)}</ul> : null
            ) : (
              <>
                {nearby.length > 0 ? (
                  <PlaceSection label={t("inArea")}>{nearby.map(row)}</PlaceSection>
                ) : null}
                {further.length > 0 ? (
                  <PlaceSection label={t("further")}>{further.map(row)}</PlaceSection>
                ) : null}
              </>
            )}
          </div>
        </section>
      </div>
    </main>
    </Layer>
  );
}

function PlaceSection({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {label}
      </h2>
      <ul className="flex flex-col gap-2">{children}</ul>
    </section>
  );
}
