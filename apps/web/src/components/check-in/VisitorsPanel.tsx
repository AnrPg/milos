"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchVisitors, VISITORS_KEY, type Visitor } from "@/api/check-in";
import { subscribeNever } from "@/lib/maps";
import { subscribeToTopic } from "@/lib/realtime";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const readVisitor = () => new URLSearchParams(window.location.search).get("visitor");
const serverVisitor = () => null;

/**
 * «Επισκέπτες» at the desk (ADR-155 §4): people who aren't members and
 * scanned the door today, newest first, live as they scan. The bell's
 * «Επισκέπτης στην πόρτα» opens the desk on that visitor.
 */
export function VisitorsPanel({ token, organizationId, date }: { token: string; organizationId: string | null; date: string }) {
  const t = useTranslations("CheckIn");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const highlighted = useSyncExternalStore(subscribeNever, readVisitor, serverVisitor);
  const sectionRef = useRef<HTMLElement>(null);
  const key = [...VISITORS_KEY, date] as const;
  const visitors = useQuery({ queryKey: key, queryFn: () => fetchVisitors(token, { date }) });

  // Live: a visitor scanning now joins the top of the list; check-ins refresh the day's list.
  useEffect(() => {
    if (!organizationId) return;
    return subscribeToTopic(token, `check_in:${organizationId}`, {
      visitor_scanned: (payload) => {
        const scan = payload as { id: string; user_id: string; location_id?: string | null; display_name?: string | null; avatar_url?: string | null; at: string };
        queryClient.setQueryData<Visitor[]>([...VISITORS_KEY, date], (current = []) =>
          current.some((visitor) => visitor.id === scan.id)
            ? current
            : [{ id: scan.id, user_id: scan.user_id, location_id: scan.location_id ?? null, display_name: scan.display_name ?? null, avatar_url: scan.avatar_url ?? null, scanned_at: scan.at, trial_offered: false }, ...current],
        );
      },
      checked_in: () => void queryClient.invalidateQueries({ queryKey: ["admin", "check-ins"] }),
      check_in_undone: () => void queryClient.invalidateQueries({ queryKey: ["admin", "check-ins"] }),
    });
  }, [date, organizationId, queryClient, token]);

  // Opened from the bell: bring the visitor into view once the list is there.
  const hasData = Boolean(visitors.data);
  useEffect(() => {
    if (highlighted && hasData) sectionRef.current?.scrollIntoView({ block: "start" });
  }, [hasData, highlighted]);

  const time = (iso: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const list = visitors.data ?? [];

  return (
    <section ref={sectionRef} id="visitors" className="space-y-4 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-labelledby="visitors-title" data-testid="desk-visitors">
      <div>
        <h2 id="visitors-title" className="text-lg font-semibold" style={{ color: "var(--text)" }}>
          {t("visitorsTitle")}
          {visitors.isSuccess ? <span style={{ color: "var(--dim)" }}> · {list.length}</span> : null}
        </h2>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("visitorsHint")}</p>
      </div>
      {visitors.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {visitors.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
      {visitors.isSuccess && list.length === 0 ? <p className="text-sm" style={{ color: "var(--muted)" }}>{t("visitorsEmpty")}</p> : null}
      <ul className="space-y-2" aria-live="polite">
        {list.map((visitor) => {
          const name = visitor.display_name || visitor.nickname || t("visitorUnnamed");
          const active = visitor.id === highlighted;
          return (
            <li
              key={visitor.id}
              className="flex items-center gap-3 rounded-[1.2rem] px-4 py-3 text-sm"
              style={{ background: active ? "color-mix(in srgb, var(--primary) 12%, var(--panel-muted))" : "var(--panel-muted)", border: `1px solid ${active ? "var(--primary)" : "var(--border)"}` }}
              aria-current={active ? "true" : undefined}
            >
              {visitor.avatar_url ? (
                // eslint-disable-next-line @next/next/no-img-element -- profile photo from the media origin
                <img src={visitor.avatar_url} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
              ) : (
                <span aria-hidden="true" className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold" style={{ background: "var(--border)", color: "var(--text)" }}>
                  {name.slice(0, 2).toUpperCase()}
                </span>
              )}
              <span className="w-12 shrink-0 tabular-nums" style={{ color: "var(--dim)" }}>{time(visitor.scanned_at)}</span>
              <span className="min-w-0 flex-1 truncate font-semibold" style={{ color: "var(--text)" }}>{name}</span>
              {visitor.location_name ? <span className="hidden truncate text-xs sm:inline" style={{ color: "var(--muted)" }}>{visitor.location_name}</span> : null}
              {visitor.trial_offered ? (
                <span className="shrink-0 rounded-full px-2 py-0.5 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}>
                  {t("visitorTrialOffered")}
                </span>
              ) : null}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
