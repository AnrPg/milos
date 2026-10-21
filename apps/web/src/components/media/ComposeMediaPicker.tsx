"use client";

import { forwardRef, useImperativeHandle, useRef, useState } from "react";
import { useTranslations } from "next-intl";
import {
  DndContext,
  PointerSensor,
  TouchSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, horizontalListSortingStrategy, useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

import { AltTextSheet } from "@/components/media/AltTextSheet";
import type { ComposeMedia, ComposeMediaItem } from "@/components/media/useComposeMedia";
import { CROP_ASPECTS, type CropAspect, type UploadState } from "@/lib/post-media";

export type ComposeMediaPickerHandle = { focus: () => void };

const CROP_LABEL_KEYS: Record<CropAspect, string> = { original: "crop_original", "4:5": "crop_portrait", "1:1": "crop_square" };

/**
 * Compose's media area (ADR-157, mockup `compose`): «Πρόσθεσε φωτογραφίες ή
 * βίντεο» opens the gallery (or the camera); picked files show as tiles with
 * their progress, retry and remove; tiles reorder by drag or with the move
 * buttons; the selected photo is cropped (original · 4:5 · 1:1) and described.
 */
export const ComposeMediaPicker = forwardRef<ComposeMediaPickerHandle, { media: ComposeMedia }>(function ComposeMediaPicker(
  { media },
  ref,
) {
  const t = useTranslations("Media");
  const galleryInput = useRef<HTMLInputElement>(null);
  const cameraInput = useRef<HTMLInputElement>(null);
  const addButton = useRef<HTMLButtonElement>(null);
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [describing, setDescribing] = useState<string | null>(null);
  const { items, limits } = media;
  const selected = items.find((item) => item.key === selectedKey) ?? items[items.length - 1] ?? null;
  const selectedIndex = selected ? items.indexOf(selected) : -1;
  const videoAllowed = limits.video && media.kind !== "photo";
  const photosAllowed = media.kind !== "video";
  const accept = [...(photosAllowed ? limits.photo_content_types : []), ...(videoAllowed ? limits.video_content_types : [])].join(",");
  const minutes = Math.round(limits.max_video_seconds / 60);
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 250, tolerance: 5 } }),
  );

  useImperativeHandle(ref, () => ({ focus: () => addButton.current?.focus() }), []);

  function picked(files: FileList | null, input: HTMLInputElement | null) {
    if (files?.length) media.add(Array.from(files));
    if (input) input.value = "";
  }

  function dragEnd(event: DragEndEvent) {
    if (!event.over || event.active.id === event.over.id) return;
    const from = items.findIndex((item) => item.key === event.active.id);
    const to = items.findIndex((item) => item.key === event.over!.id);
    if (from >= 0 && to >= 0) media.move(from, to);
  }

  const label = (item: ComposeMediaItem) =>
    item.kind === "video" ? t("videoLabel") : t("photoN", { index: items.indexOf(item) + 1, count: items.length });

  return (
    <section className="flex flex-col gap-3" aria-label={t("listLabel")}>
      {items.length === 0 ? (
        <div className="flex flex-col gap-2">
          <button
            ref={addButton}
            type="button"
            onClick={() => galleryInput.current?.click()}
            className="flex min-h-24 flex-col items-center justify-center gap-1 rounded-2xl px-4 py-5 text-center focus-visible:outline-2 focus-visible:outline-offset-2"
            style={{ border: "1.5px dashed var(--border)", color: "var(--text)", outlineColor: "var(--primary)" }}
          >
            <PhotoIcon />
            <span className="text-sm font-semibold">{limits.video ? t("add") : t("addPhotos")}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>
              {limits.video ? t("addHint", { photos: limits.max_photos, minutes }) : t("addHintPhotos", { photos: limits.max_photos })}
            </span>
          </button>
          <button
            type="button"
            onClick={() => cameraInput.current?.click()}
            className="min-h-11 self-center rounded-full px-4 text-xs font-semibold sm:hidden"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {t("camera")}
          </button>
        </div>
      ) : (
        <>
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={dragEnd}>
            <SortableContext items={items.map((item) => item.key)} strategy={horizontalListSortingStrategy}>
              <ul className="flex gap-2 overflow-x-auto pb-1" aria-label={t("listLabel")}>
                {items.map((item) => (
                  <Tile
                    key={item.key}
                    item={item}
                    label={label(item)}
                    selected={item.key === selected?.key}
                    onSelect={() => setSelectedKey(item.key)}
                    onRemove={() => media.remove(item.key)}
                    onRetry={() => media.retry(item.key)}
                  />
                ))}
                {media.room > 0 ? (
                  <li className="shrink-0">
                    <button
                      ref={addButton}
                      type="button"
                      onClick={() => galleryInput.current?.click()}
                      aria-label={t("addMore")}
                      className="flex h-24 w-24 items-center justify-center rounded-2xl focus-visible:outline-2 focus-visible:outline-offset-2"
                      style={{ border: "1.5px dashed var(--border)", color: "var(--dim)", outlineColor: "var(--primary)" }}
                    >
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                        <path d="M12 5v14M5 12h14" />
                      </svg>
                    </button>
                  </li>
                ) : null}
              </ul>
            </SortableContext>
          </DndContext>

          {selected ? (
            <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
              <div className="flex items-center gap-2">
                <p className="grow text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {label(selected)}
                  <span className="ms-2 text-xs font-normal" style={{ color: "var(--dim)" }} role="status">
                    {statusText(selected.upload, t)}
                  </span>
                </p>
                {items.length > 1 ? (
                  <>
                    <IconButton
                      label={t("moveEarlier")}
                      disabled={selectedIndex <= 0}
                      onClick={() => media.move(selectedIndex, selectedIndex - 1)}
                    >
                      <path d="M15 6l-6 6 6 6" />
                    </IconButton>
                    <IconButton
                      label={t("moveLater")}
                      disabled={selectedIndex >= items.length - 1}
                      onClick={() => media.move(selectedIndex, selectedIndex + 1)}
                    >
                      <path d="M9 6l6 6-6 6" />
                    </IconButton>
                  </>
                ) : null}
              </div>
              {selected.upload.error ? (
                <p className="text-sm" style={{ color: "var(--danger)" }}>
                  {t(["error", selected.upload.error].join("_"), { minutes })}
                </p>
              ) : null}
              {selected.kind === "photo" && selected.upload.phase !== "rejected" ? (
                <>
                  <div role="radiogroup" aria-label={t("crop")} className="flex flex-wrap items-center gap-2">
                    <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }} aria-hidden="true">
                      {t("crop")}
                    </span>
                    {CROP_ASPECTS.map((aspect) => (
                      <button
                        key={aspect}
                        type="button"
                        role="radio"
                        aria-checked={selected.aspect === aspect}
                        disabled={!selected.croppable}
                        onClick={() => media.setAspect(selected.key, aspect)}
                        className="min-h-9 rounded-full px-3 text-xs font-semibold disabled:opacity-50"
                        style={{
                          background: selected.aspect === aspect ? "var(--primary)" : "transparent",
                          color: selected.aspect === aspect ? "var(--bg)" : "var(--text)",
                          border: "1px solid var(--border)",
                        }}
                      >
                        {t(CROP_LABEL_KEYS[aspect])}
                      </button>
                    ))}
                  </div>
                  {!selected.croppable ? (
                    <p className="text-xs" style={{ color: "var(--dim)" }}>{t("cropUnavailable")}</p>
                  ) : null}
                  <button
                    type="button"
                    onClick={() => setDescribing(selected.key)}
                    disabled={!selected.mediaId}
                    aria-haspopup="dialog"
                    className="flex min-h-11 items-center justify-between gap-2 rounded-2xl px-3 text-start text-sm disabled:opacity-60"
                    style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    <span className="flex min-w-0 flex-col">
                      <span className="font-semibold">{t("altText")}</span>
                      <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                        {selected.altText || (selected.mediaId ? t("altEmpty") : t("altWaitUpload"))}
                      </span>
                    </span>
                    <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
                  </button>
                </>
              ) : null}
            </div>
          ) : null}
        </>
      )}

      {media.refusal ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
          {t(["refusal", media.refusal].join("_"), { photos: limits.max_photos })}
        </p>
      ) : null}

      <input
        ref={galleryInput}
        type="file"
        accept={accept}
        multiple={photosAllowed}
        hidden
        tabIndex={-1}
        data-testid="media-input"
        onChange={(event) => picked(event.target.files, event.target)}
      />
      <input
        ref={cameraInput}
        type="file"
        accept={videoAllowed && photosAllowed ? "image/*,video/*" : videoAllowed ? "video/*" : "image/*"}
        capture="environment"
        hidden
        tabIndex={-1}
        onChange={(event) => picked(event.target.files, event.target)}
      />

      {describing ? (
        <DescribeSheet media={media} itemKey={describing} onClose={() => setDescribing(null)} />
      ) : null}
    </section>
  );
});

function DescribeSheet({ media, itemKey, onClose }: { media: ComposeMedia; itemKey: string; onClose: () => void }) {
  const item = media.items.find((entry) => entry.key === itemKey);
  if (!item?.mediaId) return null;
  return (
    <AltTextSheet
      mediaId={item.mediaId}
      previewUrl={item.previewUrl}
      initial={item.altText}
      maxLength={500}
      onSaved={(text) => media.setAltText(item.key, text)}
      onClose={onClose}
    />
  );
}

function statusText(upload: UploadState, t: ReturnType<typeof useTranslations>) {
  if (upload.phase === "uploading") return t("status_uploading", { percent: Math.round(upload.progress * 100) });
  return t(["status", upload.phase].join("_"));
}

function Tile({
  item,
  label,
  selected,
  onSelect,
  onRemove,
  onRetry,
}: {
  item: ComposeMediaItem;
  label: string;
  selected: boolean;
  onSelect: () => void;
  onRemove: () => void;
  onRetry: () => void;
}) {
  const t = useTranslations("Media");
  const { setNodeRef, transform, transition, isDragging, listeners } = useSortable({ id: item.key });
  const { phase, progress } = item.upload;
  const showProgress = phase === "preparing" || phase === "uploading" || phase === "completing";
  return (
    <li
      ref={setNodeRef}
      className="relative h-24 w-24 shrink-0"
      style={{ transform: CSS.Transform.toString(transform), transition, zIndex: isDragging ? 2 : undefined }}
      data-testid="media-tile"
      data-phase={phase}
    >
      <button
        type="button"
        {...listeners}
        onClick={onSelect}
        aria-pressed={selected}
        aria-label={label}
        className="block h-full w-full overflow-hidden rounded-2xl focus-visible:outline-2 focus-visible:outline-offset-2"
        style={{
          border: `2px solid ${selected ? "var(--primary)" : "var(--border)"}`,
          outlineColor: "var(--primary)",
          background: "var(--panel-raised)",
          touchAction: "manipulation",
        }}
      >
        {item.kind === "video" ? (
          <video src={item.previewUrl} muted playsInline preload="metadata" className="h-full w-full object-cover" aria-hidden="true" />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element -- a local object URL
          <img
            src={item.previewUrl}
            alt=""
            className="h-full w-full object-cover"
            draggable={false}
            // A photo the browser cannot show (HEIC) still uploads; hide the broken image.
            onError={(event) => {
              event.currentTarget.style.visibility = "hidden";
            }}
          />
        )}
        {item.kind === "video" ? (
          <span className="absolute bottom-1.5 start-1.5 rounded-full px-1.5 text-[10px] font-bold" style={{ background: "var(--media-control)", color: "var(--on-media)" }} aria-hidden="true">
            ▶
          </span>
        ) : null}
        {phase === "processing" ? (
          <span className="absolute inset-x-0 bottom-0 px-1 py-0.5 text-center text-[10px] font-semibold" style={{ background: "var(--media-control)", color: "var(--on-media)" }} aria-hidden="true">
            {t("status_processing")}
          </span>
        ) : null}
        {phase === "failed" || phase === "rejected" ? (
          <span className="absolute inset-0 flex items-center justify-center" style={{ background: "var(--media-control)", color: "var(--on-media)" }} aria-hidden="true">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 8v5M12 16.5v.5" />
              <circle cx="12" cy="12" r="9" />
            </svg>
          </span>
        ) : null}
      </button>
      {showProgress ? (
        <div
          role="progressbar"
          aria-label={label}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(progress * 100)}
          className="pointer-events-none absolute inset-x-2 bottom-2 h-1.5 overflow-hidden rounded-full"
          style={{ background: "var(--media-control)" }}
        >
          <div className="h-full rounded-full transition-[width]" style={{ width: `${Math.max(4, progress * 100)}%`, background: "var(--primary)" }} />
        </div>
      ) : null}
      <button
        type="button"
        onClick={onRemove}
        aria-label={t("removeItem", { item: label })}
        className="absolute -end-1.5 -top-1.5 flex h-7 w-7 items-center justify-center rounded-full focus-visible:outline-2"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)", outlineColor: "var(--primary)" }}
      >
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" aria-hidden="true">
          <path d="M6 6l12 12M18 6L6 18" />
        </svg>
      </button>
      {phase === "failed" ? (
        <button
          type="button"
          onClick={onRetry}
          className="absolute inset-x-1.5 bottom-1.5 min-h-7 rounded-full text-[11px] font-bold focus-visible:outline-2"
          style={{ background: "var(--primary)", color: "var(--bg)", outlineColor: "var(--text)" }}
          aria-label={[t("retry"), label].join(" · ")}
        >
          {t("retry")}
        </button>
      ) : null}
    </li>
  );
}

function IconButton({
  label,
  disabled,
  onClick,
  children,
}: {
  label: string;
  disabled?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className="flex h-11 w-11 items-center justify-center rounded-full disabled:opacity-40 focus-visible:outline-2"
      style={{ border: "1px solid var(--border)", color: "var(--text)", outlineColor: "var(--primary)" }}
    >
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" aria-hidden="true" className="rtl:-scale-x-100">
        {children}
      </svg>
    </button>
  );
}

function PhotoIcon() {
  return (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true" style={{ color: "var(--dim)" }}>
      <rect x="3" y="5" width="18" height="14" rx="3" />
      <circle cx="9" cy="10" r="1.6" />
      <path d="M21 16l-5-5-8 8" />
    </svg>
  );
}
