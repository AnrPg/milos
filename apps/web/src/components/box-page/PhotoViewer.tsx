"use client";

import { useEffect, useEffectEvent, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import type { PublicBoxPage } from "@/api/social";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

import { Icon } from "./Icon";

type Photo = PublicBoxPage["profile"]["photos"][number];

/**
 * Full-screen photo viewer (plan §5a board 4 Q6): swipe or arrows between
 * photos, a counter, thumbnails, and ✕, Escape or a swipe down to close.
 */
export function PhotoViewer({ photos, start, onClose }: { photos: Photo[]; start: number; onClose: () => void }) {
  const t = useTranslations("BoxPage");
  const [index, setIndex] = useState(start);
  const dialog = useModalFocusTrap<HTMLDivElement>(onClose);
  const touch = useRef<{ x: number; y: number } | null>(null);

  const go = (step: number) => setIndex((current) => (current + step + photos.length) % photos.length);
  const onKey = useEffectEvent((event: KeyboardEvent) => {
    const rtl = document.dir === "rtl";
    if (event.key === "ArrowRight") go(rtl ? -1 : 1);
    if (event.key === "ArrowLeft") go(rtl ? 1 : -1);
  });

  useEffect(() => {
    const listener = (event: KeyboardEvent) => onKey(event);
    document.addEventListener("keydown", listener);
    return () => document.removeEventListener("keydown", listener);
  }, []);

  const photo = photos[index];
  const button = "grid h-11 w-11 place-items-center rounded-full";

  return (
    <div
      ref={dialog}
      role="dialog"
      aria-modal="true"
      aria-label={t("photosTitle")}
      className="fixed inset-0 z-[70] flex flex-col"
      style={{ background: "var(--scrim-strong)", color: "var(--on-media)" }}
      onTouchStart={(event) => {
        touch.current = { x: event.touches[0].clientX, y: event.touches[0].clientY };
      }}
      onTouchEnd={(event) => {
        if (!touch.current) return;
        const dx = event.changedTouches[0].clientX - touch.current.x;
        const dy = event.changedTouches[0].clientY - touch.current.y;
        touch.current = null;
        if (dy > 90 && Math.abs(dy) > Math.abs(dx)) onClose();
        else if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
      }}
    >
      <header className="flex items-center justify-between px-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <span className="px-2 text-sm font-semibold" aria-live="polite">
          {t("photoCounter", { current: index + 1, total: photos.length })}
        </span>
        <button type="button" onClick={onClose} aria-label={t("close")} className={button} style={{ background: "var(--media-control-inverse)" }}>
          <Icon name="x" />
        </button>
      </header>

      <div className="relative flex min-h-0 flex-1 items-center justify-center px-2">
        {/* eslint-disable-next-line @next/next/no-img-element -- media from the gym's storage */}
        <img src={photo.url} alt={t("photoAlt", { current: index + 1 })} className="max-h-full max-w-full object-contain" />
        {photos.length > 1 ? (
          <>
            <button
              type="button"
              onClick={() => go(-1)}
              aria-label={t("previousPhoto")}
              className={`${button} absolute start-3 top-1/2 hidden -translate-y-1/2 sm:grid rtl:rotate-180`}
              style={{ background: "var(--media-control-inverse)" }}
            >
              <Icon name="chevron-left" />
            </button>
            <button
              type="button"
              onClick={() => go(1)}
              aria-label={t("nextPhoto")}
              className={`${button} absolute end-3 top-1/2 hidden -translate-y-1/2 sm:grid rtl:rotate-180`}
              style={{ background: "var(--media-control-inverse)" }}
            >
              <Icon name="chevron-right" />
            </button>
          </>
        ) : null}
      </div>

      {photos.length > 1 ? (
        <ol className="flex justify-center gap-2 overflow-x-auto px-3 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3">
          {photos.map((item, position) => (
            <li key={item.id} className="shrink-0">
              <button
                type="button"
                onClick={() => setIndex(position)}
                aria-label={t("photoAlt", { current: position + 1 })}
                aria-current={position === index ? "true" : undefined}
                className="block h-14 w-14 overflow-hidden rounded-lg"
                style={{ outline: position === index ? "2px solid var(--on-media)" : "none", opacity: position === index ? 1 : 0.55 }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element -- thumbnail */}
                <img src={item.url} alt="" className="h-full w-full object-cover" />
              </button>
            </li>
          ))}
        </ol>
      ) : null}
    </div>
  );
}
