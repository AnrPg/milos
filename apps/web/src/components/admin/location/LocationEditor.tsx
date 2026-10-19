"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useId, useMemo, useState } from "react";

import { ApiError } from "@/api/client";
import {
  isMapLink,
  listAdminLocations,
  resolveMapLink,
  reverseGeocode,
  searchAddresses,
  updateLocation,
  type FacilityLocation,
  type GeocodePlace,
  type OpeningHoursSpan,
} from "@/api/facility";
import { OpeningHoursEditor } from "@/components/admin/location/OpeningHoursEditor";
import type { Pin } from "@/components/admin/location/LocationPinMap";
import { useSession } from "@/components/session-provider";
import { useDebounced } from "@/hooks/useDebounced";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

const LocationPinMap = dynamic(() => import("@/components/admin/location/LocationPinMap"), { ssr: false });

type Form = {
  name: string;
  address: string;
  neighbourhood: string;
  city: string | null;
  country_code: string | null;
  pin: Pin | null;
  opening_hours: OpeningHoursSpan[];
};

const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

function toForm(location: FacilityLocation): Form {
  return {
    name: location.name,
    address: location.address ?? "",
    neighbourhood: location.neighbourhood ?? "",
    city: location.city ?? null,
    country_code: location.country_code ?? null,
    pin:
      location.latitude != null && location.longitude != null
        ? { latitude: location.latitude, longitude: location.longitude }
        : null,
    opening_hours: location.opening_hours ?? [],
  };
}

/**
 * One location on its own page (plan §5a, board 3): name, address with
 * search, neighbourhood from the pin, a full-width map, then opening hours.
 */
export function LocationEditor({ locationId }: { locationId: string }) {
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const query = useQuery({
    queryKey: ["admin", "locations"],
    queryFn: () => listAdminLocations(token!),
    enabled: Boolean(token),
  });
  const location = query.data?.find((candidate) => candidate.id === locationId);
  const i18n = useUiTranslations();

  if (!token || query.isLoading) {
    return <p className="p-6 text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>;
  }
  if (!location) return <NotFound />;
  return <EditorForm key={location.id} token={token} location={location} />;
}

function NotFound() {
  const t = useTranslations("AdminLocation");
  const organizationSlug = useOrganizationSlug();
  return (
    <main className="mx-auto max-w-3xl px-6 py-10">
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("notFound")}</p>
      <Link href={adminHref("/admin/settings", organizationSlug)} className="mt-4 inline-block text-sm font-semibold" style={{ color: "var(--primary)" }}>
        {t("backToSettings")}
      </Link>
    </main>
  );
}

function EditorForm({ token, location }: { token: string; location: FacilityLocation }) {
  const t = useTranslations("AdminLocation");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const organizationSlug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const saved = useMemo(() => toForm(location), [location]);
  const [form, setForm] = useState<Form>(saved);
  // The neighbourhood follows the pin until the admin types their own.
  const [neighbourhoodTyped, setNeighbourhoodTyped] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const listId = useId();

  const dirty = JSON.stringify(form) !== JSON.stringify(saved);
  const term = useDebounced(form.address.trim(), 300);
  const suggestions = useQuery({
    queryKey: ["admin", "geocode", term, locale],
    queryFn: () => searchAddresses(token, term, { language: locale, near: form.pin }),
    enabled: searchOpen && term.length >= 3 && !isMapLink(term),
    staleTime: 5 * 60_000,
    retry: false,
  });

  const fillFromPlace = (place: GeocodePlace, { keepAddress }: { keepAddress: boolean }) =>
    setForm((current) => ({
      ...current,
      address: keepAddress && current.address.trim() ? current.address : place.address ?? current.address,
      neighbourhood: neighbourhoodTyped ? current.neighbourhood : place.neighbourhood ?? current.neighbourhood,
      city: place.city ?? current.city,
      country_code: place.country_code ?? current.country_code,
    }));

  const movePin = async (pin: Pin) => {
    setForm((current) => ({ ...current, pin }));
    try {
      const place = await reverseGeocode(token, pin.latitude, pin.longitude, locale);
      if (place) fillFromPlace(place, { keepAddress: true });
    } catch {
      // The pin stays where it was dropped; the neighbourhood can be typed.
    }
  };

  // A pasted Google Maps link places the pin instead of searching (board 3, Q2 C).
  const [linkState, setLinkState] = useState<"idle" | "resolving" | "failed">("idle");
  const placeFromLink = async (url: string) => {
    setLinkState("resolving");
    setSearchOpen(false);
    try {
      const place = await resolveMapLink(token, url, locale);
      setLinkState("idle");
      setForm((current) => ({ ...current, address: "" }));
      pick(place);
    } catch {
      setLinkState("failed");
    }
  };

  const pick = (place: GeocodePlace) => {
    setSearchOpen(false);
    setForm((current) => ({ ...current, pin: { latitude: place.latitude, longitude: place.longitude } }));
    fillFromPlace(place, { keepAddress: false });
  };

  const save = useMutation({
    mutationFn: () =>
      updateLocation(token, location.id, {
        name: form.name.trim(),
        address: form.address.trim() || null,
        neighbourhood: form.neighbourhood.trim() || null,
        city: form.city,
        country_code: form.country_code,
        latitude: form.pin?.latitude ?? null,
        longitude: form.pin?.longitude ?? null,
        opening_hours: form.opening_hours,
      }),
    onSuccess: async (updated) => {
      setForm(toForm(updated));
      setError(null);
      setNotice(t("saved"));
      await queryClient.invalidateQueries({ queryKey: ["admin", "locations"] });
    },
    onError: (cause) => {
      setNotice(null);
      const errors = cause instanceof ApiError && cause.status === 422 ? cause.payload.errors : null;
      setError(
        errors?.name
          ? i18n("admLocationNameTaken")
          : errors?.opening_hours
            ? t("hoursInvalid")
            : localizeError(cause, i18n),
      );
    },
  });

  const searchFailed = suggestions.isError;
  const places = suggestions.data ?? [];
  const showList = searchOpen && !isMapLink(term) && term.length >= 3 && (places.length > 0 || searchFailed || suggestions.isSuccess);

  return (
    <main className="min-h-screen px-6 py-10 md:px-10" style={{ background: "var(--bg)" }}>
      <form
        className="mx-auto flex max-w-3xl flex-col gap-6 pb-28"
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate();
        }}
      >
        <header className="flex items-center gap-3">
          <Link
            href={adminHref("/admin/settings", organizationSlug)}
            aria-label={t("backToSettings")}
            className="grid h-10 w-10 place-items-center rounded-full text-xl"
            style={{ color: "var(--text)", border: "1px solid var(--border)" }}
          >
            <span aria-hidden="true">‹</span>
          </Link>
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>
            {form.name.trim() || location.name}
          </h1>
        </header>

        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{i18n("admLocationName")}</span>
          <input
            value={form.name}
            maxLength={80}
            required
            minLength={2}
            onChange={(event) => setForm({ ...form, name: event.target.value })}
            className="rounded-2xl px-4 py-3 text-sm outline-none"
            style={fieldStyle}
          />
        </label>

        <div className="relative flex flex-col gap-1.5">
          <label htmlFor={`${listId}-address`} className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
            {t("address")}
          </label>
          <input
            id={`${listId}-address`}
            role="combobox"
            aria-expanded={showList}
            aria-controls={`${listId}-list`}
            aria-autocomplete="list"
            autoComplete="off"
            value={form.address}
            maxLength={300}
            placeholder={t("addressPlaceholder")}
            onFocus={() => setSearchOpen(true)}
            onBlur={() => window.setTimeout(() => setSearchOpen(false), 150)}
            onKeyDown={(event) => {
              if (event.key === "Escape") setSearchOpen(false);
            }}
            onChange={(event) => {
              const value = event.target.value;
              setLinkState("idle");
              setForm({ ...form, address: value });
              if (isMapLink(value)) void placeFromLink(value);
              else setSearchOpen(true);
            }}
            className="rounded-2xl px-4 py-3 text-sm outline-none"
            style={fieldStyle}
          />
          {linkState !== "idle" ? (
            <p role="status" className="text-xs" style={{ color: linkState === "failed" ? "var(--danger)" : "var(--dim)" }}>
              {linkState === "failed" ? t("linkFailed") : t("linkResolving")}
            </p>
          ) : (
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("addressHint")}</span>
          )}
          {showList ? (
            <ul
              id={`${listId}-list`}
              role="listbox"
              className="absolute inset-x-0 top-[4.9rem] z-20 overflow-hidden rounded-2xl"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", boxShadow: "0 12px 30px rgba(0,0,0,.3)" }}
            >
              {searchFailed ? (
                <li className="px-4 py-3 text-sm" style={{ color: "var(--muted)" }}>{t("searchUnavailable")}</li>
              ) : places.length === 0 ? (
                <li className="px-4 py-3 text-sm" style={{ color: "var(--muted)" }}>{t("noMatches")}</li>
              ) : (
                places.map((place) => (
                  <li key={`${place.latitude},${place.longitude}`} role="option" aria-selected="false">
                    <button
                      type="button"
                      onMouseDown={(event) => event.preventDefault()}
                      onClick={() => pick(place)}
                      className="w-full px-4 py-3 text-left text-sm"
                      style={{ color: "var(--text)", borderBottom: "1px solid var(--border)" }}
                    >
                      {place.label}
                    </button>
                  </li>
                ))
              )}
            </ul>
          ) : null}
        </div>

        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("neighbourhood")}</span>
          <input
            value={form.neighbourhood}
            maxLength={80}
            onChange={(event) => {
              setNeighbourhoodTyped(true);
              setForm({ ...form, neighbourhood: event.target.value });
            }}
            className="rounded-2xl px-4 py-3 text-sm outline-none"
            style={fieldStyle}
          />
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("neighbourhoodHint")}</span>
        </label>

        <section className="flex flex-col gap-2" aria-labelledby={`${listId}-map`}>
          <div className="flex items-baseline justify-between gap-3">
            <h2 id={`${listId}-map`} className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
              {t("map")}
            </h2>
            {form.pin ? (
              <button
                type="button"
                onClick={() => setForm({ ...form, pin: null })}
                className="text-xs font-semibold"
                style={{ color: "var(--muted)" }}
              >
                {t("removePin")}
              </button>
            ) : null}
          </div>
          <div className="h-[22rem] overflow-hidden rounded-3xl md:h-[28rem]" style={{ border: "1px solid var(--border)" }}>
            <LocationPinMap
              pin={form.pin}
              label={form.name.trim() || location.name}
              ariaLabel={t("mapAria")}
              onMove={(pin) => void movePin(pin)}
            />
          </div>
          <p className="text-xs" style={{ color: form.pin ? "var(--dim)" : "var(--warning)" }}>
            {form.pin ? t("pinHint") : t("noPin")}
          </p>
        </section>

        <section className="flex flex-col gap-2" aria-labelledby={`${listId}-hours`}>
          <h2 id={`${listId}-hours`} className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
            {t("hours")}
          </h2>
          <OpeningHoursEditor value={form.opening_hours} onChange={(opening_hours) => setForm({ ...form, opening_hours })} />
        </section>

        <div
          className="fixed inset-x-0 bottom-0 z-[60] px-6 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3"
          style={{ background: "color-mix(in srgb, var(--bg) 92%, transparent)", borderTop: "1px solid var(--border)" }}
        >
          <div className="mx-auto flex max-w-3xl items-center justify-end gap-3">
            <p role="status" className="mr-auto text-sm" style={{ color: error ? "var(--danger)" : "var(--muted)" }}>
              {error ?? (dirty ? t("unsaved") : notice)}
            </p>
            <button
              type="button"
              disabled={!dirty || save.isPending}
              onClick={() => {
                setForm(saved);
                setNeighbourhoodTyped(false);
                setError(null);
              }}
              className="rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-40"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
            >
              {i18n("cancel77dfd21")}
            </button>
            <button
              type="submit"
              disabled={!dirty || save.isPending || form.name.trim().length < 2}
              className="rounded-full px-6 py-2.5 text-sm font-bold disabled:opacity-40"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {i18n("saveefc007a")}
            </button>
          </div>
        </div>
      </form>
    </main>
  );
}
