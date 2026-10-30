"use client";

import { useEffect, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  addCleaningPoint,
  addSpacePhoto,
  deleteCleaningPoint,
  deleteSpacePhoto,
  orderCleaningPoints,
  orderSpacePhotos,
  updateCleaningPoint,
  updateSpacePhoto,
  uploadRoomPhoto,
  type CleaningPoint,
  type SpacePhoto,
} from "@/api/spaces";
import { moveItem } from "@/components/spaces/room-photos";
import { captionClass, captionStyle, inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { preparePhoto } from "@/lib/media-files";
import { putPresigned } from "@/lib/presigned-upload";

/** How long the floating 🌐 button stays after a tap before it hides again. */
const PUBLIC_BUTTON_MS = 2500;

async function upload(token: string, kind: "photos" | "points", file: File) {
  const prepared = await preparePhoto(file, "original");
  return uploadRoomPhoto(token, kind, prepared, putPresigned);
}

/**
 * The two photo sections of a room in Settings › Spaces (ADR-290):
 * «Φωτογραφίες χώρου», to get an idea of the room, each one off the public
 * box page until its uploader taps the floating 🌐; and «Σημεία
 * καθαριότητας», a photo of a part of the room and what to clean there,
 * which the janitor answers one by one.
 */
export function RoomPhotosEditor({
  token,
  spaceId,
  photos,
  points,
  canEdit,
  queryKey,
}: {
  token: string;
  spaceId: string;
  photos: SpacePhoto[];
  points: CleaningPoint[];
  canEdit: boolean;
  queryKey: readonly unknown[];
}) {
  const queryClient = useQueryClient();
  const refresh = () => queryClient.invalidateQueries({ queryKey });

  if (!canEdit && photos.length === 0 && points.length === 0) return null;

  return (
    <>
      <RoomPhotos token={token} spaceId={spaceId} photos={photos} canEdit={canEdit} onChanged={refresh} />
      <CleaningPoints token={token} spaceId={spaceId} points={points} canEdit={canEdit} onChanged={refresh} />
    </>
  );
}

function RoomPhotos({
  token,
  spaceId,
  photos,
  canEdit,
  onChanged,
}: {
  token: string;
  spaceId: string;
  photos: SpacePhoto[];
  canEdit: boolean;
  onChanged: () => Promise<unknown>;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const input = useRef<HTMLInputElement>(null);

  const add = useMutation({
    mutationFn: async (files: File[]) => {
      for (const file of files) {
        const mediaId = await upload(token, "photos", file);
        await addSpacePhoto(token, spaceId, { media_id: mediaId });
      }
    },
    onSettled: onChanged,
  });
  const change = useMutation({
    mutationFn: ({ id, body }: { id: string; body: { caption?: string | null; public?: boolean } }) => updateSpacePhoto(token, id, body),
    onSuccess: onChanged,
  });
  const remove = useMutation({ mutationFn: (id: string) => deleteSpacePhoto(token, id), onSuccess: onChanged });
  const order = useMutation({ mutationFn: (ids: string[]) => orderSpacePhotos(token, spaceId, ids), onSuccess: onChanged });
  const error = add.error ?? change.error ?? remove.error ?? order.error;

  return (
    <section data-testid="space-detail-photos">
      <div className="flex items-center justify-between gap-2">
        <h3 className={captionClass} style={captionStyle}>{t("roomPhotos")}</h3>
        {canEdit ? (
          <>
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={add.isPending} data-testid="room-photo-add" onClick={() => input.current?.click()}>
              {add.isPending ? t("uploading") : t("roomPhotoAdd")}
            </button>
            <input
              ref={input}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic"
              multiple
              hidden
              data-testid="room-photo-file"
              onChange={(event) => {
                const files = Array.from(event.target.files ?? []);
                event.target.value = "";
                if (files.length > 0) add.mutate(files);
              }}
            />
          </>
        ) : null}
      </div>
      {photos.length === 0 ? (
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{canEdit ? t("roomPhotosEmpty") : t("roomPhotosNone")}</p>
      ) : (
        <ul className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
          {photos.map((photo, index) => (
            <PhotoTile
              // A caption saved elsewhere resets the field.
              key={`${photo.id}:${photo.caption ?? ""}`}
              photo={photo}
              canEdit={canEdit}
              first={index === 0}
              last={index === photos.length - 1}
              onPublic={(next) => change.mutate({ id: photo.id, body: { public: next } })}
              onCaption={(caption) => change.mutate({ id: photo.id, body: { caption } })}
              onMove={(by) => order.mutate(moveItem(photos.map((item) => item.id), index, by))}
              onDelete={() => {
                if (window.confirm(t("roomPhotoDeleteConfirm"))) remove.mutate(photo.id);
              }}
            />
          ))}
        </ul>
      )}
      {canEdit && photos.length > 0 ? <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("roomPhotoPublicHint")}</p> : null}
      {error ? <StatusText tone="error">{localizeError(error, ui)}</StatusText> : null}
    </section>
  );
}

function PhotoTile({
  photo,
  canEdit,
  first,
  last,
  onPublic,
  onCaption,
  onMove,
  onDelete,
}: {
  photo: SpacePhoto;
  canEdit: boolean;
  first: boolean;
  last: boolean;
  onPublic: (next: boolean) => void;
  onCaption: (caption: string | null) => void;
  onMove: (by: -1 | 1) => void;
  onDelete: () => void;
}) {
  const t = useTranslations("Spaces");
  const [awake, setAwake] = useState(false);
  const [caption, setCaption] = useState(photo.caption ?? "");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  // The 🌐 floats over the photo only for a moment after a tap or while hovered.
  const wake = () => {
    setAwake(true);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setAwake(false), PUBLIC_BUTTON_MS);
  };

  return (
    <li className="flex flex-col gap-1" data-testid={`room-photo-${photo.id}`} data-public={photo.public ? "true" : "false"}>
      <div
        className="group relative overflow-hidden rounded-xl"
        style={{ border: "1px solid var(--border)" }}
        onPointerDown={canEdit ? wake : undefined}
        onMouseEnter={canEdit ? wake : undefined}
      >
        {/* A signed, short-lived URL from object storage: next/image would cache it. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={photo.url ?? ""} alt={photo.caption ?? ""} className="block aspect-[4/3] w-full object-cover" />
        {canEdit ? (
          <button
            type="button"
            data-testid={`room-photo-public-${photo.id}`}
            aria-pressed={photo.public}
            aria-label={photo.public ? t("roomPhotoPublicOff") : t("roomPhotoPublicOn")}
            title={photo.public ? t("roomPhotoPublicOff") : t("roomPhotoPublicOn")}
            className="absolute end-2 top-2 flex h-8 w-8 items-center justify-center rounded-full text-sm transition-opacity duration-300 focus:opacity-100 group-hover:opacity-100"
            style={{
              opacity: awake || photo.public ? 1 : 0,
              background: photo.public ? "var(--primary)" : "color-mix(in srgb, var(--panel) 85%, transparent)",
              color: photo.public ? "var(--primary-contrast)" : "var(--text)",
              border: "1px solid var(--border)",
            }}
            onClick={() => {
              wake();
              onPublic(!photo.public);
            }}
          >
            <span aria-hidden="true">🌐</span>
          </button>
        ) : photo.public ? (
          <span className="absolute end-2 top-2 text-sm" aria-label={t("roomPhotoIsPublic")}>🌐</span>
        ) : null}
      </div>
      {canEdit ? (
        <>
          <input
            className={inputClass}
            style={inputStyle}
            value={caption}
            maxLength={200}
            placeholder={t("roomPhotoCaption")}
            aria-label={t("roomPhotoCaption")}
            onChange={(event) => setCaption(event.target.value)}
            onBlur={() => {
              const next = caption.trim() || null;
              if (next !== (photo.caption ?? null)) onCaption(next);
            }}
          />
          <div className="flex gap-1">
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={first} aria-label={t("moveEarlier")} onClick={() => onMove(-1)}>‹</button>
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={last} aria-label={t("moveLater")} onClick={() => onMove(1)}>›</button>
            <button type="button" className={`${secondaryButtonClass} ms-auto`} style={secondaryButtonStyle} aria-label={t("roomPhotoDelete")} onClick={onDelete}>✕</button>
          </div>
        </>
      ) : photo.caption ? (
        <p className="truncate text-xs" style={{ color: "var(--muted)" }}>{photo.caption}</p>
      ) : null}
    </li>
  );
}

function CleaningPoints({
  token,
  spaceId,
  points,
  canEdit,
  onChanged,
}: {
  token: string;
  spaceId: string;
  points: CleaningPoint[];
  canEdit: boolean;
  onChanged: () => Promise<unknown>;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<CleaningPoint | null>(null);
  const remove = useMutation({ mutationFn: (id: string) => deleteCleaningPoint(token, id), onSuccess: onChanged });
  const order = useMutation({ mutationFn: (ids: string[]) => orderCleaningPoints(token, spaceId, ids), onSuccess: onChanged });
  const error = remove.error ?? order.error;

  return (
    <section data-testid="space-detail-points">
      <div className="flex items-center justify-between gap-2">
        <h3 className={captionClass} style={captionStyle}>{t("cleaningPoints")}</h3>
        {canEdit ? (
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} data-testid="cleaning-point-add" onClick={() => setAdding(true)}>
            {t("cleaningPointAdd")}
          </button>
        ) : null}
      </div>
      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("cleaningPointsHint")}</p>
      {points.length > 0 ? (
        <ol className="mt-2 flex flex-col gap-2">
          {points.map((point, index) => (
            <li
              key={point.id}
              data-testid={`cleaning-point-${point.id}`}
              className="flex items-center gap-3 rounded-xl p-2"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={point.url ?? ""} alt="" className="h-14 w-14 shrink-0 rounded-lg object-cover" />
              <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--text)" }}>
                <span style={{ color: "var(--dim)" }}>{index + 1}. </span>
                {point.instruction}
              </span>
              {canEdit ? (
                <span className="flex shrink-0 gap-1">
                  <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={index === 0} aria-label={t("moveEarlier")} onClick={() => order.mutate(moveItem(points.map((item) => item.id), index, -1))}>↑</button>
                  <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={index === points.length - 1} aria-label={t("moveLater")} onClick={() => order.mutate(moveItem(points.map((item) => item.id), index, 1))}>↓</button>
                  <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setEditing(point)}>{t("edit")}</button>
                  <button
                    type="button"
                    className={secondaryButtonClass}
                    style={secondaryButtonStyle}
                    aria-label={t("cleaningPointDelete")}
                    onClick={() => {
                      if (window.confirm(t("cleaningPointDeleteConfirm"))) remove.mutate(point.id);
                    }}
                  >
                    ✕
                  </button>
                </span>
              ) : null}
            </li>
          ))}
        </ol>
      ) : null}
      {error ? <StatusText tone="error">{localizeError(error, ui)}</StatusText> : null}
      {adding || editing ? (
        <PointForm
          token={token}
          spaceId={spaceId}
          point={editing}
          onClose={() => {
            setAdding(false);
            setEditing(null);
          }}
          onSaved={onChanged}
        />
      ) : null}
    </section>
  );
}

function PointForm({
  token,
  spaceId,
  point,
  onClose,
  onSaved,
}: {
  token: string;
  spaceId: string;
  point: CleaningPoint | null;
  onClose: () => void;
  onSaved: () => Promise<unknown>;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const input = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [instruction, setInstruction] = useState(point?.instruction ?? "");
  const [preview, setPreview] = useObjectUrl();

  const save = useMutation({
    mutationFn: async () => {
      const mediaId = file ? await upload(token, "points", file) : undefined;
      if (point) return updateCleaningPoint(token, point.id, { instruction: instruction.trim(), ...(mediaId ? { media_id: mediaId } : {}) });
      return addCleaningPoint(token, spaceId, { media_id: mediaId!, instruction: instruction.trim() });
    },
    onSuccess: async () => {
      await onSaved();
      onClose();
    },
  });
  const ready = instruction.trim().length > 0 && (Boolean(point) || Boolean(file));

  return (
    <Dialog
      title={point ? t("cleaningPointEdit") : t("cleaningPointAdd")}
      size="md"
      onClose={onClose}
      error={save.isError ? localizeError(save.error, ui) : undefined}
      onSubmit={(event) => {
        event.preventDefault();
        if (ready) save.mutate();
      }}
      footer={
        <>
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" disabled={!ready || save.isPending} testId="cleaning-point-save">
            {save.isPending ? t("uploading") : t("save")}
          </DialogButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="flex items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {preview || point?.url ? <img src={preview ?? point?.url ?? ""} alt="" className="h-20 w-20 rounded-lg object-cover" /> : null}
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => input.current?.click()}>
            {point || file ? t("cleaningPointPhotoChange") : t("cleaningPointPhoto")}
          </button>
          <input
            ref={input}
            type="file"
            accept="image/jpeg,image/png,image/webp,image/heic"
            hidden
            data-testid="cleaning-point-file"
            onChange={(event) => {
              const next = event.target.files?.[0] ?? null;
              setFile(next);
              setPreview(next);
            }}
          />
        </div>
        <label className="block">
          <span className={captionClass} style={captionStyle}>{t("cleaningPointInstruction")}</span>
          <textarea
            className={`${inputClass} mt-1 min-h-20`}
            style={inputStyle}
            value={instruction}
            maxLength={500}
            placeholder={t("cleaningPointInstructionHint")}
            data-testid="cleaning-point-instruction"
            onChange={(event) => setInstruction(event.target.value)}
          />
        </label>
      </div>
    </Dialog>
  );
}

/** A preview URL for a picked file, revoked when replaced or on unmount. */
function useObjectUrl(): [string | null, (file: File | null) => void] {
  const [url, setUrl] = useState<string | null>(null);
  const current = useRef<string | null>(null);
  useEffect(() => () => {
    if (current.current) URL.revokeObjectURL(current.current);
  }, []);
  const set = (file: File | null) => {
    if (current.current) URL.revokeObjectURL(current.current);
    current.current = file ? URL.createObjectURL(file) : null;
    setUrl(current.current);
  };
  return [url, set];
}
