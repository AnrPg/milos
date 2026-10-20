"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { deskCheckIn, revokeMemberCode, scanMemberCode, type DeskResult } from "@/api/check-in";

import { parseScannedCode, shouldAutoCheckIn } from "./check-in";
import { ConfirmButton } from "./ConfirmButton";
import { checkInErrorKey } from "./errors";
import { CameraError, scannerSource, type StopScanner } from "./scanner";

const AUTO_KEY = "milos:desk-auto-check-in";
const SAME_CODE_MS = 4_000;

function readAuto() {
  try {
    return window.localStorage.getItem(AUTO_KEY) === "1";
  } catch {
    return false;
  }
}

function storeAuto(on: boolean) {
  try {
    window.localStorage.setItem(AUTO_KEY, on ? "1" : "0");
  } catch {
    // A per-device convenience.
  }
}

/**
 * «Σάρωση» at the desk (ADR-155 §7): the camera reads a member's QR (from the
 * app or a Wallet card) and the desk sees who it is, their bookings, package,
 * problems and warnings. In auto mode (remembered on this device) a scan
 * that is all fine checks in by itself; anything else waits for staff.
 * «Check-in παρ' όλα αυτά» shows only when the owner allows it. The camera
 * is asked for only when staff tap «Σάρωση».
 */
export function DeskScanner({ token, locationId }: { token: string; locationId: string }) {
  const t = useTranslations("CheckIn");
  const queryClient = useQueryClient();
  const videoRef = useRef<HTMLVideoElement>(null);
  const stopRef = useRef<StopScanner | null>(null);
  const lastRef = useRef<{ code: string; at: number } | null>(null);
  const busyRef = useRef(false);
  const [scanning, setScanning] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [auto, setAuto] = useState(false);
  const [result, setResult] = useState<DeskResult | null>(null);
  const [message, setMessage] = useState<{ tone: "ok" | "error" | "info"; text: string } | null>(null);
  const [manual, setManual] = useState("");

  useEffect(() => {
    const timer = window.setTimeout(() => setAuto(readAuto()), 0);
    return () => window.clearTimeout(timer);
  }, []);

  const refreshLists = useCallback(() => queryClient.invalidateQueries({ queryKey: ["admin", "check-ins"] }), [queryClient]);

  const scan = useMutation({
    mutationFn: (code: string) => scanMemberCode(token, { code, auto, ...(locationId ? { location_id: locationId } : {}) }),
    onMutate: () => {
      busyRef.current = true;
      setMessage(null);
    },
    onSuccess: (data) => {
      setResult(data);
      if (data.checked_in) void refreshLists();
    },
    onError: (error) => {
      setResult(null);
      setMessage({ tone: "error", text: t(checkInErrorKey(error)) });
    },
    onSettled: () => {
      busyRef.current = false;
    },
  });

  const checkIn = useMutation({
    mutationFn: (options: { bookingId?: string; override?: boolean }) =>
      deskCheckIn(token, result!.member.id, {
        method: result!.method ?? "member_qr",
        ...(options.bookingId ? { booking_id: options.bookingId } : {}),
        ...(locationId ? { location_id: locationId } : {}),
        ...(options.override ? { override: true } : {}),
      }),
    onSuccess: (data) => {
      setResult(data);
      void refreshLists();
    },
    onError: (error) => setMessage({ tone: "error", text: t(checkInErrorKey(error)) }),
  });

  const revoke = useMutation({
    mutationFn: () => revokeMemberCode(token, result!.member.id),
    onSuccess: (data) => setMessage({ tone: "ok", text: t("deskRevoked", { passes: data.revoked_passes }) }),
    onError: (error) => setMessage({ tone: "error", text: t(checkInErrorKey(error)) }),
  });

  const handleText = useCallback(
    (raw: string) => {
      const parsed = parseScannedCode(raw);
      if (parsed.kind === "door") {
        setMessage({ tone: "info", text: t("deskDoorCode") });
        return;
      }
      if (parsed.kind === "unknown") {
        setMessage({ tone: "info", text: t("deskUnknownCode") });
        return;
      }
      const now = Date.now();
      // The camera sees the same code many times a second: one scan per code, then a pause.
      if (busyRef.current || (lastRef.current && lastRef.current.code === parsed.code && now - lastRef.current.at < SAME_CODE_MS)) return;
      lastRef.current = { code: parsed.code, at: now };
      scan.mutate(parsed.code);
    },
    [scan, t],
  );

  const stop = useCallback(() => {
    stopRef.current?.();
    stopRef.current = null;
    setScanning(false);
  }, []);

  async function start() {
    setCameraError(null);
    setMessage(null);
    const video = videoRef.current;
    if (!video) return;
    try {
      stopRef.current = await scannerSource().start(video, (text) => handleRef.current(text));
      setScanning(true);
    } catch (error) {
      const reason = error instanceof CameraError ? error.reason : "failed";
      setCameraError(t(["camera", reason].join("_")));
    }
  }

  // The latest handler for a running camera, and the camera off when leaving the desk.
  const handleRef = useRef(handleText);
  useEffect(() => {
    handleRef.current = handleText;
  }, [handleText]);
  useEffect(() => () => stopRef.current?.(), []);

  // Auto mode: a scan that's all fine checks in by itself. The API does it when `auto` is
  // sent; if it answered without checking in although it could, the desk finishes it once.
  const autoHandled = useRef<DeskResult | null>(null);
  useEffect(() => {
    if (!result || autoHandled.current === result || !shouldAutoCheckIn(result, auto)) return;
    autoHandled.current = result;
    checkIn.mutate({ bookingId: result.decision === "class" && result.bookings?.length === 1 ? result.bookings[0].id : undefined });
  }, [auto, checkIn, result]);

  function toggleAuto(on: boolean) {
    setAuto(on);
    storeAuto(on);
  }

  return (
    <section className="space-y-4 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-labelledby="desk-scan-title" data-testid="desk-scanner">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="desk-scan-title" className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("deskScanTitle")}</h2>
        <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
          <input type="checkbox" role="switch" checked={auto} onChange={(event) => toggleAuto(event.target.checked)} className="h-5 w-5" />
          {t("deskAuto")}
        </label>
      </div>
      <p className="text-sm" style={{ color: "var(--muted)" }}>{auto ? t("deskAutoOnHint") : t("deskAutoOffHint")}</p>

      <div className="relative overflow-hidden rounded-2xl" style={{ background: "#000", display: scanning ? "block" : "none" }}>
        <video ref={videoRef} className="aspect-video w-full object-cover" muted playsInline aria-label={t("deskCameraLabel")} />
        <span aria-hidden="true" className="pointer-events-none absolute inset-[18%] rounded-2xl border-4" style={{ borderColor: "rgba(255,255,255,0.75)" }} />
      </div>

      <div className="flex flex-wrap gap-2">
        {scanning ? (
          <button type="button" onClick={stop} className="min-h-11 rounded-full px-5 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("deskStop")}
          </button>
        ) : (
          <button type="button" onClick={() => void start()} className="min-h-11 rounded-full px-5 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} data-testid="desk-scan-start">
            {t("deskScan")}
          </button>
        )}
        <form
          className="flex min-w-0 flex-1 gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            if (manual.trim()) {
              lastRef.current = null;
              handleText(manual);
              setManual("");
            }
          }}
        >
          <input
            value={manual}
            onChange={(event) => setManual(event.target.value)}
            aria-label={t("deskManualLabel")}
            placeholder={t("deskManualPlaceholder")}
            className="min-h-11 min-w-0 flex-1 rounded-xl px-3 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
            autoComplete="off"
            spellCheck={false}
          />
          <button type="submit" disabled={!manual.trim()} className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("deskManualGo")}
          </button>
        </form>
      </div>

      {cameraError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{cameraError}</p> : null}
      {scan.isPending ? <p role="status" className="text-sm" style={{ color: "var(--muted)" }}>{t("deskChecking")}</p> : null}
      {message ? (
        <p role={message.tone === "error" ? "alert" : "status"} className="text-sm font-semibold" style={{ color: message.tone === "error" ? "var(--danger)" : message.tone === "ok" ? "var(--success)" : "var(--muted)" }}>
          {message.text}
        </p>
      ) : null}

      {result ? (
        <DeskResultCard
          result={result}
          autoWaiting={auto && !result.checked_in && !result.can_auto_check_in}
          busy={checkIn.isPending}
          onCheckIn={(options) => checkIn.mutate(options)}
          revoking={revoke.isPending}
          onRevoke={() => revoke.mutate()}
          onNext={() => {
            setResult(null);
            setMessage(null);
            lastRef.current = null;
          }}
        />
      ) : null}
    </section>
  );
}

function DeskResultCard({
  result,
  autoWaiting,
  busy,
  onCheckIn,
  revoking,
  onRevoke,
  onNext,
}: {
  result: DeskResult;
  autoWaiting: boolean;
  busy: boolean;
  onCheckIn: (options: { bookingId?: string; override?: boolean }) => void;
  revoking: boolean;
  onRevoke: () => void;
  onNext: () => void;
}) {
  const t = useTranslations("CheckIn");
  const locale = useLocale();
  const clock = (iso: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const date = (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(new Date(iso));
  const name = result.member.display_name || result.member.nickname || "";
  const bookings = result.bookings ?? [];
  const problems = result.problems ?? [];
  const warnings = result.warnings ?? [];
  const pkg = result.package;
  const canCheckIn = !result.checked_in && problems.length === 0 && ["class", "open_gym"].includes(result.decision);
  const done = result.checked_in;

  return (
    <article
      className="space-y-3 rounded-[1.5rem] p-4"
      style={{
        background: done ? "color-mix(in srgb, var(--success, #22c55e) 12%, var(--panel-muted))" : "var(--panel-muted)",
        border: `1px solid ${done ? "var(--success, #22c55e)" : problems.length ? "var(--danger)" : "var(--border)"}`,
      }}
      data-testid="desk-result"
      aria-live="polite"
    >
      <div className="flex items-center gap-3">
        {result.member.avatar_url ? (
          // eslint-disable-next-line @next/next/no-img-element -- member photo from the media origin
          <img src={result.member.avatar_url} alt="" className="h-16 w-16 shrink-0 rounded-full object-cover" />
        ) : (
          <span aria-hidden="true" className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full text-xl font-extrabold" style={{ background: "var(--primary)", color: "var(--bg)" }}>
            {name.slice(0, 2).toUpperCase() || "?"}
          </span>
        )}
        <div className="min-w-0">
          <p className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>{name}</p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t(["deskMethod", result.method ?? "member_qr"].join("_"))}</p>
        </div>
      </div>

      {done ? (
        <p className="text-base font-bold" style={{ color: "var(--success, #22c55e)" }} data-testid="desk-checked-in">
          {done.kind === "class" && done.booking
            ? t("deskCheckedInClass", { name: done.booking.name ?? "", time: clock(done.booking.starts_at) })
            : t("deskCheckedInOpenGym")}
          {done.override ? ` · ${t("deskOverrideMark")}` : ""}
        </p>
      ) : result.already_checked_in ? (
        <p className="text-sm font-semibold" style={{ color: "var(--muted)" }}>{t("deskAlready")}</p>
      ) : null}

      {bookings.length > 0 ? (
        <ul className="space-y-1">
          {bookings.map((booking) => (
            <li key={booking.id} className="flex items-center justify-between gap-3 text-sm" style={{ color: "var(--text)" }}>
              <span>{[booking.name, clock(booking.starts_at)].filter(Boolean).join(" · ")}</span>
              {!done && result.decision === "choose" ? (
                <button type="button" disabled={busy} onClick={() => onCheckIn({ bookingId: booking.id })} className="min-h-10 rounded-full px-4 text-xs font-bold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                  {t("deskCheckInThis")}
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      ) : result.decision === "open_gym" && !done ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("deskOpenGym")}</p>
      ) : null}

      {pkg?.name ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {[
            pkg.name,
            pkg.unlimited ? t("packageUnlimited") : typeof pkg.class_visits_left === "number" ? t("packageVisitsLeft", { count: pkg.class_visits_left }) : null,
            pkg.expires_on ? t("packageUntil", { date: date(pkg.expires_on) }) : null,
            pkg.frozen_until ? t("packageFrozenUntil", { date: date(pkg.frozen_until) }) : null,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
      ) : (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("deskNoPackage")}</p>
      )}

      {problems.length > 0 || warnings.length > 0 ? (
        <ul className="flex flex-wrap gap-2" aria-label={t("deskProblems")}>
          {problems.map((problem) => (
            <li key={problem} className="rounded-full px-3 py-1 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--danger) 16%, transparent)", color: "var(--danger)" }}>
              {t(["problem", problem].join("_"))}
            </li>
          ))}
          {warnings.map((warning) => (
            <li key={warning} className="rounded-full px-3 py-1 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--warning, #f59e0b) 18%, transparent)", color: "var(--text)" }}>
              {t(["warning", warning].join("_"))}
            </li>
          ))}
        </ul>
      ) : null}

      {autoWaiting ? <p className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("deskAutoStopped")}</p> : null}

      <div className="flex flex-wrap gap-2">
        {canCheckIn ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onCheckIn({ bookingId: result.decision === "class" && bookings.length === 1 ? bookings[0].id : undefined })}
            className="min-h-11 rounded-full px-5 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            data-testid="desk-check-in"
          >
            {t("deskCheckIn")}
          </button>
        ) : null}
        {!done && problems.length > 0 && result.override_allowed ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onCheckIn({ bookingId: bookings.length === 1 ? bookings[0].id : undefined, override: true })}
            className="min-h-11 rounded-full px-5 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--danger, #dc2626)", color: "#fff" }}
            data-testid="desk-override"
          >
            {t("deskOverride")}
          </button>
        ) : null}
        <button type="button" onClick={onNext} className="min-h-11 rounded-full px-5 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {t("deskNext")}
        </button>
        <ConfirmButton
          label={t("deskRevoke")}
          question={t("deskRevokeConfirm", { name })}
          confirmLabel={t("deskRevokeAction")}
          pending={revoking}
          onConfirm={onRevoke}
        />
      </div>
    </article>
  );
}
