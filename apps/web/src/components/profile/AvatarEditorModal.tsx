"use client";

import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { useTranslations } from "next-intl";

import { useHideBottomNav } from "@/components/nav/bottom-nav-visibility";
import { canvasToAvatarFile, drawAvatar, loadAvatarImage, type AvatarImage } from "@/components/profile/avatar-crop";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import {
  AVATAR_MAX_ZOOM,
  AVATAR_MIN_ZOOM,
  IDENTITY_TRANSFORM,
  axisMovability,
  panBy,
  panToSlider,
  rotateTo,
  sliderToPan,
  zoomTo,
  type AvatarTransform,
} from "@/lib/avatar-crop";

type Props = {
  /** A freshly picked file, or the URL of the current avatar to re-edit. */
  source: File | string;
  pending: boolean;
  uploadError?: string | null;
  onCancel: () => void;
  onSave: (file: File) => Promise<void>;
};

export function AvatarEditorModal({ source, pending, uploadError, onCancel, onSave }: Props) {
  // A focused flow: the member app's bottom bar steps aside (ui/Dialog does too).
  useHideBottomNav();
  const tCommon = useTranslations("Common");
  const tProfile = useTranslations("Profile");
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [image, setImage] = useState<AvatarImage | null>(null);
  const [transform, setTransform] = useState<AvatarTransform>(IDENTITY_TRANSFORM);
  const [error, setError] = useState<string | null>(null);
  const gestures = useCropGestures({
    onPan: (dx, dy) => image && setTransform((current) => panBy(image, current, dx, dy)),
    onZoom: (factor) => image && setTransform((current) => zoomTo(image, current, current.zoom * factor)),
  });

  useEffect(() => {
    // The parent mounts one editor per source, so there is no stale image to clear.
    const controller = new AbortController();
    loadAvatarImage(source, controller.signal)
      .then((next) => {
        if (controller.signal.aborted) return;
        setError(null);
        setTransform(IDENTITY_TRANSFORM);
        setImage(next);
      })
      .catch(() => {
        if (!controller.signal.aborted) setError(tProfile(typeof source === "string" ? "avatarLoadError" : "avatarReadError"));
      });
    return () => controller.abort();
  }, [source, tProfile]);

  useEffect(() => {
    if (image && canvasRef.current) drawAvatar(canvasRef.current, image, transform);
  }, [image, transform]);

  async function save() {
    if (!canvasRef.current || !image) return;
    setError(null);
    try {
      await onSave(await canvasToAvatarFile(canvasRef.current));
    } catch {
      setError(tProfile("avatarReadError"));
    }
  }

  const update = (next: (image: AvatarImage) => AvatarTransform) => image && setTransform(next(image));
  const movable = image ? axisMovability(image, transform) : { x: false, y: false };
  const ready = image !== null;

  return (
    <Dialog
      onClose={onCancel}
      dismissible={!pending}
      title={tProfile("avatarEditorTitle")}
      titleId="avatar-editor-title"
      description={<span className="[@media(max-height:480px)]:hidden">{tProfile("avatarEditorDescription")}</span>}
      size="xl"
      variant="center"
      plainBody
      panelClassName="h-full max-h-[46rem]"
      testId="avatar-editor"
      footer={
        <>
          <DialogButton disabled={pending} onClick={onCancel}>{tCommon("cancel")}</DialogButton>
          <DialogButton tone="primary" disabled={pending || !ready} onClick={() => void save()}>
            {pending ? tCommon("saving") : tProfile("avatarApply")}
          </DialogButton>
        </>
      }
    >
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto overscroll-contain px-5 pb-4 sm:px-6 [@media(orientation:landscape)_and_(max-height:560px)]:flex-row">
        {/* The crop is the largest square that fits what the controls leave;
            phones held sideways put the controls beside it. */}
        <div className="relative min-h-[7.5rem] min-w-[7.5rem] flex-1" style={{ containerType: "size" }}>
          <div className="absolute inset-0 grid place-items-center">
            <div
              {...gestures}
              data-testid="avatar-crop-area"
              className="relative touch-none select-none overflow-hidden rounded-full"
              style={{
                width: "min(100cqw, 100cqh)",
                height: "min(100cqw, 100cqh)",
                border: "3px solid var(--primary)",
                background: "var(--panel-muted)",
                cursor: movable.x || movable.y ? "grab" : "default",
              }}
            >
              <canvas
                ref={canvasRef}
                width={512}
                height={512}
                className="block h-full w-full"
                role="img"
                aria-label={tProfile("avatarPreviewLabel")}
              />
            </div>
          </div>
        </div>

        <div className="shrink-0 space-y-3 [@media(orientation:landscape)_and_(max-height:560px)]:w-[55%] [@media(orientation:landscape)_and_(max-height:560px)]:overflow-y-auto">
          <div className="grid grid-cols-2 gap-x-4 gap-y-3">
            <RangeField
              label={tProfile("avatarZoom")}
              value={transform.zoom}
              min={AVATAR_MIN_ZOOM}
              max={AVATAR_MAX_ZOOM}
              step={0.01}
              disabled={!ready}
              valueText={`${Math.round(transform.zoom * 100)}%`}
              onChange={(value) => update((img) => zoomTo(img, transform, value))}
            />
            <RangeField
              label={tProfile("avatarRotation")}
              value={Math.round(transform.rotation)}
              min={0}
              max={360}
              step={1}
              disabled={!ready}
              valueText={`${Math.round(transform.rotation)}°`}
              onChange={(value) => update((img) => rotateTo(img, transform, value))}
            />
            <RangeField
              label={tProfile("avatarHorizontalPosition")}
              value={image ? panToSlider(image, transform, "x") : 0}
              min={-100}
              max={100}
              step={1}
              disabled={!movable.x}
              onChange={(value) => update((img) => sliderToPan(img, transform, "x", value))}
            />
            <RangeField
              label={tProfile("avatarVerticalPosition")}
              value={image ? panToSlider(image, transform, "y") : 0}
              min={-100}
              max={100}
              step={1}
              disabled={!movable.y}
              onChange={(value) => update((img) => sliderToPan(img, transform, "y", value))}
            />
          </div>
          <div className="flex flex-wrap gap-2">
            <ToolButton
              label={tProfile("avatarRotateLeft")}
              disabled={!ready}
              onClick={() => update((img) => rotateTo(img, transform, Math.round(transform.rotation) - 90))}
            >
              ↺ 90°
            </ToolButton>
            <ToolButton
              label={tProfile("avatarRotateRight")}
              disabled={!ready}
              onClick={() => update((img) => rotateTo(img, transform, Math.round(transform.rotation) + 90))}
            >
              ↻ 90°
            </ToolButton>
            <ToolButton label={tProfile("avatarReset")} disabled={!ready} onClick={() => setTransform(IDENTITY_TRANSFORM)}>
              {tProfile("avatarReset")}
            </ToolButton>
          </div>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{tProfile("avatarGestureHint")}</p>
          {error || uploadError ? (
            <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{error ?? uploadError}</p>
          ) : null}
        </div>
      </div>
    </Dialog>
  );
}

function RangeField({
  label,
  value,
  min,
  max,
  step,
  disabled,
  valueText,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  disabled: boolean;
  valueText?: string;
  onChange: (value: number) => void;
}) {
  return (
    <label
      className="flex min-w-0 flex-col justify-between text-[0.7rem] font-semibold uppercase tracking-[0.08em]"
      style={{ color: disabled ? "var(--dim)" : "var(--muted)" }}
    >
      <span className="flex items-baseline justify-between gap-2">
        <span className="min-w-0 break-words">{label}</span>
        {valueText ? <span className="shrink-0 tabular-nums normal-case tracking-normal">{valueText}</span> : null}
      </span>
      <input
        type="range"
        className="mt-1.5 block h-6 w-full disabled:cursor-not-allowed"
        style={{ accentColor: disabled ? "var(--muted)" : "var(--primary)", opacity: disabled ? 0.45 : 1 }}
        value={value}
        min={min}
        max={max}
        step={step}
        disabled={disabled}
        aria-disabled={disabled}
        aria-valuetext={valueText}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </label>
  );
}

function ToolButton({ label, disabled, onClick, children }: { label: string; disabled: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
      className="min-h-10 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
      style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
    >
      {children}
    </button>
  );
}

/**
 * Drag to pan and pinch to zoom with pointer events. Deltas are reported in
 * crop-window units (a full-width drag moves by 1), so the maths stays
 * independent of the on-screen size. The sliders remain the accessible path.
 */
function useCropGestures({ onPan, onZoom }: { onPan: (dx: number, dy: number) => void; onZoom: (factor: number) => void }) {
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<number | null>(null);

  function distance() {
    const [a, b] = [...pointers.current.values()];
    return a && b ? Math.hypot(a.x - b.x, a.y - b.y) : null;
  }

  function end(event: ReactPointerEvent<HTMLElement>) {
    pointers.current.delete(event.pointerId);
    pinch.current = distance();
  }

  return {
    onPointerDown(event: ReactPointerEvent<HTMLElement>) {
      event.currentTarget.setPointerCapture?.(event.pointerId);
      pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
      pinch.current = distance();
    },
    onPointerMove(event: ReactPointerEvent<HTMLElement>) {
      const previous = pointers.current.get(event.pointerId);
      if (!previous) return;
      const size = event.currentTarget.clientWidth || 1;
      pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.current.size >= 2) {
        const next = distance();
        if (next && pinch.current) onZoom(next / pinch.current);
        pinch.current = next;
        return;
      }
      onPan((event.clientX - previous.x) / size, (event.clientY - previous.y) / size);
    },
    onPointerUp: end,
    onPointerCancel: end,
  };
}
