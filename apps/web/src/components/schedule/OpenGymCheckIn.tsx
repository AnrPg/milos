"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useLocale } from "next-intl";

import { checkInOpenGym, listMemberLocations, type MemberCheckIn, type MemberLocation } from "@/api/member-facility";
import type { EffectiveEntitlement } from "@/api/my-finance";
import { includesOpenGym, localizeMemberBookingError } from "@/components/schedule/member-booking";
import { useUiTranslations } from "@/i18n/ui";
import { Select } from "@/components/ui/Select";
import { SPARK_GO_STYLE } from "@/lib/spark";

/**
 * Open-gym self check-in (ADR-097). Renders nothing unless the member's
 * package includes open gym; the location picker appears only with several
 * active locations. Box › Πρόγραμμα shows it under the classes, and Box in
 * the next booking's place when there is none (vision §6.2).
 */
export function OpenGymCheckIn({
  accessToken,
  entitlement,
  extra,
}: {
  accessToken: string;
  entitlement: EffectiveEntitlement | null | undefined;
  /** Another way in next to «Check-in», such as Box's «QR check-in». */
  extra?: ReactNode;
}) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const enabled = includesOpenGym(entitlement);
  const [locations, setLocations] = useState<MemberLocation[]>([]);
  const [locationId, setLocationId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [checkIn, setCheckIn] = useState<MemberCheckIn | null>(null);

  useEffect(() => {
    if (!enabled || !accessToken) return;
    let cancelled = false;

    void listMemberLocations(accessToken)
      .then((nextLocations) => {
        if (cancelled) return;
        setLocations(nextLocations);
        setLocationId((current) => current || nextLocations[0]?.id || "");
      })
      .catch(() => {
        if (!cancelled) setLocations([]);
      });

    return () => {
      cancelled = true;
    };
  }, [accessToken, enabled]);

  if (!enabled) return null;

  async function handleCheckIn() {
    setBusy(true);
    setError(null);
    try {
      setCheckIn(await checkInOpenGym(accessToken, locationId || null));
    } catch (err) {
      setError(localizeMemberBookingError(err, i18n, locale, "check_in"));
    } finally {
      setBusy(false);
    }
  }

  const checkedInTime = checkIn
    ? new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" }).format(new Date(checkIn.checked_in_at))
    : null;

  return (
    <section
      className="flex flex-wrap items-center justify-between gap-3 rounded-[1.6rem] px-5 py-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="min-w-0">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("mbOpenGymTitle")}</p>
        {checkIn ? (
          <p className="mt-0.5 text-xs" style={{ color: "var(--success)" }}>
            {checkIn.already_checked_in
              ? i18n("mbAlreadyCheckedIn", { time: checkedInTime ?? "" })
              : checkIn.location_name
                ? i18n("mbCheckedInAt", { location: checkIn.location_name })
                : i18n("mbCheckedIn")}
          </p>
        ) : (
          <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>{i18n("mbOpenGymHint")}</p>
        )}
        {error ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{error}</p> : null}
      </div>

      {checkIn ? null : (
        <div className="flex flex-wrap items-center gap-2">
          {locations.length > 1 ? (
            <Select
              aria-label={i18n("mbCheckInLocation")}
              className="rounded-full px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              onValueChange={(value) => setLocationId(value)}
              value={locationId}
            >
              {locations.map((location) => (
                <option key={location.id} value={location.id}>{location.name}</option>
              ))}
            </Select>
          ) : null}
          <button
            className="min-h-11 rounded-full px-5 text-sm font-semibold disabled:opacity-50"
            style={SPARK_GO_STYLE}
            disabled={busy}
            onClick={() => void handleCheckIn()}
            type="button"
          >
            {i18n("mbCheckIn")}
          </button>
          {extra}
        </div>
      )}
    </section>
  );
}
