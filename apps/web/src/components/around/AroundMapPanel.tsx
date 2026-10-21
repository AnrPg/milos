"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import type { AroundKind, AroundOrigin, AroundPin, AroundViewport } from "@/api/around";

import { MAX_VIEWPORT_KM, initialViewport, viewportDiagonalKm } from "./around";
import type { MapPin } from "./AroundMap";
import { useAroundError } from "./AreaPicker";
import { useAround, useAroundPins } from "./use-around";

const AroundMap = dynamic(() => import("./AroundMap"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse" style={{ background: "var(--panel)" }} />,
});

const sameViewport = (a: AroundViewport, b: AroundViewport) =>
  (["west", "south", "east", "north"] as const).every((side) => Math.abs(a[side] - b[side]) < 1e-4);

/** Where a pin opens: the event, the box's public page, the open club. */
export function pinHref(pin: Pick<AroundPin, "kind" | "id" | "slug">) {
  if (pin.kind === "events") return `/events/${encodeURIComponent(pin.id)}`;
  if (pin.kind === "boxes") return pin.slug ? `/b/${encodeURIComponent(pin.slug)}` : null;
  if (pin.kind === "clubs") return `/clubs/${encodeURIComponent(pin.id)}`;
  return null;
}

/**
 * The compact map above the sections (board 9 Q3 B): pins for the current
 * results, a pin highlights (and scrolls to) its row, a row's «Στον χάρτη»
 * highlights its pin. Panning offers «Ψάξε εδώ» within the 60 km cap. It can
 * grow to full screen and back.
 */
export function AroundMapPanel({ origin, radiusKm }: { origin: AroundOrigin; radiusKm: number }) {
  const t = useTranslations("Around");
  const aroundError = useAroundError();
  const { queryFilter, selectedId, setSelectedId } = useAround();
  const start = useMemo(() => initialViewport(origin.latitude, origin.longitude, radiusKm), [origin.latitude, origin.longitude, radiusKm]);
  const [searched, setSearched] = useState<AroundViewport>(start);
  const [moved, setMoved] = useState<AroundViewport | null>(null);
  const [expanded, setExpanded] = useState(false);
  const [failed, setFailed] = useState(false);
  const [card, setCard] = useState<string | null>(null);
  const pinsQuery = useAroundPins(searched, queryFilter);
  const expandButton = useRef<HTMLButtonElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);
  const wasExpanded = useRef(false);

  const kindLabel = (kind: AroundKind) => t(["pin", kind].join("_"));
  const pins: MapPin[] = useMemo(
    () => (pinsQuery.data?.pins ?? []).map((pin) => ({ ...pin, label: [kindLabel(pin.kind), pin.title ?? ""].filter(Boolean).join(": ") })),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- labels follow the pins
    [pinsQuery.data],
  );
  const cardPin = card ? pins.find((pin) => pin.id === card) : undefined;
  const tooFar = moved ? viewportDiagonalKm(moved) > MAX_VIEWPORT_KM : false;
  const canSearchHere = moved !== null && !sameViewport(moved, searched);

  useEffect(() => {
    if (expanded) closeButton.current?.focus();
    else if (wasExpanded.current) expandButton.current?.focus();
    wasExpanded.current = expanded;
    if (!expanded) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setExpanded(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [expanded]);

  function pick(id: string) {
    setSelectedId(id);
    const row = expanded ? null : document.querySelector<HTMLElement>(`[data-around-id="${CSS.escape(id)}"]`);
    if (row) {
      setCard(null);
      row.scrollIntoView({ block: "nearest", behavior: "smooth" });
    } else {
      setCard(id);
    }
  }

  return (
    <section
      aria-label={t("mapLabel")}
      className={
        expanded
          ? "fixed inset-0 z-[65] flex flex-col"
          : "relative flex h-[33dvh] min-h-52 flex-col overflow-hidden rounded-3xl md:h-[42vh]"
      }
      style={{ background: "var(--panel)", border: expanded ? undefined : "1px solid var(--border)" }}
    >
      <div className="relative min-h-0 flex-1">
        {failed ? (
          <div className="flex h-full flex-col gap-2 overflow-y-auto p-4">
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("mapUnavailable")}</p>
            <ul className="flex flex-wrap gap-2">
              {pins.map((pin) => (
                <li key={pin.id}>
                  <button
                    type="button"
                    aria-label={pin.label}
                    aria-pressed={selectedId === pin.id}
                    data-kind={pin.kind}
                    onClick={() => pick(pin.id)}
                    className="min-h-9 rounded-full px-3 text-xs font-semibold"
                    style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    {pin.title ?? kindLabel(pin.kind)}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        ) : (
          <AroundMap
            pins={pins}
            selectedId={selectedId}
            initialViewport={start}
            ariaLabel={t("mapRegion")}
            expanded={expanded}
            onSelect={pick}
            onMoved={setMoved}
            onFailed={() => setFailed(true)}
          />
        )}

        {canSearchHere ? (
          <div className="pointer-events-none absolute inset-x-0 top-3 flex justify-center">
            <button
              type="button"
              disabled={tooFar}
              onClick={() => {
                if (!moved) return;
                setSearched(moved);
                setMoved(null);
                setCard(null);
              }}
              className="pointer-events-auto min-h-10 rounded-full px-4 text-sm font-bold shadow-lg disabled:opacity-80"
              style={{ background: tooFar ? "var(--panel-raised)" : "var(--primary)", color: tooFar ? "var(--text-soft)" : "var(--primary-contrast)" }}
            >
              {tooFar ? t("zoomInToSearch") : t("searchHere")}
            </button>
          </div>
        ) : null}

        <div className="absolute bottom-3 left-3 flex gap-2">
          {expanded ? (
            <button
              ref={closeButton}
              type="button"
              onClick={() => setExpanded(false)}
              className="min-h-10 rounded-full px-4 text-sm font-bold shadow-lg"
              style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            >
              {t("mapCollapse")}
            </button>
          ) : (
            <button
              ref={expandButton}
              type="button"
              onClick={() => setExpanded(true)}
              className="min-h-10 rounded-full px-4 text-sm font-bold shadow-lg"
              style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            >
              {t("mapExpand")}
            </button>
          )}
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2 text-xs" style={{ color: "var(--dim)" }} aria-live="polite">
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: "var(--primary)" }} />
          {t("legendEvents")}
        </span>
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: "var(--text)" }} />
          {t("legendBoxes")}
        </span>
        {pinsQuery.data ? <span>{t("pinCount", { count: pins.length })}</span> : null}
        {pinsQuery.data?.truncated ? <span>{t("pinsTruncated")}</span> : null}
        {pinsQuery.isError ? <span role="alert">{aroundError(pinsQuery.error)}</span> : null}
      </div>

      {cardPin ? (
        <div
          role="region"
          aria-label={cardPin.label}
          className="absolute inset-x-3 bottom-14 z-10 flex items-center gap-3 rounded-2xl p-3 shadow-2xl"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
        >
          <span className="min-w-0 grow">
            <span className="block text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{kindLabel(cardPin.kind)}</span>
            <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{cardPin.title ?? kindLabel(cardPin.kind)}</span>
          </span>
          {pinHref(cardPin) ? (
            <Link
              href={pinHref(cardPin)!}
              className="flex min-h-10 items-center rounded-full px-4 text-sm font-bold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {t("open")}
            </Link>
          ) : null}
          <button
            type="button"
            onClick={() => setCard(null)}
            aria-label={t("closeCard")}
            className="grid h-10 w-10 place-items-center rounded-full"
            style={{ color: "var(--dim)" }}
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
      ) : null}
    </section>
  );
}
