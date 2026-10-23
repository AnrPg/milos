"use client";

import { useId, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import type { Neighbourhood, PlaceSuggestion } from "@/api/around";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine } from "@/components/community/Sheet";
import { useDebounced } from "@/hooks/useDebounced";
import { useUiTranslations } from "@/i18n/ui";

import { MAX_NEIGHBOURHOODS, pointOrigin, type OriginChoice } from "./around";
import { useNeighbourhoodSearch, useResolvePlace, useSaveAroundArea } from "./use-around";

/** A gazetteer place in the reader's language (Greek names for Greek, English otherwise). */
export function useNeighbourhoodName() {
  const locale = useLocale();
  return (place: Pick<Neighbourhood, "name" | "name_en">) => (locale === "el" ? place.name : place.name_en || place.name);
}

/** What tells same-named places apart («Athens · Georgia, United States»), in the reader's language. */
export function usePlaceContext() {
  const locale = useLocale();
  return (place: Pick<Neighbourhood, "context" | "context_en">) =>
    (locale === "el" ? place.context : place.context_en || place.context) ?? null;
}

/** A search result as one tappable row: name, what tells it apart, and what kind of place it is. */
export function PlaceOption({ place, busy = false }: { place: PlaceSuggestion; busy?: boolean }) {
  const t = useTranslations("Around");
  const name = useNeighbourhoodName();
  const context = usePlaceContext();
  const where = context(place);
  const kind = busy
    ? t("placeAdding")
    : place.kind === "address"
      ? t("placeAddress")
      : place.kind === "city"
        ? t("placeCity")
        : t("placeNeighbourhood");
  return (
    <>
      <span className="flex min-w-0 flex-col">
        <span className="truncate font-semibold">{name(place)}</span>
        {where ? (
          <span className="truncate text-xs font-normal" style={{ color: "var(--text-soft)" }}>{where}</span>
        ) : null}
      </span>
      <span className="shrink-0 text-xs font-normal" style={{ color: "var(--dim)" }}>{kind}</span>
    </>
  );
}

/** OpenStreetMap (ODbL) and GeoNames (CC BY 4.0) ask for credit wherever their places are listed. */
export function PlacesAttribution() {
  const t = useTranslations("Around");
  return <p className="text-[11px]" style={{ color: "var(--dim)" }}>{t("placesAttribution")}</p>;
}

/** Γύρω μου errors in words: offline, an unknown place, the geocoder down, else the shared map. */
export function useAroundError() {
  const t = useTranslations("Around");
  const tUi = useUiTranslations();
  return (error: unknown) => {
    if (!error) return null;
    if (typeof navigator !== "undefined" && !navigator.onLine) return t("errorOffline");
    if (error instanceof ApiError) {
      if (error.payload?.code === "place_not_found") return t("errorPlaceNotFound");
      if (error.payload?.code === "geocoder_unavailable") return t("errorGeocoder");
      if (error.payload?.code === "invalid_place_ref") return t("errorLoad");
      return clientErrorMessage(error, tUi);
    }
    return t("errorLoad");
  };
}

type GeoState = "idle" | "locating" | "denied" | "unavailable";

/** The device's position for one search only: rounded to ~100 m, never saved. */
export function useDevicePosition(onPoint: (origin: OriginChoice) => void) {
  const [state, setState] = useState<GeoState>("idle");
  const locate = () => {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setState("unavailable");
      return;
    }
    setState("locating");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setState("idle");
        onPoint(pointOrigin(position.coords.latitude, position.coords.longitude));
      },
      (error) => setState(error.code === error.PERMISSION_DENIED ? "denied" : "unavailable"),
      { enableHighAccuracy: false, timeout: 10_000, maximumAge: 5 * 60_000 },
    );
  };
  return { state, locate };
}

export function GeoMessage({ state }: { state: GeoState }) {
  const t = useTranslations("Around");
  if (state === "denied") return <ErrorLine message={t("geoDenied")} />;
  if (state === "unavailable") return <ErrorLine message={t("geoUnavailable")} />;
  return null;
}

/**
 * «Πού να ψάξουμε;» / «Η περιοχή μου» (ADR-154 §2): up to 5 neighbourhoods
 * or cities anywhere, or the area around an address (ADR-188); the first is
 * the main one. `onUsePoint` adds «Χρήση τοποθεσίας
 * τώρα» for a search from where the device is, without saving anything.
 */
export function AreaPicker({
  initial,
  submitLabel,
  onSaved,
  onUsePoint,
}: {
  initial: Neighbourhood[];
  submitLabel: string;
  onSaved?: (area: Neighbourhood[]) => void;
  onUsePoint?: (origin: OriginChoice) => void;
}) {
  const t = useTranslations("Around");
  const name = useNeighbourhoodName();
  const context = usePlaceContext();
  const aroundError = useAroundError();
  const inputId = useId();
  const resultsId = useId();
  const [picked, setPicked] = useState<Neighbourhood[]>(initial);
  const [query, setQuery] = useState("");
  const q = useDebounced(query, 250);
  const results = useNeighbourhoodSearch(q);
  const save = useSaveAroundArea();
  const resolve = useResolvePlace();
  const [adding, setAdding] = useState<string | null>(null);
  const geo = useDevicePosition((origin) => onUsePoint?.(origin));
  const full = picked.length >= MAX_NEIGHBOURHOODS;
  const found = (results.data?.places ?? []).filter((place) => !picked.some((entry) => entry.id === place.id));
  const searching = q.trim().length >= 2;

  const add = (place: PlaceSuggestion) => {
    if (full || adding) return;
    setAdding(place.id);
    resolve.mutate(place, {
      onSuccess: (stored) => {
        // An address may resolve to a neighbourhood already picked.
        setPicked((current) => (current.some((entry) => entry.id === stored.id) ? current : [...current, stored]));
        setQuery("");
        document.getElementById(inputId)?.focus();
      },
      onSettled: () => setAdding(null),
    });
  };
  const remove = (id: string) => setPicked((current) => current.filter((entry) => entry.id !== id));
  const makeMain = (id: string) =>
    setPicked((current) => {
      const place = current.find((entry) => entry.id === id);
      return place ? [place, ...current.filter((entry) => entry.id !== id)] : current;
    });

  return (
    <div className="flex flex-col gap-3">
      {picked.length > 0 ? (
        <ul aria-label={t("areaChosen")} className="flex flex-wrap gap-2">
          {picked.map((place, index) => (
            <li
              key={place.id}
              className="flex min-h-10 items-center gap-1 rounded-full py-1 pl-3.5 pr-1 text-sm font-semibold"
              style={{
                background: "color-mix(in srgb, var(--primary) 16%, var(--panel))",
                border: "1px solid var(--primary)",
                color: "var(--text)",
              }}
            >
              <span title={context(place) ?? undefined}>{name(place)}</span>
              {index === 0 ? (
                <span className="text-xs font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
                  · {t("areaMain")}
                </span>
              ) : (
                <button
                  type="button"
                  onClick={() => makeMain(place.id)}
                  aria-label={t("areaMakeMain", { place: name(place) })}
                  className="grid h-8 w-8 place-items-center rounded-full"
                  style={{ color: "var(--dim)" }}
                >
                  <span aria-hidden="true">☆</span>
                </button>
              )}
              <button
                type="button"
                onClick={() => remove(place.id)}
                aria-label={t("areaRemove", { place: name(place) })}
                className="grid h-8 w-8 place-items-center rounded-full"
                style={{ color: "var(--dim)" }}
              >
                <span aria-hidden="true">✕</span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      <label htmlFor={inputId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {full ? t("areaFull") : t("areaSearchLabel")}
      </label>
      <input
        id={inputId}
        type="search"
        value={query}
        disabled={full}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={t("areaSearchPlaceholder")}
        aria-controls={resultsId}
        autoComplete="off"
        className="min-h-11 w-full rounded-2xl px-3 text-sm disabled:opacity-50"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
      <div id={resultsId} aria-live="polite">
        {searching && results.isError ? <ErrorLine message={aroundError(results.error)} /> : null}
        {searching && results.isSuccess && found.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("areaNoMatch")}</p>
        ) : null}
        {searching && results.data?.remote === "unavailable" ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("worldwideUnavailable")}</p>
        ) : null}
        {searching && found.length > 0 ? (
          <ul className="flex flex-col">
            {found.slice(0, 8).map((place) => (
              <li key={place.id}>
                <button
                  type="button"
                  onClick={() => add(place)}
                  disabled={adding !== null}
                  aria-busy={adding === place.id}
                  className="flex min-h-11 w-full items-center justify-between gap-3 rounded-xl px-2 py-1 text-left text-sm disabled:opacity-60"
                  style={{ color: "var(--text)" }}
                >
                  <PlaceOption place={place} busy={adding === place.id} />
                </button>
              </li>
            ))}
          </ul>
        ) : null}
        <ErrorLine message={aroundError(resolve.error)} />
        {searching ? <PlacesAttribution /> : null}
      </div>

      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("areaPrivacy")}</p>

      <div className="flex flex-wrap gap-2">
        {onUsePoint ? (
          <button
            type="button"
            onClick={geo.locate}
            disabled={geo.state === "locating"}
            className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            {geo.state === "locating" ? t("geoLocating") : t("useLocationNow")}
          </button>
        ) : null}
        <button
          type="button"
          disabled={picked.length === 0 || save.isPending}
          onClick={() => save.mutate(picked.map((place) => place.id), { onSuccess: (area) => onSaved?.(area) })}
          className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {submitLabel}
        </button>
      </div>
      <GeoMessage state={geo.state} />
      <ErrorLine message={aroundError(save.error)} />
    </div>
  );
}
