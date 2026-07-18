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
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const url = URL.createObjectURL(file);
    const nextImage = new Image();
    nextImage.onload = () => setImage(nextImage);
    nextImage.onerror = () => setError(tProfile("avatarReadError"));
    nextImage.src = url;
    return () => URL.revokeObjectURL(url);
  }, [file, tProfile]);

  useEffect(() => {
    if (image && canvasRef.current) {
      drawAvatarCrop(canvasRef.current, image, zoom, horizontal, vertical);
    }
  }, [horizontal, image, vertical, zoom]);

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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4" role="dialog" aria-modal="true" aria-labelledby="avatar-editor-title">
      <div className="w-full max-w-lg rounded-[2rem] p-6 shadow-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <h2 id="avatar-editor-title" className="text-xl font-bold" style={{ color: "var(--text)" }}>{tProfile("avatarEditorTitle")}</h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{tProfile("avatarEditorDescription")}</p>

        <div className="mx-auto mt-5 aspect-square w-full max-w-80 overflow-hidden rounded-full" style={{ border: "3px solid var(--primary)", background: "var(--bg-soft)" }}>
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
        </div>

        {error || uploadError ? <p className="mt-4 text-sm font-semibold" style={{ color: "var(--danger)" }}>{error ?? uploadError}</p> : null}
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" disabled={pending} onClick={onCancel} className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>{tCommon("cancel")}</button>
          <button type="button" disabled={pending || !image} onClick={() => void save()} className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>{pending ? tCommon("saving") : tProfile("avatarApply")}</button>
        </div>
      </div>
    </div>
  );
}
