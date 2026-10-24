"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type {
  AroundBoxItem,
  AroundClubItem,
  AroundEventItem,
  AroundKind,
  AroundPostItem,
  AroundSearchResponse,
} from "@/api/around";
import { clubInitials } from "@/components/community/community";
import { OpenClubRow } from "@/components/community/FindPage";
import { PostCard } from "@/components/community/PostCard";
import { ErrorLine } from "@/components/community/Sheet";
import { EventPostCard } from "@/components/events/EventPostCard";
import { HubCard } from "@/components/member-app/HubParts";

import { KIND_ORDER, onlyKind, type ThinResults } from "./around";
import { useAroundError } from "./AreaPicker";
import { useKm } from "./AroundFilters";
import { useAround, useAroundKind } from "./use-around";

/** The id a map pin carries for an item: the gym's id for a box. */
export function itemPinId(kind: AroundKind, item: AroundEventItem | AroundBoxItem | AroundClubItem | AroundPostItem) {
  if (kind === "events") return (item as AroundEventItem).event.id;
  if (kind === "boxes") return (item as AroundBoxItem).box.organization_id;
  if (kind === "clubs") return (item as AroundClubItem).club.id;
  return (item as AroundPostItem).post.id;
}

/** Whether an item can show on the map (events need a point; clubs and people's posts have none of their own). */
function hasPoint(kind: AroundKind, item: AroundEventItem | AroundBoxItem | AroundClubItem | AroundPostItem) {
  if (kind === "boxes") return true;
  if (kind === "events") {
    const place = (item as AroundEventItem).event.place;
    return place.latitude !== null && place.longitude !== null;
  }
  return false;
}

/**
 * One result row with its distance; the list is the primary path, so a row
 * names its place and «Στον χάρτη» highlights its pin above.
 */
function RowShell({
  id,
  mappable,
  distance,
  children,
}: {
  id: string;
  mappable: boolean;
  distance: number | null;
  children: ReactNode;
}) {
  const t = useTranslations("Around");
  const km = useKm();
  const { selectedId, setSelectedId } = useAround();
  const selected = selectedId === id;
  return (
    <li
      data-around-id={id}
      className="flex flex-col gap-1.5 rounded-2xl p-1 transition-shadow"
      style={{ boxShadow: selected ? "0 0 0 2px var(--primary)" : undefined, scrollMarginTop: "5rem" }}
    >
      {children}
      {distance !== null || mappable ? (
        <div className="flex items-center justify-between gap-2 px-2 text-xs" style={{ color: "var(--dim)" }}>
          <span>{distance !== null ? t("distanceAway", { distance: km(distance) }) : null}</span>
          {mappable ? (
            <button
              type="button"
              aria-pressed={selected}
              onClick={() => setSelectedId(selected ? null : id)}
              className="min-h-9 rounded-full px-3 font-semibold"
              style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
            >
              {t("showOnMap")}
            </button>
          ) : null}
        </div>
      ) : null}
    </li>
  );
}

export function AroundEventRow({ item }: { item: AroundEventItem }) {
  return (
    <RowShell id={item.event.id} mappable={hasPoint("events", item)} distance={item.distance_km}>
      <EventPostCard event={item.event} />
    </RowShell>
  );
}

/** A gym near you: links to its public page; «Δοκιμαστικό» when it takes trials. */
export function AroundBoxRow({ item }: { item: AroundBoxItem }) {
  const t = useTranslations("Around");
  const tags = useTranslations("BoxTags");
  const { box } = item;
  const line = [box.neighbourhood ?? box.city, ...box.disciplines.slice(0, 2).map((key) => tags(["discipline", key].join(".")))]
    .filter(Boolean)
    .join(" · ");
  return (
    <RowShell id={box.organization_id} mappable distance={item.distance_km}>
      <Link
        href={`/b/${encodeURIComponent(box.slug)}`}
        className="flex min-h-14 items-center gap-3 rounded-2xl p-3"
        style={{ background: "var(--panel-raised)" }}
      >
        {box.logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
          <img src={box.logo_url} alt="" className="h-11 w-11 shrink-0 rounded-full object-cover" />
        ) : (
          <span
            aria-hidden="true"
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
            style={{ background: "var(--panel)", color: "var(--text)" }}
          >
            {clubInitials(box.name)}
          </span>
        )}
        <span className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{box.name}</span>
          {line ? <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>{line}</span> : null}
        </span>
        {box.takes_trials ? (
          <span
            className="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold"
            style={{ background: "color-mix(in srgb, var(--primary) 16%, transparent)", color: "var(--primary-strong, var(--primary))" }}
          >
            {t("trialBadge")}
          </span>
        ) : null}
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </Link>
    </RowShell>
  );
}

export function AroundClubRow({ item }: { item: AroundClubItem }) {
  const km = useKm();
  return (
    <RowShell id={item.club.id} mappable={false} distance={null}>
      <ul>
        <OpenClubRow club={item.club} detail={item.distance_km !== null ? km(item.distance_km) : undefined} />
      </ul>
    </RowShell>
  );
}

export function AroundPostRow({ item }: { item: AroundPostItem }) {
  return (
    <RowShell id={item.post.id} mappable={false} distance={item.distance_km}>
      <PostCard post={item.post} />
    </RowShell>
  );
}

type Item = AroundEventItem | AroundBoxItem | AroundClubItem | AroundPostItem;

export function AroundRow({ kind, item }: { kind: AroundKind; item: Item }) {
  if (kind === "events") return <AroundEventRow item={item as AroundEventItem} />;
  if (kind === "boxes") return <AroundBoxRow item={item as AroundBoxItem} />;
  if (kind === "clubs") return <AroundClubRow item={item as AroundClubItem} />;
  return <AroundPostRow item={item as AroundPostItem} />;
}

/**
 * The sections (board 9): Events (soonest), Box κοντά σου (trial-takers
 * first; one quiet line for people who already have a gym), Ανοιχτά clubs
 * and, when asked for, Αναρτήσεις. A section with nothing in it is hidden
 * (vision §4.2; the «Τίποτα έως…» card speaks for an empty search). «Δες
 * όλα» narrows «what» to that kind in place, and Γύρω μου then lists it in
 * full (`AroundKindList`).
 */
export function AroundSections({ data }: { data: AroundSearchResponse }) {
  const t = useTranslations("Around");
  const { filter, setFilter } = useAround();

  function seeAll(kind: AroundKind) {
    setFilter(onlyKind(filter, kind));
    requestAnimationFrame(() => document.getElementById(AROUND_RESULTS_ID)?.scrollIntoView({ block: "start" }));
  }

  return (
    <div className="flex flex-col gap-4">
      {KIND_ORDER.map((kind) => {
        const section = data.sections[kind];
        const items = (section?.items ?? []) as Item[];
        if (!section || items.length === 0) return null;
        const collapsed = kind === "boxes" && "placement" in section && section.placement === "collapsed";
        const body = (
          <ul className="flex flex-col gap-2">
            {items.map((item) => (
              <AroundRow key={itemPinId(kind, item)} kind={kind} item={item} />
            ))}
          </ul>
        );
        const more =
          section.total > items.length ? (
            <button
              type="button"
              onClick={() => seeAll(kind)}
              className="mt-2 flex min-h-11 items-center text-sm font-bold"
              style={{ color: "var(--primary-strong, var(--primary))" }}
            >
              {t("seeAll", { count: section.total })}
            </button>
          ) : null;

        if (collapsed) return <CollapsedBoxes key={kind} total={section.total} body={body} more={more} />;
        return (
          <section key={kind} aria-labelledby={["around-section", kind].join("-")}>
            <HubCard highlighted={kind === "boxes"}>
              <h2
                id={["around-section", kind].join("-")}
                className="mb-2 text-xs font-bold uppercase tracking-[0.18em]"
                style={{ color: "var(--dim)" }}
              >
                {t(["section", kind].join("_"))}
              </h2>
              {body}
              {more}
            </HubCard>
          </section>
        );
      })}
    </div>
  );
}

/** Where the results start, so «Δες όλα» can bring the full list into view. */
export const AROUND_RESULTS_ID = "around-results";

/**
 * One kind near you in full, cursor-paged: what Γύρω μου shows when «what»
 * is a single kind (was `/around/<kind>`). Nothing found shows nothing here;
 * the «Τίποτα έως…» card above offers wider radii.
 */
export function AroundKindList({ kind }: { kind: AroundKind }) {
  const t = useTranslations("Around");
  const aroundError = useAroundError();
  const { ready, queryFilter, origin } = useAround();
  const list = useAroundKind(kind, { filter: queryFilter, origin, enabled: ready });
  const items = (list.data?.pages ?? []).flatMap((page) => page.items as Item[]);

  if (list.isPending) return null;
  if (list.isError && items.length === 0) {
    return (
      <HubCard>
        <ErrorLine message={aroundError(list.error)} />
        <button
          type="button"
          onClick={() => void list.refetch()}
          className="mt-3 min-h-11 rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("retry")}
        </button>
      </HubCard>
    );
  }
  if (items.length === 0) return null;

  return (
    <section aria-labelledby="around-kind-list" className="flex flex-col gap-2">
      <h2 id="around-kind-list" className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {t(["section", kind].join("_"))}
      </h2>
      <ul className="flex flex-col gap-2">
        {items.map((item) => (
          <AroundRow key={itemPinId(kind, item)} kind={kind} item={item} />
        ))}
      </ul>
      {list.hasNextPage ? (
        <button
          type="button"
          onClick={() => void list.fetchNextPage()}
          disabled={list.isFetchingNextPage}
          className="min-h-11 rounded-2xl text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {list.isFetchingNextPage ? t("loadingMore") : t("loadMore")}
        </button>
      ) : null}
      {list.isFetchNextPageError ? <ErrorLine message={aroundError(list.error)} /> : null}
    </section>
  );
}

/** ADR-154 §7: someone with a gym sees other boxes as one quiet line. */
function CollapsedBoxes({ total, body, more }: { total: number; body: ReactNode; more: ReactNode }) {
  const t = useTranslations("Around");
  const [open, setOpen] = useState(false);
  return (
    <section aria-label={t("section_boxes")}>
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="flex min-h-11 w-full items-center justify-between rounded-2xl px-4 text-sm font-semibold"
        style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
      >
        {t("otherBoxes", { count: total })}
        <span aria-hidden="true">{open ? "▴" : "▾"}</span>
      </button>
      {open ? (
        <div className="mt-2 px-1">
          {body}
          {more}
        </div>
      ) : null}
    </section>
  );
}

/** «Τίποτα έως 3 km» (ADR-154 §8): wider radii with their counts, and «Καθάρισε φίλτρα». */
export function ThinResultsCard({ thin, onWider, onClear }: { thin: ThinResults; onWider: (km: number) => void; onClear: () => void }) {
  const t = useTranslations("Around");
  const km = useKm();
  return (
    <HubCard highlighted>
      <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>
        {thin.found === 0 ? t("thinNone", { distance: km(thin.radiusKm) }) : t("thinFew", { count: thin.found, distance: km(thin.radiusKm) })}
      </h2>
      <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
        {thin.wider.length > 0 ? t("thinWiderHint") : thin.canClear ? t("thinClearHint") : t("thinNothingHint")}
      </p>
      {thin.wider.length > 0 || thin.canClear ? (
        <div className="mt-3 flex flex-wrap gap-2">
          {thin.wider.map((rung) => (
            <button
              key={rung.radiusKm}
              type="button"
              onClick={() => onWider(rung.radiusKm)}
              className="min-h-11 rounded-2xl px-4 text-sm font-bold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {t("widerButton", { distance: km(rung.radiusKm), count: rung.total })}
            </button>
          ))}
          {thin.canClear ? (
            <button
              type="button"
              onClick={onClear}
              className="min-h-11 rounded-2xl px-4 text-sm font-bold"
              style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            >
              {t("clearFilters")}
            </button>
          ) : null}
        </div>
      ) : null}
    </HubCard>
  );
}
