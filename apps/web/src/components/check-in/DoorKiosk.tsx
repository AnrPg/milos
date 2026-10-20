"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { fetchDoorDisplay, type DoorDisplay } from "@/api/check-in";
import { useSession } from "@/components/session-provider";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { subscribeToTopic } from "@/lib/realtime";
import { playCue, primeCueAudio } from "@/lib/timer-cues";

import { clockOffset, countdownLabel, doorFrame, doorRefetchDelay } from "./check-in";
import { QrCode } from "./QrCode";
import { useOnline } from "./use-online";

type Loaded = { display: DoorDisplay; offset: number };
type Welcome = { id: number; name: string | null };

const WELCOME_MS = 6_000;

/**
 * «Οθόνη πόρτας» (ADR-155, board 10 Q1): a kiosk at the box's door showing a
 * QR that rotates every 15–60 s. It rotates from the offline batch, so a
 * short network drop doesn't stop it, and fetches the next batch before this
 * one runs out. Each check-in here greets the person by first name with a
 * green flash, and a chime once staff have tapped «Ενεργοποίηση ήχου»
 * (browsers block sound until someone taps). The screen stays awake.
 */
export function DoorKiosk({ locationId }: { locationId: string }) {
  const t = useTranslations("CheckIn");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const { membership } = useSelectedMembershipRole();
  const online = useOnline();
  const rootRef = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  // Failed fetches in a row: each one reschedules the next try.
  const [failures, setFailures] = useState(0);
  const failed = failures > 0;
  const [notFound, setNotFound] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  const [soundOn, setSoundOn] = useState(false);
  const soundRef = useRef(false);
  const [welcome, setWelcome] = useState<Welcome | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);

  useScreenWakeLock(true);

  const load = useCallback(async () => {
    if (!token) return;
    try {
      const display = await fetchDoorDisplay(token, locationId);
      setLoaded({ display, offset: clockOffset(display.server_time, Date.now()) });
      setFailures(0);
      setNow(Date.now());
    } catch (error) {
      if ((error as { status?: number }).status === 404) setNotFound(true);
      setFailures((count) => count + 1);
    }
  }, [locationId, token]);

  // First load, and again whenever the network comes back.
  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load, online]);

  // The clock: once a second for the countdown.
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);

  const rotation = loaded?.display.rotation_seconds ?? 30;
  const serverNow = now + (loaded?.offset ?? 0);
  const frame = doorFrame(loaded?.display.codes ?? [], serverNow, rotation);

  // The next batch, before this one runs out (sooner after a failure).
  const batchEndsAt = frame.batchEndsAt;
  useEffect(() => {
    if (!loaded || notFound) return;
    const current = Date.now() + loaded.offset;
    const delay = doorRefetchDelay(batchEndsAt, current, rotation, failed);
    const timer = window.setTimeout(() => void load(), delay);
    return () => window.clearTimeout(timer);
  }, [loaded, batchEndsAt, failed, failures, notFound, rotation, load]);

  // Live check-ins at this door: the welcome line, the flash and the chime.
  const topic = loaded?.display.topic ?? null;
  useEffect(() => {
    if (!token || !topic) return;
    let counter = 0;
    let clear: number | undefined;
    const leave = subscribeToTopic(token, topic, {
      checked_in: (payload) => {
        const event = payload as { location_id?: string | null; first_name?: string | null };
        if (event.location_id && event.location_id !== locationId) return;
        counter += 1;
        setWelcome({ id: counter, name: event.first_name ?? null });
        if (soundRef.current) playCue("work", "sound");
        window.clearTimeout(clear);
        clear = window.setTimeout(() => setWelcome(null), WELCOME_MS);
      },
    });
    return () => {
      window.clearTimeout(clear);
      leave();
    };
  }, [locationId, token, topic]);

  useEffect(() => {
    const sync = () => setFullscreen(Boolean(document.fullscreenElement));
    const timer = window.setTimeout(() => setCanFullscreen(Boolean(document.fullscreenEnabled)), 0);
    document.addEventListener("fullscreenchange", sync);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("fullscreenchange", sync);
    };
  }, []);

  function enableSound() {
    primeCueAudio();
    soundRef.current = true;
    setSoundOn(true);
  }

  function toggleFullscreen() {
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined);
    else void rootRef.current?.requestFullscreen?.().catch(() => undefined);
  }

  const boxName = membership?.settings?.brand_name?.trim() || membership?.organization.name || "";
  const logo = membership?.settings?.brand_logo_url ?? null;
  const clock = (iso: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const offline = failed || !online;
  const nextClass = loaded?.display.next_class ?? null;
  const minutesLeft = batchEndsAt ? Math.max(0, Math.ceil((batchEndsAt - serverNow) / 60_000)) : 0;

  if (notFound) {
    return (
      <main className="flex min-h-dvh flex-col items-center justify-center gap-4 p-8 text-center" style={{ background: "var(--bg)" }}>
        <p className="text-lg" style={{ color: "var(--text)" }}>{t("doorNotFound")}</p>
        <Link href={adminHref("/admin/check-in", slug)} className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
          {t("backToDesk")}
        </Link>
      </main>
    );
  }

  return (
    <div
      ref={rootRef}
      className="relative flex min-h-dvh flex-col overflow-hidden"
      data-testid="door-kiosk"
      style={{ background: welcome ? "color-mix(in srgb, var(--success, #22c55e) 22%, var(--bg))" : "var(--bg)", color: "var(--text)", transition: "background 300ms" }}
    >
      {welcome ? <div key={welcome.id} aria-hidden="true" className="checkin-flash pointer-events-none absolute inset-0" /> : null}

      <header className="flex items-center justify-between gap-4 p-[3vmin]">
        <div className="flex min-w-0 items-center gap-3">
          {logo ? (
            // eslint-disable-next-line @next/next/no-img-element -- the box's uploaded logo, from the media origin
            <img src={logo} alt="" className="h-[7vmin] max-h-16 w-auto rounded-xl object-contain" />
          ) : null}
          <div className="min-w-0">
            <p className="truncate font-black" style={{ fontSize: "clamp(1.1rem, 3.6vmin, 2.6rem)" }}>{boxName}</p>
            {loaded ? <p className="truncate text-sm" style={{ color: "var(--muted)" }}>{loaded.display.location.name}</p> : null}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {soundOn ? (
            <span className="rounded-full px-3 py-1.5 text-xs font-bold" style={{ color: "var(--success, #22c55e)", border: "1px solid currentColor" }}>
              {t("soundOn")}
            </span>
          ) : (
            <button type="button" onClick={enableSound} className="min-h-11 rounded-full px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--bg)" }}>
              {t("enableSound")}
            </button>
          )}
          {canFullscreen ? (
            <button
              type="button"
              onClick={toggleFullscreen}
              className="min-h-11 rounded-full px-4 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {fullscreen ? t("exitFullscreen") : t("fullscreen")}
            </button>
          ) : null}
        </div>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center gap-[4vmin] px-[4vmin] pb-[4vmin] landscape:flex-row">
        <section className="flex flex-col items-center gap-3">
          {frame.current ? (
            <QrCode
              value={frame.current.deep_link}
              label={t("doorQrLabel")}
              testId="door-qr"
              className="h-[min(70vmin,34rem)] w-[min(70vmin,34rem)] p-[1.5vmin]"
            />
          ) : (
            <div
              className="flex h-[min(70vmin,34rem)] w-[min(70vmin,34rem)] items-center justify-center rounded-3xl p-6 text-center text-lg"
              style={{ border: "2px dashed var(--border)", color: "var(--muted)" }}
              data-testid="door-qr-waiting"
            >
              {loaded ? t("doorWaiting") : t("loading")}
            </div>
          )}
          {frame.current && frame.secondsUntilRotation > 0 ? (
            <p className="font-mono text-sm" style={{ color: "var(--muted)" }} data-testid="door-countdown" aria-hidden="true">
              {t("doorRotatesIn", { time: countdownLabel(frame.secondsUntilRotation) })}
            </p>
          ) : null}
        </section>

        <section className="flex max-w-xl flex-col gap-[3vmin] text-center landscape:text-start">
          <div aria-live="polite" className="min-h-[4.5rem]">
            {welcome ? (
              <p className="font-black" style={{ fontSize: "clamp(1.8rem, 6vmin, 4.5rem)", color: "var(--success, #22c55e)" }} data-testid="door-welcome">
                {welcome.name ? t("welcome", { name: welcome.name }) : t("welcomeAnon")}
              </p>
            ) : (
              <p className="font-extrabold" style={{ fontSize: "clamp(1.4rem, 4.6vmin, 3.2rem)" }}>{t("doorScanHint")}</p>
            )}
          </div>

          {nextClass ? (
            <div className="rounded-3xl p-[2.5vmin]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("doorNextClass")}</p>
              <p className="font-extrabold" style={{ fontSize: "clamp(1.2rem, 3.6vmin, 2.4rem)" }}>
                {clock(nextClass.starts_at)} · {nextClass.name ?? ""}
              </p>
              {typeof nextClass.spots_remaining === "number" ? (
                <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("spotsLeft", { count: nextClass.spots_remaining })}</p>
              ) : null}
            </div>
          ) : null}

          {offline ? (
            <p role="status" className="rounded-2xl px-4 py-3 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--warning, #f59e0b) 16%, transparent)", color: "var(--text)" }} data-testid="door-offline">
              {frame.current ? t("doorOffline", { minutes: minutesLeft }) : t("doorOfflineOut")}
            </p>
          ) : null}
        </section>
      </main>
    </div>
  );
}
