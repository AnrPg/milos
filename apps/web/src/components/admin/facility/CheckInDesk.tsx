"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale } from "next-intl";
import { useState } from "react";

import { createCheckIn, listAdminLocations, listCheckIns, type FacilityCheckIn } from "@/api/facility";
import type { FinanceRecord } from "@/api/finance";
import { localizeCheckInError } from "@/components/admin/facility/check-in-errors";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { localIsoDate } from "@/components/admin/users/membership-freezes";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" };

/** Front-desk open-gym check-ins (ADR-097): who came in on a day, and a quick manual check-in. */
export function CheckInDesk() {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const today = localIsoDate();
  const [date, setDate] = useState(today);
  const [member, setMember] = useState<{ id: string; nickname: string }>({ id: "", nickname: "" });
  const [locationId, setLocationId] = useState("");
  const [result, setResult] = useState<{ tone: "success" | "info" | "danger"; text: string } | null>(null);

  const locationsQuery = useQuery({
    queryKey: ["admin", "locations"],
    enabled: Boolean(token),
    queryFn: () => listAdminLocations(token!),
  });
  const activeLocations = (locationsQuery.data ?? []).filter((location) => !location.archived_at);

  const checkInsQuery = useQuery({
    queryKey: ["admin", "check-ins", date],
    enabled: Boolean(token),
    queryFn: () => listCheckIns(token!, { date }),
  });
  const checkIns = checkInsQuery.data ?? [];

  const checkIn = useMutation({
    mutationFn: () => createCheckIn(token!, { user_id: member.id, location_id: locationId || null }),
    onSuccess: async (record: FacilityCheckIn) => {
      const name = record.nickname ?? member.nickname;
      setResult(
        record.already_checked_in
          ? { tone: "info", text: i18n("admCheckInAlready", { name }) }
          : { tone: "success", text: i18n("admCheckInDone", { name }) },
      );
      setMember({ id: "", nickname: "" });
      await queryClient.invalidateQueries({ queryKey: ["admin", "check-ins"] });
    },
    onError: (error) => setResult({ tone: "danger", text: localizeCheckInError(error, i18n) }),
  });

  const time = (value: string) =>
    new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(value));

  const toneColor = { success: "var(--success)", info: "var(--muted)", danger: "var(--danger)" } as const;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-4xl space-y-6">
        <TransientHero collapsedTitle={i18n("admCheckInTitle")} label={i18n("admCheckInIntro")} timeoutMs={3000}>
          <section className="rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("admCheckInTitle")}</p>
            <p className="mt-4 max-w-3xl text-base leading-7" style={{ color: "var(--muted)" }}>{i18n("admCheckInIntro")}</p>
          </section>
        </TransientHero>

        {token ? (
          <>
            <section className="space-y-4 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{i18n("admCheckInMember")}</h2>
              <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
                <UserSearchField
                  label={i18n("admCheckInMemberLabel")}
                  token={token}
                  value={member.id}
                  onChange={(id, user: FinanceRecord | null) => {
                    setResult(null);
                    setMember({ id, nickname: typeof user?.nickname === "string" ? user.nickname : "" });
                  }}
                />
                {activeLocations.length > 0 ? (
                  <label className="space-y-1">
                    <span className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("admSlotLocation")}</span>
                    <select className="w-full rounded-xl px-3 py-2 text-sm" onChange={(event) => setLocationId(event.target.value)} style={fieldStyle} value={locationId}>
                      <option value="">{i18n("admCheckInNoLocation")}</option>
                      {activeLocations.map((location) => (
                        <option key={location.id} value={location.id}>{location.name}</option>
                      ))}
                    </select>
                  </label>
                ) : null}
              </div>
              <button
                className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-50"
                disabled={!member.id || checkIn.isPending}
                onClick={() => checkIn.mutate()}
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                type="button"
              >
                {checkIn.isPending ? i18n("admCheckInPending") : i18n("admCheckInAction")}
              </button>
              {result ? <p className="text-sm font-semibold" role="status" style={{ color: toneColor[result.tone] }}>{result.text}</p> : null}
            </section>

            <section className="space-y-4 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>
                  {date === today ? i18n("admCheckInToday") : i18n("admCheckInOnDay")}
                  {checkInsQuery.isSuccess ? <span style={{ color: "var(--dim)" }}> · {checkIns.length}</span> : null}
                </h2>
                <input
                  aria-label={i18n("admCheckInDate")}
                  className="rounded-xl px-3 py-2 text-sm"
                  max={today}
                  onChange={(event) => setDate(event.target.value || today)}
                  style={fieldStyle}
                  type="date"
                  value={date}
                />
              </div>
              {checkInsQuery.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p> : null}
              {checkInsQuery.isError ? <p className="text-sm" role="alert" style={{ color: "var(--danger)" }}>{localizeError(checkInsQuery.error, i18n)}</p> : null}
              {checkInsQuery.isSuccess && checkIns.length === 0 ? <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("admCheckInEmpty")}</p> : null}
              <ul className="space-y-2">
                {checkIns.map((record) => (
                  <li className="flex items-center gap-3 rounded-[1.2rem] px-4 py-3 text-sm" key={record.id} style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                    <span className="w-14 shrink-0 tabular-nums" style={{ color: "var(--dim)" }}>{time(record.checked_in_at)}</span>
                    <span className="min-w-0 flex-1 truncate font-semibold" style={{ color: "var(--text)" }}>{record.nickname ?? record.user_id}</span>
                    {record.location_name ? <span className="truncate text-xs" style={{ color: "var(--muted)" }}>{record.location_name}</span> : null}
                    <span className="shrink-0 text-xs" style={{ color: "var(--dim)" }}>
                      {record.source === "staff" ? i18n("admCheckInSourceStaff") : i18n("admCheckInSourceSelf")}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          </>
        ) : (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        )}
      </div>
    </main>
  );
}
