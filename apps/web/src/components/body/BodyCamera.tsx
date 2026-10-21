"use client";

import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslations } from "next-intl";

import type { BodyPose } from "@/api/body";
import { key } from "@/components/body/BodyBits";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

const TIMER_SECONDS = 10;

type Facing = "user" | "environment";

/**
 * The in-app camera for one pose (vision §7.7, board 13 q4): full screen,
 * the previous photo of the pose laid over the preview as a ghost (opacity
 * slider) so stance and distance match, a 10-second timer to step back,
 * front/back camera, keep or retake, and «Από τη συλλογή». Nothing leaves
 * the device until the photo is kept.
 */
export function BodyCamera({
  pose,
  ghostUrl,
  onKeep,
  onClose,
}: {
  pose: BodyPose;
  ghostUrl: string | null;
  onKeep: (file: Blob) => void;
  onClose: () => void;
}) {
  const t = useTranslations("Body");
  const titleId = useId();
  const dialog = useModalFocusTrap<HTMLDivElement>(onClose);
  const videoRef = useRef<HTMLVideoElement>(null);
  const galleryRef = useRef<HTMLInputElement>(null);
  const [facing, setFacing] = useState<Facing>("user");
  const [cameraError, setCameraError] = useState(false);
  const [ghostOpacity, setGhostOpacity] = useState(40);
  const [timerOn, setTimerOn] = useState(true);
  const [countdown, setCountdown] = useState<number | null>(null);
  const [shot, setShot] = useState<{ blob: Blob; url: string } | null>(null);
  const poseLabel = t(key("pose", pose));

  // Start (or restart) the camera; stop it when switching, keeping a shot, or closing.
  useEffect(() => {
    if (shot) return;
    let stream: MediaStream | null = null;
    let cancelled = false;
    const media = typeof navigator !== "undefined" ? navigator.mediaDevices : undefined;
    if (!media?.getUserMedia) {
      queueMicrotask(() => setCameraError(true));
      return;
    }
    media
      .getUserMedia({ video: { facingMode: facing, width: { ideal: 1920 }, height: { ideal: 1440 } }, audio: false })
      .then((opened) => {
        if (cancelled) {
          opened.getTracks().forEach((track) => track.stop());
          return;
        }
        stream = opened;
        setCameraError(false);
        const video = videoRef.current;
        if (video) {
          video.srcObject = opened;
          void video.play().catch(() => undefined);
        }
      })
      .catch(() => {
        if (!cancelled) setCameraError(true);
      });
    return () => {
      cancelled = true;
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, [facing, shot]);

  // The countdown ticks once a second, then takes the photo.
  useEffect(() => {
    if (countdown === null) return;
    if (countdown === 0) {
      queueMicrotask(() => {
        setCountdown(null);
        capture();
      });
      return;
    }
    const timer = window.setTimeout(() => setCountdown((value) => (value === null ? null : value - 1)), 1000);
    return () => window.clearTimeout(timer);
  }, [countdown]);

  useEffect(() => () => {
    if (shot) URL.revokeObjectURL(shot.url);
  }, [shot]);

  function capture() {
    const video = videoRef.current;
    if (!video || !video.videoWidth) return;
    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(
      (blob) => {
        if (blob) setShot({ blob, url: URL.createObjectURL(blob) });
      },
      "image/jpeg",
      0.92,
    );
  }

  function shutter() {
    if (countdown !== null) {
      setCountdown(null);
      return;
    }
    if (timerOn) setCountdown(TIMER_SECONDS);
    else capture();
  }

  const mirrored = facing === "user";
  const light = { color: "var(--on-media)" };
  const control = { className: "inline-flex min-h-11 items-center justify-center gap-1.5 rounded-full px-3 text-sm font-semibold" };
  const controlStyle = { background: "var(--media-control)", color: "var(--on-media)", border: "1px solid var(--media-control-border)" };

  return createPortal(
    <div
      ref={dialog}
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-[80] flex flex-col"
      style={{ background: "var(--media)" }}
      data-testid="body-camera"
    >
      <div className="flex items-center justify-between gap-2 px-3 pt-3" style={{ paddingTop: "calc(0.75rem + env(safe-area-inset-top))" }}>
        <h2 id={titleId} className="text-base font-bold" style={light}>{t("cameraTitle", { pose: poseLabel })}</h2>
        <button type="button" onClick={onClose} className={control.className} style={controlStyle}>{t("close")}</button>
      </div>

      <div className="relative min-h-0 flex-1 overflow-hidden">
        {shot ? (
          // eslint-disable-next-line @next/next/no-img-element -- a local object URL
          <img src={shot.url} alt={t("cameraPreviewAlt", { pose: poseLabel })} className="h-full w-full object-contain" />
        ) : (
          <>
            <video
              ref={videoRef}
              playsInline
              muted
              className="h-full w-full object-cover"
              style={mirrored ? { transform: "scaleX(-1)" } : undefined}
              aria-label={t("cameraPreview")}
            />
            {ghostUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- short-lived presigned URL of the previous photo
              <img
                src={ghostUrl}
                alt=""
                aria-hidden="true"
                className="pointer-events-none absolute inset-0 h-full w-full object-cover"
                style={{ opacity: ghostOpacity / 100, transform: mirrored ? "scaleX(-1)" : undefined }}
                data-testid="camera-ghost"
              />
            ) : null}
            {cameraError ? (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 p-6 text-center" style={light}>
                <p className="text-sm">{t("cameraUnavailable")}</p>
              </div>
            ) : null}
            {countdown !== null ? (
              <div className="pointer-events-none absolute inset-0 flex items-center justify-center" aria-live="assertive">
                <span className="text-7xl font-extrabold tabular-nums" style={{ ...light, textShadow: "var(--shadow-md)" }}>{countdown}</span>
              </div>
            ) : null}
          </>
        )}
      </div>

      <div className="flex flex-col gap-3 px-4 pb-4 pt-3" style={{ paddingBottom: "calc(1rem + env(safe-area-inset-bottom))" }}>
        {shot ? (
          <div className="flex gap-2">
            <button type="button" onClick={() => setShot(null)} className={[control.className, "flex-1"].join(" ")} style={controlStyle}>
              {t("retake")}
            </button>
            <button
              type="button"
              onClick={() => onKeep(shot.blob)}
              className={[control.className, "flex-1"].join(" ")}
              style={{ background: "var(--primary)", color: "var(--bg)" }}
            >
              {t("keep")}
            </button>
          </div>
        ) : (
          <>
            {ghostUrl && !cameraError ? (
              <label className="flex items-center gap-3 text-xs" style={light}>
                <span className="shrink-0">{t("ghostOpacity")}</span>
                <input
                  type="range"
                  min={0}
                  max={80}
                  value={ghostOpacity}
                  onChange={(event) => setGhostOpacity(Number(event.target.value))}
                  className="flex-1"
                />
              </label>
            ) : null}
            <div className="flex items-center justify-between gap-2">
              <button type="button" onClick={() => galleryRef.current?.click()} className={control.className} style={controlStyle}>
                {t("fromGallery")}
              </button>
              <button
                type="button"
                onClick={shutter}
                disabled={cameraError}
                aria-label={countdown !== null ? t("cancelTimer") : t("takePhoto")}
                className="h-16 w-16 shrink-0 rounded-full disabled:opacity-40"
                style={{ border: "4px solid var(--on-media)", background: countdown !== null ? "var(--media-control-border)" : "transparent" }}
              />
              <div className="flex gap-2">
                <button
                  type="button"
                  aria-pressed={timerOn}
                  onClick={() => setTimerOn((value) => !value)}
                  className={control.className}
                  style={controlStyle}
                >
                  {timerOn ? t("timerOn", { seconds: TIMER_SECONDS }) : t("timerOff")}
                </button>
                <button
                  type="button"
                  onClick={() => setFacing((value) => (value === "user" ? "environment" : "user"))}
                  aria-label={t("switchCamera")}
                  className={control.className}
                  style={controlStyle}
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
                    <path d="M4 7h3l2-2h6l2 2h3v12H4z" />
                    <path d="M9 13a3 3 0 0 0 5.2 2M15 12a3 3 0 0 0-5.2-2" />
                  </svg>
                </button>
              </div>
            </div>
          </>
        )}
        <input
          ref={galleryRef}
          type="file"
          accept="image/*"
          className="hidden"
          data-testid="body-gallery-input"
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (file) onKeep(file);
          }}
        />
      </div>
    </div>,
    document.body,
  );
}
