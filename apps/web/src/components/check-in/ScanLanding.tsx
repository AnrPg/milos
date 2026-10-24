"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { scanDoor, undoScan, type CheckInBooking, type CheckInClass, type CheckInPackage, type ScanResult, type UndoResult } from "@/api/check-in";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { TrialSheet } from "@/components/trials/TrialSheet";
import { adminHref } from "@/lib/organization-slug";

import { clockOffset, nothingReasonKey, scanBody, scanView, undoSecondsLeft, type ScanSource } from "./check-in";
import { checkInErrorKey } from "./errors";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** A trial without an approval rule books straight away. */
const AUTO_APPROVAL = "auto" as const;

type Source = ScanSource;

/**
 * Where the phone camera lands after scanning the door (`/c/<location>/<code>`)
 * or the printed poster (`/c/<location>/p/<code>`), ADR-155 §3–5. Signed out,
 * the person signs in and comes back here. One scan answers with what
 * happened: checked in (with a minute to undo), pick a booking, already in,
 * nothing to check in to with classes to book, or «not a member yet» with
 * the box's trial classes. The poster only ever checks in to a booking, and
 * so do an NFC door tag (`/c/<location>/n/<code>`) and the store app's
 * arrival reminder (`/c/<location>/g/<token>`), ADR-173.
 */
export function ScanLanding({ locationId, code, source }: { locationId: string; code: string; source: Source }) {
  const t = useTranslations("CheckIn");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [override, setOverride] = useState<{ result: ScanResult; receivedAt: number } | null>(null);
  const [undone, setUndone] = useState<UndoResult | null>(null);

  const scan = useQuery({
    queryKey: ["check-in", "scan", source, locationId, code],
    enabled: Boolean(token),
    // One scan per visit: the answer stays as it was, focus and reconnects don't re-scan.
    staleTime: Infinity,
    gcTime: Infinity,
    retry: false,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
    queryFn: async () => {
      const result = await scanDoor(token!, scanBody(source, locationId, code));
      return { result, receivedAt: Date.now() };
    },
  });

  const choose = useMutation({
    mutationFn: (bookingId: string) => scanDoor(token!, { scan_token: current!.result.scan_token!, booking_id: bookingId }),
    onSuccess: (result) => setOverride({ result, receivedAt: Date.now() }),
  });

  const current = override ?? scan.data ?? null;

  return (
    <main className="mx-auto flex min-h-[70dvh] w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-6" data-testid="scan-landing">
      {!current && (scan.isPending || !token) ? (
        <div role="status" className="flex flex-col items-center gap-3 py-16 text-center">
          <span aria-hidden="true" className="h-10 w-10 animate-spin rounded-full border-4" style={{ borderColor: "var(--border)", borderTopColor: "var(--primary)" }} />
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("scanChecking")}</p>
        </div>
      ) : null}

      {!current && scan.isError ? (
        <Card>
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("scanFailedTitle")}</h1>
          <ErrorNotice>{t(checkInErrorKey(scan.error))}</ErrorNotice>
          <button type="button" onClick={() => void scan.refetch()} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {t("tryAgain")}
          </button>
        </Card>
      ) : null}

      {current && token ? (
        undone ? (
          <Undone result={current.result} undone={undone} />
        ) : (
          <Outcome
            token={token}
            source={source}
            result={current.result}
            receivedAt={current.receivedAt}
            onChoose={(bookingId) => choose.mutate(bookingId)}
            choosing={choose.isPending}
            chooseError={choose.isError ? t(checkInErrorKey(choose.error)) : null}
            onUndone={setUndone}
          />
        )
      ) : null}
    </main>
  );
}

function Outcome({
  token,
  source,
  result,
  receivedAt,
  onChoose,
  choosing,
  chooseError,
  onUndone,
}: {
  token: string;
  source: Source;
  result: ScanResult;
  receivedAt: number;
  onChoose: (bookingId: string) => void;
  choosing: boolean;
  chooseError: string | null;
  onUndone: (undone: UndoResult) => void;
}) {
  const t = useTranslations("CheckIn");
  const view = scanView(result, source);
  const box = result.box;
  const schedule = (slotId?: string) => adminHref(slotId ? `/box/schedule?open_slot=${encodeURIComponent(slotId)}` : "/box/schedule", box.slug);

  switch (view.kind) {
    case "checked_in":
      return <CheckedIn token={token} result={result} receivedAt={receivedAt} onUndone={onUndone} />;
    case "already":
      return (
        <Card tone="success">
          <BoxLine result={result} />
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("scanAlreadyTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}><CheckInLine result={result} /></p>
          <PackageLine pkg={result.package} />
        </Card>
      );
    case "choose":
      return (
        <Card>
          <BoxLine result={result} />
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("scanChooseTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("scanChooseHint")}</p>
          <ul className="flex flex-col gap-2">
            {(result.choices ?? []).map((booking) => (
              <li key={booking.id}>
                <button
                  type="button"
                  disabled={choosing}
                  onClick={() => onChoose(booking.id)}
                  className="flex min-h-12 w-full items-center justify-between gap-3 rounded-2xl px-4 text-start text-sm font-bold disabled:opacity-60"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  <BookingLabel booking={booking} />
                  <span aria-hidden="true">›</span>
                </button>
              </li>
            ))}
          </ul>
          {chooseError ? <ErrorNotice>{chooseError}</ErrorNotice> : null}
        </Card>
      );
    case "suggestions":
    case "nothing":
      return (
        <Card>
          <BoxLine result={result} />
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("scanNothingTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(nothingReasonKey(result.reason))}</p>
          {result.next_booking ? (
            <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
              {t("scanNextBooking")} <BookingLabel booking={result.next_booking} />
            </p>
          ) : null}
          {view.kind === "suggestions" ? (
            <>
              <h2 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("scanSuggestionsTitle")}</h2>
              <ul className="flex flex-col gap-2">
                {(result.classes ?? []).map((slot) => (
                  <li key={slot.id} className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
                    <ClassLabel slot={slot} />
                    <Link href={schedule(slot.id)} className="flex min-h-11 shrink-0 items-center rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                      {t("scanBook")}
                    </Link>
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <Link href={schedule()} className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("scanOpenSchedule")}
            </Link>
          )}
          <PackageLine pkg={result.package} />
        </Card>
      );
    case "poster_member":
      return (
        <Card>
          <BoxLine result={result} />
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("scanNothingTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("scanPosterNoBooking")}</p>
          <Link href={schedule()} className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("scanOpenSchedule")}
          </Link>
        </Card>
      );
    case "poster_visitor":
      return (
        <Card>
          <BoxLine result={result} />
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("scanVisitorTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("scanPosterVisitor", { box: box.name })}</p>
        </Card>
      );
    case "visitor":
      return <VisitorView token={token} result={result} />;
  }
}

function CheckedIn({ token, result, receivedAt, onUndone }: { token: string; result: ScanResult; receivedAt: number; onUndone: (undone: UndoResult) => void }) {
  const t = useTranslations("CheckIn");
  // `undo_until` is the server's clock; the response's Date header isn't exposed, so the
  // offset is measured from when the answer arrived (the minute starts on the server then).
  const offset = clockOffset(result.check_in?.at ?? null, receivedAt);
  const [now, setNow] = useState(() => Date.now());
  const left = undoSecondsLeft(result.undo_until, now + offset);
  useEffect(() => {
    if (left <= 0) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, [left]);

  const undo = useMutation({
    mutationFn: () => undoScan(token, result.undo_token!),
    onSuccess: onUndone,
  });

  return (
    <Card tone="success">
      <BoxLine result={result} />
      <p aria-hidden="true" className="text-5xl" style={{ color: "var(--success)" }}>✓</p>
      <h1 className="text-3xl font-extrabold" style={{ color: "var(--text)" }} data-testid="scan-checked-in">
        <CheckInLine result={result} />
      </h1>
      <PackageLine pkg={result.package} />
      {result.undo_token && left > 0 ? (
        <button
          type="button"
          onClick={() => undo.mutate()}
          disabled={undo.isPending}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="scan-undo"
        >
          {t("scanUndo", { seconds: left })}
        </button>
      ) : null}
      {undo.isError ? <ErrorNotice>{t(checkInErrorKey(undo.error))}</ErrorNotice> : null}
    </Card>
  );
}

function Undone({ result, undone }: { result: ScanResult; undone: UndoResult }) {
  const t = useTranslations("CheckIn");
  return (
    <Card>
      <BoxLine result={result} />
      <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }} data-testid="scan-undone">{t("scanUndoneTitle")}</h1>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("scanUndoneHint")}</p>
      <PackageLine pkg={undone.package ?? null} />
    </Card>
  );
}

function VisitorView({ token, result }: { token: string; result: ScanResult }) {
  const t = useTranslations("CheckIn");
  const tTrials = useTranslations("Trials");
  const [picked, setPicked] = useState<CheckInClass | null>(null);
  const trial = result.trial ?? null;
  const classes = trial?.enabled && !trial.blocked_reason ? trial.classes : [];
  const mine = trial?.mine as { id?: string; status?: string } | null | undefined;

  return (
    <Card>
      <BoxLine result={result} />
      <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }} data-testid="scan-visitor">{t("scanVisitorTitle")}</h1>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {result.membership === "former" ? t("scanVisitorFormer", { box: result.box.name }) : t("scanVisitorHint", { box: result.box.name })}
      </p>

      {mine?.id ? (
        <Link href={`/trials/${encodeURIComponent(mine.id)}`} className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--success)", color: "var(--text)" }}>
          {tTrials("yourTrial")}
        </Link>
      ) : null}

      {trial?.blocked_reason ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{tTrials(["blocked", trial.blocked_reason].join("_"))}</p>
      ) : null}

      {!mine?.id && classes.length > 0 ? (
        <>
          <h2 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("scanTrialTitle")}</h2>
          <ul className="flex flex-col gap-2">
            {classes.map((slot) => (
              <li key={slot.id} className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
                <span className="flex min-w-0 flex-col">
                  <ClassLabel slot={slot} />
                  {typeof slot.trial_seats === "number" ? (
                    <span className="text-xs font-bold" style={{ color: "var(--success)" }}>{tTrials("seatsLeft", { count: slot.trial_seats })}</span>
                  ) : null}
                </span>
                <button
                  type="button"
                  onClick={() => setPicked(slot)}
                  className="min-h-11 shrink-0 rounded-2xl px-4 text-sm font-bold"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {t("scanTrialBook")}
                </button>
              </li>
            ))}
          </ul>
        </>
      ) : null}

      <FollowButton targetType="organization" targetId={result.box.organization_id} initialStatus={result.follow} wide />

      {picked && trial ? (
        <TrialSheet
          page={{ box: { slug: result.box.slug, name: result.box.name } }}
          token={token}
          offer={{ approval: trial.approval ?? AUTO_APPROVAL }}
          initialSlot={{ id: picked.id, name: picked.name ?? null, scheduled_at: picked.starts_at }}
          source="qr_door"
          onClose={() => setPicked(null)}
        />
      ) : null}
    </Card>
  );
}

// -- small parts

function Card({ children, tone }: { children: React.ReactNode; tone?: "success" }) {
  return (
    <section
      className="flex flex-col gap-3 rounded-3xl p-5"
      style={{
        background: tone === "success" ? "color-mix(in srgb, var(--success) 10%, var(--panel))" : "var(--panel)",
        border: `1px solid ${tone === "success" ? "color-mix(in srgb, var(--success) 45%, transparent)" : "var(--border)"}`,
      }}
    >
      {children}
    </section>
  );
}

function BoxLine({ result }: { result: ScanResult }) {
  return (
    <p className="flex items-center gap-2 text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
      {result.box.logo_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- the box's uploaded logo
        <img src={result.box.logo_url} alt="" className="h-6 w-6 rounded-md object-contain" />
      ) : null}
      <span className="truncate">{[result.box.name, result.location.name].filter(Boolean).join(" · ")}</span>
    </p>
  );
}

function useClock() {
  const locale = useLocale();
  return (iso: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}

function useDay() {
  const locale = useLocale();
  return (iso: string) => new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short" }).format(new Date(iso));
}

function BookingLabel({ booking }: { booking: CheckInBooking }) {
  const clock = useClock();
  return <span>{[booking.name, clock(booking.starts_at)].filter(Boolean).join(" ")}</span>;
}

function ClassLabel({ slot }: { slot: CheckInClass }) {
  const t = useTranslations("CheckIn");
  const clock = useClock();
  const day = useDay();
  return (
    <span className="flex min-w-0 flex-col">
      <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{[slot.name, clock(slot.starts_at)].filter(Boolean).join(" ")}</span>
      <span className="text-xs" style={{ color: "var(--text-soft)" }}>
        {day(slot.starts_at)}
        {typeof slot.spots_remaining === "number" ? ` · ${t("spotsLeft", { count: slot.spots_remaining })}` : ""}
      </span>
    </span>
  );
}

/** «Μέσα! CrossFit 18:00» or «Μέσα! Open gym». */
function CheckInLine({ result }: { result: ScanResult }) {
  const t = useTranslations("CheckIn");
  const clock = useClock();
  const booking = result.check_in?.booking;
  if (result.check_in?.kind === "class" && booking) return <>{t("scanInClass", { name: booking.name ?? "", time: clock(booking.starts_at) })}</>;
  return <>{t("scanInOpenGym")}</>;
}

function PackageLine({ pkg }: { pkg: CheckInPackage | null | undefined }) {
  const t = useTranslations("CheckIn");
  if (!pkg?.name) return null;
  const left = pkg.unlimited
    ? t("packageUnlimited")
    : typeof pkg.class_visits_left === "number"
      ? t("packageVisitsLeft", { count: pkg.class_visits_left })
      : typeof pkg.open_gym_visits_left === "number"
        ? t("packageOpenGymLeft", { count: pkg.open_gym_visits_left })
        : null;
  return (
    <p className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="scan-package">
      {[pkg.name, left].filter(Boolean).join(" · ")}
    </p>
  );
}
