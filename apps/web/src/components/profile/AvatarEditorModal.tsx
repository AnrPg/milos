"use client";

import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { canvasToAvatarFile, drawAvatarCrop } from "@/components/profile/avatar-crop";

type Props = {
  file: File;
  pending: boolean;
  uploadError?: string | null;
  onCancel: () => void;
  onSave: (file: File) => Promise<void>;
};

export function AvatarEditorModal({ file, pending, uploadError, onCancel, onSave }: Props) {
  const tCommon = useTranslations("Common");
  const tProfile = useTranslations("Profile");
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  const [zoom, setZoom] = useState(1);
  const [horizontal, setHorizontal] = useState(0);
  const [vertical, setVertical] = useState(0);
  const [rotation, setRotation] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const nextImage = new Image();
    const reader = new FileReader();

    nextImage.onload = () => {
      if (!cancelled) setImage(nextImage);
    };
    nextImage.onerror = () => {
      if (!cancelled) setError(tProfile("avatarReadError"));
    };
    reader.onload = () => {
      if (cancelled || typeof reader.result !== "string") return;
      nextImage.src = reader.result;
    };
    reader.onerror = () => {
      if (!cancelled) setError(tProfile("avatarReadError"));
    };
    reader.readAsDataURL(file);

    return () => {
      cancelled = true;
      if (reader.readyState === FileReader.LOADING) reader.abort();
    };
  }, [file, tProfile]);

  useEffect(() => {
    if (image && canvasRef.current) {
      drawAvatarCrop(canvasRef.current, image, zoom, horizontal, vertical, rotation);
    }
  }, [horizontal, image, rotation, vertical, zoom]);

  async function save() {
    if (!canvasRef.current || !image) return;
    setError(null);
    try {
      await onSave(await canvasToAvatarFile(canvasRef.current));
    } catch {
      setError(tProfile("avatarReadError"));
    }
  }

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-black/75 p-4" role="dialog" aria-modal="true" aria-labelledby="avatar-editor-title">
      <div className="flex min-h-full items-center justify-center py-2">
        <div className="max-h-[calc(100vh-2rem)] w-full max-w-lg overflow-y-auto rounded-[2rem] p-6 shadow-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <h2 id="avatar-editor-title" className="text-xl font-bold" style={{ color: "var(--text)" }}>{tProfile("avatarEditorTitle")}</h2>
          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{tProfile("avatarEditorDescription")}</p>

          <div className="mx-auto mt-5 aspect-square w-full max-w-72 overflow-hidden rounded-full sm:max-w-80" style={{ border: "3px solid var(--primary)", background: "var(--bg-soft)" }}>
            <canvas ref={canvasRef} width={512} height={512} className="h-full w-full" aria-label={tProfile("avatarPreviewLabel")} />
          </div>

          <div className="mt-6 space-y-4">
            {[
              [tProfile("avatarZoom"), zoom, 1, 3, 0.05, setZoom],
              [tProfile("avatarHorizontalPosition"), horizontal, -100, 100, 1, setHorizontal],
              [tProfile("avatarVerticalPosition"), vertical, -100, 100, 1, setVertical],
            ].map(([label, value, min, max, step, setter]) => (
              <label key={String(label)} className="block text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>
                {String(label)}
                <input
                  type="range"
                  className="mt-2 w-full accent-[var(--primary)]"
                  value={Number(value)}
                  min={Number(min)}
                  max={Number(max)}
                  step={Number(step)}
                  onChange={(event) => (setter as React.Dispatch<React.SetStateAction<number>>)(Number(event.target.value))}
                />
              </label>
            ))}
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>
                {tProfile("avatarRotation")}
              </p>
              <div className="mt-2 flex gap-2">
                <button
                  type="button"
                  onClick={() => setRotation((value) => (value + 270) % 360)}
                  className="rounded-xl px-4 py-2 text-sm font-semibold"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  title={tProfile("avatarRotateLeft")}
                >
                  ↺ 90°
                </button>
                <button
                  type="button"
                  onClick={() => setRotation((value) => (value + 90) % 360)}
                  className="rounded-xl px-4 py-2 text-sm font-semibold"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  title={tProfile("avatarRotateRight")}
                >
                  ↻ 90°
                </button>
              </div>
            </div>
          </div>

          {error || uploadError ? <p className="mt-4 text-sm font-semibold" style={{ color: "var(--danger)" }}>{error ?? uploadError}</p> : null}
          <div className="mt-6 flex justify-end gap-3">
            <button type="button" disabled={pending} onClick={onCancel} className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>{tCommon("cancel")}</button>
            <button type="button" disabled={pending || !image} onClick={() => void save()} className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>{pending ? tCommon("saving") : tProfile("avatarApply")}</button>
          </div>
        </div>
      </div>
    </div>
  );
}
