"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { AroundOrigin } from "@/api/around";
import { ClubBar } from "@/components/community/ClubBar";
import { ComposeButton } from "@/components/community/ComposeSheet";
import { ErrorLine, Sheet } from "@/components/community/Sheet";
import { useMyClubs } from "@/components/community/use-community";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { FeedInboxButtons } from "@/components/chat/MessagesButton";
import { useDebounced } from "@/hooks/useDebounced";

import { clearNarrowing, foundTotal, isOneOff, thinResults, withWhen, type OriginChoice } from "./around";
import { AreaPicker, GeoMessage, PlaceOption, useAroundError, useDevicePosition, useNeighbourhoodName } from "./AreaPicker";
import { AroundChipRow } from "./AroundFilters";
import { AroundMapPanel } from "./AroundMapPanel";
import { AroundSections, ThinResultsCard } from "./AroundSections";
import { ScopeToggle } from "./ScopeToggle";
import { needsOrigin, useAround, useAroundArea, useAroundSearch, useNeighbourhoodSearch, useResolvePlace } from "./use-around";

/**
 * Αρχική › Γύρω μου (vision §6.2, §7.2; board 9): what is near you by kind,
 * under the same header, club bar and scope toggle as «Τα clubs μου». A
 * compact map sits above the sections; the chip row and its sheet filter both.
 */
export function AroundPage() {
  const t = useTranslations("Around");
  const tMember = useTranslations("MemberApp");
  const clubs = useMyClubs();
  const around = useAround();
  const search = useAroundSearch();
  const aroundError = useAroundError();
  const [areaSheet, setAreaSheet] = useState(false);
  const [elsewhere, setElsewhere] = useState(false);
  const data = search.data;
  const askOrigin = !data && needsOrigin(search.error) && !isOneOff(around.origin);
  const thin = data ? thinResults(data) : null;

  return (
    <HubPage
      title={tMember("homeTitle")}
      actions={
        <div className="flex items-center gap-2">
          <FeedInboxButtons />
          <ComposeButton clubs={clubs.data ?? []} />
        </div>
      }
    >
      {clubs.data && clubs.data.length > 0 ? <ClubBar clubs={clubs.data} /> : null}
      <ScopeToggle current="around" />

      {askOrigin ? (
        <StartCard onElsewhere={() => setElsewhere(true)} />
      ) : (
        <>
          <OriginBar
            origin={data?.origin ?? null}
            choice={around.origin}
            onChangeArea={() => setAreaSheet(true)}
            onElsewhere={() => setElsewhere(true)}
            onBack={() => around.setOrigin({ type: "auto" })}
          />
          <AroundChipRow resultCount={data ? foundTotal(data.sections) : 0} />
          {search.isPending || !around.ready ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
          ) : null}
          {search.isError && !data ? (
            <HubCard>
              <ErrorLine message={aroundError(search.error)} />
              <button
                type="button"
                onClick={() => void search.refetch()}
                className="mt-3 min-h-11 rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
              >
                {t("retry")}
              </button>
              {isOneOff(around.origin) ? (
                <button
                  type="button"
                  onClick={() => around.setOrigin({ type: "auto" })}
                  className="ml-2 mt-3 min-h-11 rounded-2xl px-4 text-sm font-bold"
                  style={{ color: "var(--text)", border: "1px solid var(--border)" }}
                >
                  {t("backToArea")}
                </button>
              ) : null}
            </HubCard>
          ) : null}
          {data ? (
            <>
              <p className="sr-only" aria-live="polite">
                {search.isFetching ? t("updating") : t("resultsSummary", { count: foundTotal(data.sections) })}
              </p>
              {search.isError ? <ErrorLine message={aroundError(search.error)} /> : null}
              <AroundMapPanel
                key={[data.origin.latitude, data.origin.longitude, data.filter.radius_km].join(":")}
                origin={data.origin}
                radiusKm={data.filter.radius_km}
              />
              {thin ? (
                <ThinResultsCard
                  thin={thin}
                  onWider={(km) => around.setFilter({ ...around.filter, radius_km: km })}
                  onClear={() => around.setFilter(clearNarrowing(around.filter))}
                />
              ) : null}
              <div style={{ opacity: search.isFetching && search.isPlaceholderData ? 0.6 : 1 }}>
                <AroundSections data={data} />
              </div>
            </>
          ) : null}
        </>
      )}

      {areaSheet ? <AreaSheet onClose={() => setAreaSheet(false)} /> : null}
      {elsewhere ? <ElsewhereSheet onClose={() => setElsewhere(false)} /> : null}
    </HubPage>
  );
}

/** First visit without an area or a box: «Πού να ψάξουμε;». */
function StartCard({ onElsewhere }: { onElsewhere: () => void }) {
  const t = useTranslations("Around");
  const { setOrigin } = useAround();
  return (
    <HubCard highlighted>
      <h2 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("startTitle")}</h2>
      <p className="mb-4 mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{t("startHint")}</p>
      <AreaPicker initial={[]} submitLabel={t("continue")} onSaved={() => setOrigin({ type: "auto" })} onUsePoint={setOrigin} />
      <button type="button" onClick={onElsewhere} className="mt-3 text-sm font-semibold underline" style={{ color: "var(--text)" }}>
        {t("searchElsewhere")}
      </button>
    </HubCard>
  );
}

/** «Από: Κυψέλη · Αλλαγή», or a one-off search with the way back. */
function OriginBar({
  origin,
  choice,
  onChangeArea,
  onElsewhere,
  onBack,
}: {
  origin: AroundOrigin | null;
  choice: OriginChoice;
  onChangeArea: () => void;
  onElsewhere: () => void;
  onBack: () => void;
}) {
  const t = useTranslations("Around");
  const area = useAroundArea();
  const name = useNeighbourhoodName();
  const oneOff = isOneOff(choice);
  const label =
    choice.type === "place"
      ? choice.label
      : choice.type === "point"
        ? t("originPoint")
        : origin?.type === "box"
          ? origin.label ?? t("originBox")
          : origin?.type === "area" && area.data?.[0]
            ? name(area.data[0])
            : origin?.label ?? (origin?.type === "neighbourhoods" ? t("originPlaces") : "");
  const link = "min-h-9 rounded-full px-3 text-xs font-bold";
  const linkStyle = { color: "var(--text)", border: "1px solid var(--border)" };

  return (
    <div className="flex flex-wrap items-center justify-between gap-2">
      <p className="min-w-0 text-sm" style={{ color: "var(--text-soft)" }}>
        {oneOff ? t("searchingFrom", { place: label }) : label ? t("from", { place: label }) : null}
      </p>
      <div className="flex gap-2">
        {oneOff ? (
          <button type="button" onClick={onBack} className={link} style={linkStyle}>{t("backToArea")}</button>
        ) : (
          <button type="button" onClick={onChangeArea} className={link} style={linkStyle}>{t("changeArea")}</button>
        )}
        <button type="button" onClick={onElsewhere} className={link} style={linkStyle}>{t("searchElsewhere")}</button>
      </div>
    </div>
  );
}

/** «Η περιοχή μου», edited from the Γύρω μου header. */
function AreaSheet({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Around");
  const area = useAroundArea();
  const { setOrigin } = useAround();
  return (
    <Sheet labelId="around-area-sheet" title={t("areaTitle")} onClose={onClose}>
      {area.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : (
        <AreaPicker
          initial={area.data ?? []}
          submitLabel={t("save")}
          onSaved={() => {
            setOrigin({ type: "auto" });
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}

/**
 * A one-off search elsewhere («Θεσσαλονίκη, αυτό το ΣΚ»): a gazetteer place,
 * any typed place, or the device's position now. The saved area stays.
 */
function ElsewhereSheet({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Around");
  const name = useNeighbourhoodName();
  const { setOrigin, filter, setFilter } = useAround();
  const [query, setQuery] = useState("");
  const [weekend, setWeekend] = useState(false);
  const results = useNeighbourhoodSearch(useDebounced(query, 250));
  const resolve = useResolvePlace();
  const aroundError = useAroundError();
  const pick = (origin: OriginChoice) => {
    setOrigin(origin);
    if (weekend) setFilter(withWhen(filter, "weekend"));
    onClose();
  };
  const geo = useDevicePosition(pick);
  const trimmed = query.trim();

  return (
    <Sheet labelId="around-elsewhere-sheet" title={t("elsewhereTitle")} onClose={onClose}>
      <form
        className="flex flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (trimmed.length >= 2) pick({ type: "place", query: trimmed, label: trimmed });
        }}
      >
        <label htmlFor="around-elsewhere" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("elsewhereLabel")}
        </label>
        <input
          id="around-elsewhere"
          type="search"
          value={query}
          autoComplete="off"
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("elsewherePlaceholder")}
          className="min-h-11 rounded-2xl px-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <ul aria-live="polite" className="flex flex-col">
          {trimmed.length >= 2
            ? (results.data?.places ?? []).slice(0, 6).map((place) => (
                <li key={place.id}>
                  <button
                    type="button"
                    disabled={resolve.isPending}
                    aria-busy={resolve.isPending && resolve.variables?.id === place.id}
                    onClick={() =>
                      resolve.mutate(place, {
                        onSuccess: (stored) => pick({ type: "place", neighbourhoodId: stored.id, label: name(stored) }),
                      })
                    }
                    className="flex min-h-11 w-full items-center justify-between gap-3 rounded-xl px-2 py-1 text-left text-sm disabled:opacity-60"
                    style={{ color: "var(--text)" }}
                  >
                    <PlaceOption place={place} busy={resolve.isPending && resolve.variables?.id === place.id} />
                  </button>
                </li>
              ))
            : null}
          {trimmed.length >= 2 ? (
            <li>
              <button type="submit" className="min-h-11 w-full rounded-xl px-2 text-left text-sm" style={{ color: "var(--text-soft)" }}>
                {t("searchFor", { query: trimmed })}
              </button>
            </li>
          ) : null}
        </ul>
        <ErrorLine message={aroundError(resolve.error)} />
        <label className="flex min-h-11 items-center gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
          <input type="checkbox" checked={weekend} onChange={(event) => setWeekend(event.target.checked)} className="h-5 w-5" />
          {t("thisWeekend")}
        </label>
        <button
          type="button"
          onClick={geo.locate}
          disabled={geo.state === "locating"}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {geo.state === "locating" ? t("geoLocating") : t("useLocationNow")}
        </button>
        <GeoMessage state={geo.state} />
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("elsewhereHint")}</p>
      </form>
    </Sheet>
  );
}
