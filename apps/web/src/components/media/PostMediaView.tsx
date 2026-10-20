"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import type { PostMedia } from "@/api/media";
import {
  FEED_IMAGE_SIZES,
  buildSrcSet,
  formatDuration,
  frameAspect,
  indexFromScroll,
  keyIndex,
  stepIndex,
} from "@/lib/post-media";

/**
 * A post's photos or video in the feed (ADR-157, mockup `photoPost`): one
 * photo full width, 2–10 in a swipeable scroll-snap carousel with dots, an
 * «n/10» counter, arrows on desktop and the arrow keys. Tapping a photo opens
 * the viewer. A video plays inline, muted, only while in view.
 */
export function PostMediaView({
  media,
  author,
  onOpen,
}: {
  media: PostMedia[];
  author: string;
  onOpen: (index: number) => void;
}) {
  const t = useTranslations("Media");
  const first = media[0];
  if (!first) return null;
  const aspect = frameAspect(first.width, first.height);
  const label = (item: PostMedia, index: number) =>
    item.alt_text || (item.kind === "video" ? t("videoBy", { name: author }) : media.length > 1 ? t("photoNBy", { index: index + 1, count: media.length, name: author }) : t("photoBy", { name: author }));

  if (first.kind === "video") {
    return (
      <div className="overflow-hidden rounded-2xl" style={{ aspectRatio: String(aspect), background: "#000" }}>
        <InlineVideo item={first} label={label(first, 0)} onOpen={() => onOpen(0)} />
      </div>
    );
  }
  if (media.length === 1) {
    return (
      <div className="relative overflow-hidden rounded-2xl" style={{ aspectRatio: String(aspect) }}>
        <PhotoSlide item={first} label={label(first, 0)} onOpen={() => onOpen(0)} eager={false} />
      </div>
    );
  }
  return <MediaCarousel media={media} aspect={aspect} label={label} onOpen={onOpen} />;
}

function MediaCarousel({
  media,
  aspect,
  label,
  onOpen,
}: {
  media: PostMedia[];
  aspect: number;
  label: (item: PostMedia, index: number) => string;
  onOpen: (index: number) => void;
}) {
  const t = useTranslations("Media");
  const track = useRef<HTMLDivElement>(null);
  const frame = useRef(0);
  const [index, setIndex] = useState(0);
  const count = media.length;

  const go = useCallback(
    (target: number) => {
      const element = track.current;
      if (!element) return;
      const next = stepIndex(target, 0, count);
      const rtl = getComputedStyle(element).direction === "rtl";
      const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
      element.scrollTo({ left: next * element.clientWidth * (rtl ? -1 : 1), behavior: reduce ? "auto" : "smooth" });
      setIndex(next);
    },
    [count],
  );

  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  function onScroll() {
    cancelAnimationFrame(frame.current);
    frame.current = requestAnimationFrame(() => {
      const element = track.current;
      if (element) setIndex(indexFromScroll(element.scrollLeft, element.clientWidth, count));
    });
  }

  function onKeyDown(event: React.KeyboardEvent) {
    const rtl = track.current ? getComputedStyle(track.current).direction === "rtl" : false;
    const next = keyIndex(event.key, index, count, rtl);
    if (next === null) return;
    event.preventDefault();
    go(next);
  }

  return (
    <section
      aria-roledescription={t("roleCarousel")}
      aria-label={t("carouselLabel", { count })}
      className="relative"
      onKeyDown={onKeyDown}
      data-testid="media-carousel"
    >
      <div
        ref={track}
        onScroll={onScroll}
        className="flex snap-x snap-mandatory overflow-x-auto overscroll-x-contain rounded-2xl [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        style={{ aspectRatio: String(aspect) }}
      >
        {media.map((item, position) => (
          <div
            key={item.id}
            role="group"
            aria-roledescription={t("roleSlide")}
            aria-label={t("slideN", { index: position + 1, count })}
            aria-hidden={position !== index ? true : undefined}
            className="relative h-full w-full shrink-0 snap-start snap-always"
          >
            <PhotoSlide
              item={item}
              label={label(item, position)}
              onOpen={() => onOpen(position)}
              eager={false}
              tabbable={position === index}
            />
          </div>
        ))}
      </div>
      <span
        aria-hidden="true"
        className="pointer-events-none absolute end-2 top-2 rounded-full px-2 py-0.5 text-xs font-bold tabular-nums"
        style={{ background: "rgba(0,0,0,.6)", color: "#fff" }}
        data-testid="media-counter"
      >
        {t("counter", { current: index + 1, count })}
      </span>
      <CarouselArrow direction="previous" label={t("previous")} disabled={index === 0} onClick={() => go(index - 1)} />
      <CarouselArrow direction="next" label={t("next")} disabled={index === count - 1} onClick={() => go(index + 1)} />
      <div className="mt-1 flex justify-center gap-0.5">
        {media.map((item, position) => (
          <button
            key={item.id}
            type="button"
            onClick={() => go(position)}
            aria-label={t("goTo", { index: position + 1 })}
            aria-current={position === index ? "true" : undefined}
            className="flex h-6 w-5 items-center justify-center rounded-full focus-visible:outline-2"
            style={{ outlineColor: "var(--primary)" }}
          >
            <span
              className="block h-1.5 w-1.5 rounded-full transition-transform"
              style={{
                background: position === index ? "var(--primary)" : "var(--border)",
                transform: position === index ? "scale(1.35)" : undefined,
              }}
            />
          </button>
        ))}
      </div>
    </section>
  );
}

function CarouselArrow({
  direction,
  label,
  disabled,
  onClick,
}: {
  direction: "previous" | "next";
  label: string;
  disabled: boolean;
  onClick: () => void;
}) {
  if (disabled) return null;
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className={[
        "absolute top-[calc(50%-1.5rem)] hidden h-9 w-9 -translate-y-1/2 items-center justify-center rounded-full shadow focus-visible:outline-2 [@media(hover:hover)_and_(pointer:fine)]:flex",
        direction === "previous" ? "start-2" : "end-2",
      ].join(" ")}
      style={{ background: "rgba(255,255,255,.88)", color: "#111", outlineColor: "var(--primary)" }}
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" aria-hidden="true" className="rtl:-scale-x-100">
        <path d={direction === "previous" ? "M15 6l-6 6 6 6" : "M9 6l6 6-6 6"} />
      </svg>
    </button>
  );
}

/** A photo letterboxed in its frame over its blurred placeholder; a rendition that is not ready yet shows as processing. */
export function MediaImage({
  item,
  label,
  sizes = FEED_IMAGE_SIZES,
  eager,
  fit = "contain",
}: {
  item: PostMedia;
  label: string;
  sizes?: string;
  eager?: boolean;
  fit?: "contain" | "cover";
}) {
  const t = useTranslations("Media");
  const src = item.feed_url ?? item.full_url ?? item.thumb_url;
  const loading: "eager" | "lazy" = eager ? "eager" : "lazy";
  return (
    <span className="absolute inset-0 block overflow-hidden" style={{ background: "var(--panel-raised)" }}>
      {item.placeholder ? (
        <span
          aria-hidden="true"
          className="absolute inset-0 block scale-110"
          style={{ backgroundImage: `url("${item.placeholder}")`, backgroundSize: "cover", backgroundPosition: "center", filter: "blur(18px)" }}
        />
      ) : null}
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- presigned, short-lived URLs on the media origin
        <img
          src={src}
          srcSet={buildSrcSet(item) || undefined}
          sizes={sizes}
          width={item.width ?? undefined}
          height={item.height ?? undefined}
          alt={label}
          loading={loading}
          decoding="async"
          draggable={false}
          className="relative h-full w-full"
          style={{ objectFit: fit }}
        />
      ) : (
        <span className="relative flex h-full w-full items-center justify-center text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("itemProcessing")}
        </span>
      )}
    </span>
  );
}

function PhotoSlide({
  item,
  label,
  onOpen,
  eager,
  tabbable = true,
}: {
  item: PostMedia;
  label: string;
  onOpen: () => void;
  eager: boolean;
  tabbable?: boolean;
}) {
  const t = useTranslations("Media");
  const ready = Boolean(item.feed_url || item.full_url);
  if (!ready) return <MediaImage item={item} label={label} eager={eager} />;
  return (
    <button
      type="button"
      onClick={onOpen}
      tabIndex={tabbable ? 0 : -1}
      aria-label={[label, t("openViewer")].join(" · ")}
      className="absolute inset-0 block h-full w-full cursor-zoom-in focus-visible:outline-2 focus-visible:-outline-offset-4"
      style={{ outlineColor: "var(--primary)" }}
    >
      <MediaImage item={item} label={label} eager={eager} />
    </button>
  );
}

function prefersStill() {
  if (typeof window === "undefined") return true;
  const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  const connection = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection;
  return reduce || Boolean(connection?.saveData);
}

/**
 * A post video inline: muted with its poster, playing only while mostly in
 * view (never with reduced motion or data saver). The first tap turns the
 * sound on and shows the controls.
 */
export function InlineVideo({ item, label, onOpen }: { item: PostMedia; label: string; onOpen?: () => void }) {
  const t = useTranslations("Media");
  const ref = useRef<HTMLVideoElement>(null);
  const [engaged, setEngaged] = useState(false);
  const [still] = useState(prefersStill);

  useEffect(() => {
    const video = ref.current;
    if (!video || still || engaged || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && entry.intersectionRatio >= 0.6) void video.play().catch(() => undefined);
        else video.pause();
      },
      { threshold: [0, 0.6, 1] },
    );
    observer.observe(video);
    return () => observer.disconnect();
  }, [still, engaged]);

  if (!item.video_url) {
    return (
      <div className="relative h-full w-full">
        <MediaImage item={item} label={label} />
      </div>
    );
  }

  const preload: "none" | "metadata" = still ? "none" : "metadata";

  function engage() {
    const video = ref.current;
    if (!video) return;
    setEngaged(true);
    video.muted = false;
    video.controls = true;
    void video.play().catch(() => undefined);
  }

  return (
    <div className="relative h-full w-full">
      <video
        ref={ref}
        src={item.video_url}
        poster={item.feed_url ?? undefined}
        muted={!engaged}
        loop={!engaged}
        playsInline
        preload={preload}
        aria-label={label}
        width={item.width ?? undefined}
        height={item.height ?? undefined}
        className="h-full w-full object-contain"
        data-testid="post-video"
      />
      {!engaged ? (
        <button
          type="button"
          onClick={engage}
          aria-label={still ? t("play") : t("unmute")}
          className="absolute inset-0 flex items-end justify-between p-3 focus-visible:outline-2 focus-visible:-outline-offset-4"
          style={{ outlineColor: "var(--primary)" }}
        >
          <span className="rounded-full px-2 py-0.5 text-xs font-bold tabular-nums" style={{ background: "rgba(0,0,0,.6)", color: "#fff" }}>
            {formatDuration(item.duration_ms)}
          </span>
          <span className="flex h-9 w-9 items-center justify-center rounded-full" style={{ background: "rgba(0,0,0,.6)", color: "#fff" }} aria-hidden="true">
            {still ? (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
            ) : (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M11 5L6 9H3v6h3l5 4V5z" />
                <path d="M22 9l-6 6M16 9l6 6" />
              </svg>
            )}
          </span>
        </button>
      ) : onOpen ? (
        <button
          type="button"
          onClick={onOpen}
          aria-label={t("openViewer")}
          className="absolute end-2 top-2 flex h-9 w-9 items-center justify-center rounded-full focus-visible:outline-2"
          style={{ background: "rgba(0,0,0,.55)", color: "#fff", outlineColor: "var(--primary)" }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
            <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
          </svg>
        </button>
      ) : null}
    </div>
  );
}
