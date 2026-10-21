"use client";

import Link from "next/link";
import { useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchBoxSchedule, type PublicBoxPage, type PublicBoxSchedule } from "@/api/social";
import { MY_TRIALS_KEY, requestTrial, type MyTrial, type TrialOffer } from "@/api/trials";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

import { newOperationId, trialErrorKey } from "./trial-ui";

type Slot = PublicBoxSchedule["slots"][number];
/** What the sheet needs of a class picked before it opens (the box schedule, or a door scan's offer). */
type PickedSlot = { id: string; name?: string | null; scheduled_at: string };

const WINDOW_DAYS = 14;

/**
 * The trial sheet (board 6 Q1): this fortnight's classes that take trial
 * guests, by day; pick one, add an optional note for the coach and phone,
 * confirm. It's booked at once («Κλείστηκε») or sent for approval
 * («Στάλθηκε»), then shows the box's «Τι να φέρεις». The same sheet opens
 * from «Κλείσε με δοκιμαστικό» on a class, with that class picked.
 */
export function TrialSheet({
  page,
  token,
  offer,
  initialSlot,
  referralEventId = null,
  source,
  onClose,
}: {
  page: { box: Pick<PublicBoxPage["box"], "slug" | "name"> };
  token: string;
  offer: Pick<TrialOffer, "approval">;
  initialSlot?: PickedSlot | null;
  /** The club event whose trial offer opened the sheet (ADR-153). */
  referralEventId?: string | null;
  /** Where the ask came from when the caller knows better (the door scan: `qr_door`, ADR-155). */
  source?: "qr_door";
  onClose: () => void;
}) {
  const t = useTranslations("Trials");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const dialog = useModalFocusTrap<HTMLElement>(onClose);
  const [picked, setPicked] = useState<PickedSlot | null>(initialSlot ?? null);
  const [note, setNote] = useState("");
  const [phone, setPhone] = useState("");
  const [done, setDone] = useState<MyTrial | null>(null);
  const operation = useRef(newOperationId());

  const classes = useQuery({
    queryKey: ["social", "box-trial-classes", page.box.slug],
    enabled: !initialSlot,
    queryFn: () => {
      const start = new Date();
      const end = new Date(start.getTime() + WINDOW_DAYS * 86_400_000);
      return fetchBoxSchedule(token, page.box.slug, { startAt: start.toISOString(), endAt: end.toISOString() });
    },
  });

  const days = useMemo(() => {
    const open = (classes.data?.slots ?? []).filter((slot) => (slot.trial_seats ?? 0) > 0);
    const byDay = new Map<string, Slot[]>();
    for (const slot of open) {
      const key = new Date(slot.scheduled_at).toDateString();
      byDay.set(key, [...(byDay.get(key) ?? []), slot]);
    }
    return [...byDay.values()];
  }, [classes.data]);

  const ask = useMutation({
    mutationFn: () =>
      requestTrial(token, page.box.slug, {
        scheduled_class_id: picked!.id,
        note: note.trim() || null,
        phone: phone.trim() || null,
        source: referralEventId ? "event" : source ?? (initialSlot ? "schedule" : "box_page"),
        ...(referralEventId ? { referral_event_id: referralEventId } : {}),
        client_operation_id: operation.current,
      }),
    onSuccess: (trial) => {
      setDone(trial);
      void queryClient.invalidateQueries({ queryKey: MY_TRIALS_KEY });
      void queryClient.invalidateQueries({ queryKey: ["social", "box-schedule", page.box.slug] });
      void queryClient.invalidateQueries({ queryKey: ["social", "box-trial-classes", page.box.slug] });
    },
  });

  const dayLabel = (iso: string) =>
    new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" }).format(new Date(iso));
  const clock = (iso: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const manual = offer.approval === "manual";
  const phoneValid = phone.trim() === "" || /^\+?[0-9 ()-]{6,24}$/.test(phone.trim());

  // Portalled: the box page's side card is its own stacking context.
  return createPortal(
    <div className="fixed inset-0 z-[70] flex items-end justify-center sm:items-center" style={{ background: "rgba(0,0,0,0.55)" }} onClick={onClose} role="presentation">
      <section
        ref={dialog}
        role="dialog"
        aria-modal="true"
        aria-labelledby="trial-sheet-title"
        onClick={(event) => event.stopPropagation()}
        className="flex max-h-[92dvh] w-full max-w-xl flex-col rounded-t-3xl sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="flex justify-center pt-2.5 sm:hidden">
          <span aria-hidden="true" className="h-1 w-10 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <header className="px-5 pb-2 pt-3">
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{page.box.name}</p>
          <h2 id="trial-sheet-title" className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>
            {done ? (done.status === "booked" ? t("doneBookedTitle") : t("doneRequestedTitle")) : t("sheetTitle")}
          </h2>
        </header>

        <div className="flex-1 overflow-y-auto px-5 pb-4">
          {done ? (
            <div className="flex flex-col gap-3">
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>
                {done.status === "booked" ? t("doneBookedBody") : t("doneRequestedBody")}
              </p>
              <p className="rounded-2xl px-4 py-3 text-sm font-semibold first-letter:uppercase" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
                {done.class.name} · {dayLabel(done.class.scheduled_at)} · {clock(done.class.scheduled_at)}
              </p>
              {done.bring_note ? (
                <div className="rounded-2xl px-4 py-3" style={{ border: "1px solid var(--border)" }}>
                  <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("bringTitle")}</p>
                  <p className="mt-1 whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>{done.bring_note}</p>
                </div>
              ) : null}
            </div>
          ) : picked ? (
            <div className="flex flex-col gap-4">
              <div className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)" }}>
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{picked.name}</span>
                  <span className="text-xs first-letter:uppercase" style={{ color: "var(--text-soft)" }}>
                    {dayLabel(picked.scheduled_at)} · {clock(picked.scheduled_at)}
                  </span>
                </span>
                {!initialSlot ? (
                  <button type="button" onClick={() => setPicked(null)} className="shrink-0 text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
                    {t("change")}
                  </button>
                ) : null}
              </div>
              <label className="flex flex-col gap-1.5">
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("noteLabel")}</span>
                <textarea
                  value={note}
                  onChange={(event) => setNote(event.target.value.slice(0, 500))}
                  rows={3}
                  placeholder={t("notePlaceholder")}
                  className="rounded-2xl px-3.5 py-2.5 text-sm"
                  style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                />
              </label>
              <label className="flex flex-col gap-1.5">
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("phoneLabel")}</span>
                <input
                  type="tel"
                  inputMode="tel"
                  autoComplete="tel"
                  value={phone}
                  onChange={(event) => setPhone(event.target.value.slice(0, 24))}
                  placeholder={t("phonePlaceholder")}
                  aria-invalid={!phoneValid}
                  className="min-h-11 rounded-2xl px-3.5 text-sm"
                  style={{ background: "var(--bg)", border: `1px solid ${phoneValid ? "var(--border)" : "var(--danger)"}`, color: "var(--text)" }}
                />
                <span className="text-xs" style={{ color: phoneValid ? "var(--dim)" : "var(--danger)" }}>
                  {phoneValid ? t("phoneHint") : t("phoneInvalid")}
                </span>
              </label>
              {ask.isError ? (
                <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t(trialErrorKey(ask.error))}</p>
              ) : null}
            </div>
          ) : (
            <div className="flex flex-col gap-4">
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{manual ? t("pickHintManual") : t("pickHint")}</p>
              {classes.isPending ? <p className="py-4 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
              {classes.isError ? <p className="py-4 text-center text-sm" style={{ color: "var(--danger)" }}>{t("error_generic")}</p> : null}
              {classes.isSuccess && days.length === 0 ? (
                <p className="rounded-2xl p-4 text-center text-sm" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>{t("noClasses")}</p>
              ) : null}
              {days.map((slots) => (
                <section key={slots[0]!.id} className="flex flex-col gap-2">
                  <h3 className="text-xs font-bold uppercase tracking-[0.14em] first-letter:uppercase" style={{ color: "var(--dim)" }}>
                    {dayLabel(slots[0]!.scheduled_at)}
                  </h3>
                  {slots.map((slot) => (
                    <button
                      key={slot.id}
                      type="button"
                      onClick={() => setPicked(slot)}
                      className="grid min-h-14 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl px-4 py-2.5 text-start"
                      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
                    >
                      <span className="font-mono text-sm font-bold" style={{ color: "var(--text-soft)" }}>{clock(slot.scheduled_at)}</span>
                      <span className="flex min-w-0 flex-col">
                        <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{slot.name}</span>
                        {slot.coach?.nickname ? <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{slot.coach.nickname}</span> : null}
                      </span>
                      <span className="text-xs font-bold" style={{ color: "var(--success)" }}>{t("seatsLeft", { count: slot.trial_seats ?? 0 })}</span>
                    </button>
                  ))}
                </section>
              ))}
            </div>
          )}
        </div>

        <footer className="flex flex-col gap-2 px-5 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3" style={{ borderTop: "1px solid var(--border)" }}>
          {done ? (
            <Link href={`/trials/${done.id}`} className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold" style={{ background: "var(--primary)", color: "var(--bg)" }}>
              {t("seeTrial")}
            </Link>
          ) : picked ? (
            <button
              type="button"
              disabled={ask.isPending || !phoneValid}
              onClick={() => ask.mutate()}
              className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold disabled:opacity-60"
              style={{ background: "var(--primary)", color: "var(--bg)" }}
            >
              {ask.isPending ? t("sending") : manual ? t("confirmManual") : t("confirmAuto")}
            </button>
          ) : null}
          <button type="button" onClick={onClose} className="min-h-11 rounded-2xl text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {done ? t("close") : t("cancel")}
          </button>
        </footer>
      </section>
    </div>,
    document.body,
  );
}
