"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { Dialog } from "@/components/ui/Dialog";

export type StripPhoto = { id: string; url?: string | null; caption?: string | null };

/**
 * Photos of a room in a row that scrolls sideways (ADR-290). Tapping one
 * opens it large, with its caption.
 */
export function RoomPhotoStrip({ photos, testId }: { photos: StripPhoto[]; testId?: string }) {
  const t = useTranslations("Spaces");
  const [open, setOpen] = useState<StripPhoto | null>(null);
  const shown = photos.filter((photo) => photo.url);

  return (
    <>
      <ul className="flex snap-x gap-2 overflow-x-auto pb-1" data-testid={testId}>
        {shown.map((photo) => (
          <li key={photo.id} className="shrink-0 snap-start">
            <button
              type="button"
              className="block overflow-hidden rounded-xl"
              style={{ border: "1px solid var(--border)" }}
              aria-label={photo.caption || t("roomPhotoOpen")}
              onClick={() => setOpen(photo)}
            >
              {/* A signed, short-lived URL from object storage: next/image would cache it. */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={photo.url!} alt={photo.caption ?? ""} className="block h-28 w-40 object-cover" />
            </button>
            {photo.caption ? (
              <p className="mt-1 w-40 truncate text-xs" style={{ color: "var(--muted)" }}>{photo.caption}</p>
            ) : null}
          </li>
        ))}
      </ul>
      {open ? (
        <Dialog title={open.caption || t("roomPhotos")} size="3xl" variant="center" onClose={() => setOpen(null)}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={open.url!} alt={open.caption ?? ""} className="block h-auto w-full rounded-xl" />
        </Dialog>
      ) : null}
    </>
  );
}
