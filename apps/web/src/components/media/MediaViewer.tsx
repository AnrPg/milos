"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslations } from "next-intl";

import type { PostMedia } from "@/api/media";
import { ReportButton } from "@/components/community/ReportButton";
import { InlineVideo } from "@/components/media/PostMediaView";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { buildSrcSet, clampIndex, indexFromScroll, keyIndex } from "@/lib/post-media";

const MAX_SCALE = 4;
const DOUBLE_TAP_SCALE = 2.5;

type Zoom = { scale: number; x: number; y: number };
const NO_ZOOM: Zoom = { scale: 1, x: 0, y: 0 };

/**
 * The full-screen viewer of a post's media (ADR-157): swipe (or the arrow
 * keys) between items, pinch or double-tap to zoom, the caption and alt text
 * under the photo, a subtle report flag in the corner. Escape closes it and
 * focus goes back to the photo that opened it.
 */
export function MediaViewer({
  media,
  startIndex,
  caption,
  author,
  onClose,
  onReport,
}: {
  media: PostMedia[];
  startIndex: number;
  caption?: string | null;
  author: string;
  onClose: () => void;
  onReport?: () => void;
}) {
  const t = useTranslations("Media");
  const tCommunity = useTranslations("Community");
  const dialog = useModalFocusTrap<HTMLDivElement>(onClose);
  const track = useRef<HTMLDivElement>(null);
  const frame = useRef(0);
  const count = media.length;
  const [index, setIndex] = useState(() => clampIndex(startIndex, count));
  const [zoomed, setZoomed] = useState(false);
  const current = media[index];

  const go = useCallback(
    (target: number) => {
      const element = track.current;
      if (!element) return;
      const next = clampIndex(target, count);
      const rtl = getComputedStyle(element).direction === "rtl";
      const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
      element.scrollTo({ left: next * element.clientWidth * (rtl ? -1 : 1), behavior: reduce ? "auto" : "smooth" });
      setIndex(next);
      setZoomed(false);
    },
    [count],
  );

  // Open on the tapped item without an animation.
  useEffect(() => {
    const element = track.current;
    if (!element) return;
    const rtl = getComputedStyle(element).direction === "rtl";
    element.scrollTo({ left: clampIndex(startIndex, count) * element.clientWidth * (rtl ? -1 : 1), behavior: "auto" });
  }, [startIndex, count]);

  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  function onScroll() {
    cancelAnimationFrame(frame.current);
    frame.current = requestAnimationFrame(() => {
      const element = track.current;
      if (element) setIndex(indexFromScroll(element.scrollLeft, element.clientWidth, count));
    });
  }

  function onKeyDown(event: React.KeyboardEvent) {
    if (zoomed) return;
    const rtl = track.current ? getComputedStyle(track.current).direction === "rtl" : false;
    const next = keyIndex(event.key, index, count, rtl);
    if (next === null || (event.target as HTMLElement).tagName === "VIDEO") return;
    event.preventDefault();
    go(next);
  }

  const label = (item: PostMedia, position: number) =>
    item.alt_text || (item.kind === "video" ? t("videoBy", { name: author }) : t("photoNBy", { index: position + 1, count, name: author }));

  return createPortal(
    <div
      ref={dialog}
      role="dialog"
      aria-modal="true"
      aria-label={t("viewer")}
      tabIndex={-1}
      onKeyDown={onKeyDown}
      className="fixed inset-0 z-[80] flex flex-col"
      style={{ background: "var(--media)", color: "var(--on-media)" }}
      data-testid="media-viewer"
    >
      <div className="flex items-center gap-2 px-2 pt-[max(0.5rem,env(safe-area-inset-top))]">
        <button
          type="button"
          onClick={onClose}
          aria-label={t("close")}
          className="flex h-11 w-11 items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2"
          style={{ outlineColor: "var(--on-media)" }}
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" aria-hidden="true">
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </button>
        <p className="grow text-center text-sm font-semibold tabular-nums" aria-live="polite">
          {count > 1 ? t("counter", { current: index + 1, count }) : null}
        </p>
        {onReport ? <ReportButton label={tCommunity("report")} onClick={onReport} tone="overlay" /> : <span className="w-11" />}
      </div>

      <div className="relative min-h-0 grow">
        <div
          ref={track}
          onScroll={onScroll}
          className="flex h-full snap-x snap-mandatory [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          style={{ overflowX: zoomed ? "hidden" : "auto" }}
        >
          {media.map((item, position) => (
            <div
              key={item.id}
              role="group"
              aria-roledescription={t("roleSlide")}
              aria-label={t("slideN", { index: position + 1, count })}
              aria-hidden={position !== index ? true : undefined}
              className="relative flex h-full w-full shrink-0 snap-start snap-always items-center justify-center"
            >
              {item.kind === "video" ? (
                <div className="h-full w-full">
                  {position === index ? <InlineVideo item={item} label={label(item, position)} /> : null}
                </div>
              ) : (
                <ZoomableImage
                  item={item}
                  label={label(item, position)}
                  active={position === index}
                  onZoomChange={position === index ? setZoomed : undefined}
                />
              )}
            </div>
          ))}
        </div>
        {count > 1 ? (
          <>
            {index > 0 ? (
              <ViewerArrow direction="previous" label={t("previous")} onClick={() => go(index - 1)} />
            ) : null}
            {index < count - 1 ? <ViewerArrow direction="next" label={t("next")} onClick={() => go(index + 1)} /> : null}
          </>
        ) : null}
      </div>

      {caption || current?.alt_text ? (
        <div className="max-h-[30vh] overflow-y-auto px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3 text-sm" style={{ background: "linear-gradient(transparent, var(--scrim-strong) 30%)" }}>
          {caption ? <p className="line-clamp-4 whitespace-pre-wrap">{caption}</p> : null}
          {current?.alt_text ? (
            <p className="mt-1 text-xs" style={{ color: "var(--on-media-soft)" }}>
              <span className="font-bold">{t("altText")}:</span> {current.alt_text}
            </p>
          ) : null}
        </div>
      ) : null}
    </div>,
    document.body,
  );
}

function ViewerArrow({ direction, label, onClick }: { direction: "previous" | "next"; label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className={[
        "absolute top-1/2 hidden h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full focus-visible:outline-2 [@media(hover:hover)_and_(pointer:fine)]:flex",
        direction === "previous" ? "start-3" : "end-3",
      ].join(" ")}
      style={{ background: "var(--media-control-inverse)", color: "var(--on-media)", outlineColor: "var(--on-media)" }}
    >
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" aria-hidden="true" className="rtl:-scale-x-100">
        <path d={direction === "previous" ? "M15 6l-6 6 6 6" : "M9 6l6 6-6 6"} />
      </svg>
    </button>
  );
}

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

/** A photo that pinches, double-taps and (with ctrl + wheel or +/−) zooms; panned with one finger while zoomed. */
function ZoomableImage({
  item,
  label,
  active,
  onZoomChange,
}: {
  item: PostMedia;
  label: string;
  active: boolean;
  onZoomChange?: (zoomed: boolean) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<{ distance: number; scale: number } | null>(null);
  const lastTap = useRef(0);
  const [zoom, setZoom] = useState<Zoom>(NO_ZOOM);
  const [gesturing, setGesturing] = useState(false);

  const apply = useCallback(
    (next: Zoom) => {
      const scale = clamp(next.scale, 1, MAX_SCALE);
      const element = box.current;
      const maxX = element ? (element.clientWidth * (scale - 1)) / 2 : 0;
      const maxY = element ? (element.clientHeight * (scale - 1)) / 2 : 0;
      const value = scale === 1 ? NO_ZOOM : { scale, x: clamp(next.x, -maxX, maxX), y: clamp(next.y, -maxY, maxY) };
      setZoom(value);
      onZoomChange?.(value.scale > 1);
    },
    [onZoomChange],
  );

  // Leaving a slide resets its zoom.
  const [wasActive, setWasActive] = useState(active);
  if (wasActive !== active) {
    setWasActive(active);
    if (!active) setZoom(NO_ZOOM);
  }

  function toggleAt(clientX: number, clientY: number) {
    const element = box.current;
    if (!element) return;
    if (zoom.scale > 1) return apply(NO_ZOOM);
    const rect = element.getBoundingClientRect();
    const dx = clientX - (rect.left + rect.width / 2);
    const dy = clientY - (rect.top + rect.height / 2);
    apply({ scale: DOUBLE_TAP_SCALE, x: -dx * (DOUBLE_TAP_SCALE - 1), y: -dy * (DOUBLE_TAP_SCALE - 1) });
  }

  function onPointerDown(event: React.PointerEvent) {
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    setGesturing(true);
    if (pointers.current.size === 2) {
      const [a, b] = [...pointers.current.values()];
      pinch.current = { distance: Math.hypot(a.x - b.x, a.y - b.y), scale: zoom.scale };
    }
    if (zoom.scale > 1 || pointers.current.size === 2) event.currentTarget.setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: React.PointerEvent) {
    const previous = pointers.current.get(event.pointerId);
    if (!previous) return;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.current.size === 2 && pinch.current) {
      const [a, b] = [...pointers.current.values()];
      const distance = Math.hypot(a.x - b.x, a.y - b.y);
      apply({ ...zoom, scale: pinch.current.scale * (distance / Math.max(1, pinch.current.distance)) });
    } else if (pointers.current.size === 1 && zoom.scale > 1) {
      apply({ ...zoom, x: zoom.x + event.clientX - previous.x, y: zoom.y + event.clientY - previous.y });
    }
  }

  function onPointerUp(event: React.PointerEvent) {
    const wasPinch = pointers.current.size === 2;
    pointers.current.delete(event.pointerId);
    if (pointers.current.size < 2) pinch.current = null;
    if (pointers.current.size === 0) setGesturing(false);
    if (wasPinch) return;
    const now = event.timeStamp;
    if (now - lastTap.current < 300) {
      lastTap.current = 0;
      toggleAt(event.clientX, event.clientY);
    } else {
      lastTap.current = now;
    }
  }

  function onWheel(event: React.WheelEvent) {
    if (!event.ctrlKey) return;
    apply({ ...zoom, scale: zoom.scale * (event.deltaY < 0 ? 1.1 : 0.9) });
  }

  function onKeyDown(event: React.KeyboardEvent) {
    if (event.key === "+" || event.key === "=") apply({ ...zoom, scale: zoom.scale * 1.5 });
    else if (event.key === "-") apply({ ...zoom, scale: zoom.scale / 1.5 });
    else if (event.key === "0") apply(NO_ZOOM);
    else return;
    event.preventDefault();
    event.stopPropagation();
  }

  const src = item.full_url ?? item.feed_url ?? item.thumb_url ?? undefined;
  const loading: "eager" | "lazy" = active ? "eager" : "lazy";
  return (
    <div
      ref={box}
      tabIndex={active ? 0 : -1}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onWheel={onWheel}
      onKeyDown={onKeyDown}
      className="relative flex h-full w-full items-center justify-center overflow-hidden focus-visible:outline-2 focus-visible:-outline-offset-4"
      style={{ touchAction: zoom.scale > 1 ? "none" : "pan-x", outlineColor: "var(--on-media)" }}
      data-zoom={zoom.scale.toFixed(2)}
      data-testid="viewer-photo"
    >
      {item.placeholder ? (
        <span
          aria-hidden="true"
          className="absolute inset-0 m-auto block"
          style={{
            aspectRatio: item.width && item.height ? `${item.width} / ${item.height}` : undefined,
            maxWidth: "100%",
            maxHeight: "100%",
            backgroundImage: `url("${item.placeholder}")`,
            backgroundSize: "cover",
            filter: "blur(16px)",
          }}
        />
      ) : null}
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- presigned, short-lived URLs on the media origin
        <img
          src={src}
          srcSet={buildSrcSet(item) || undefined}
          sizes="100vw"
          width={item.width ?? undefined}
          height={item.height ?? undefined}
          alt={label}
          draggable={false}
          decoding="async"
          loading={loading}
          className="relative max-h-full max-w-full select-none object-contain"
          style={{
            transform: `translate3d(${zoom.x}px, ${zoom.y}px, 0) scale(${zoom.scale})`,
            transition: gesturing ? "none" : "transform 160ms ease-out",
          }}
        />
      ) : null}
    </div>
  );
}
