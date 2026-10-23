"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import { createCheckIn, listAdminLocations, listCheckIns, type FacilityCheckIn } from "@/api/facility";
import type { FinanceRecord } from "@/api/finance";
import { localizeCheckInError } from "@/components/admin/facility/check-in-errors";
import { DeskScanner } from "@/components/check-in/DeskScanner";
import { VisitorsPanel } from "@/components/check-in/VisitorsPanel";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { localIsoDate } from "@/components/admin/users/membership-freezes";
import { useSession } from "@/components/session-provider";
import { PageHeader } from "@/components/PageHeader";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { membershipLocationScope } from "@/lib/location-scope";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { Select } from "@/components/ui/Select";
import { DateInput } from "@/components/ui/DateInput";
import { SPARK_GO_STYLE } from "@/lib/spark";

const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" };

/**
 * Front-desk check-ins (ADR-097): who came in on a day, and a quick manual
 * check-in. ADR-155 adds «Σάρωση» of a member's QR or Wallet card, today's
 * visitors at the door, and the way to each location's door screen.
 */
export function CheckInDesk() {
  const i18n = useUiTranslations();
  const tCheckIn = useTranslations("CheckIn");
  const slug = useOrganizationSlug();
  const { membership } = useSelectedMembershipRole();
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
  const branchScoped = membershipLocationScope(membership) !== "all";
  const deskLocationId = locationId || (branchScoped ? (activeLocations[0]?.id ?? "") : "");

  const checkInsQuery = useQuery({
    queryKey: ["admin", "check-ins", date],
    enabled: Boolean(token),
    queryFn: () => listCheckIns(token!, { date }),
  });
  const checkIns = checkInsQuery.data ?? [];

  const checkIn = useMutation({
    mutationFn: () => createCheckIn(token!, { user_id: member.id, location_id: deskLocationId || null }),
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
        <PageHeader title={i18n("admCheckInTitle")} />

        {token ? (
          <>
            {activeLocations.length > 0 ? (
              <nav aria-label={tCheckIn("doorScreens")} className="flex flex-wrap gap-2">
                {activeLocations.map((location) => (
                  <Link
                    key={location.id}
                    href={adminHref(`/admin/check-in/door/${location.id}`, slug)}
                    className="flex min-h-11 items-center rounded-full px-4 text-sm font-semibold"
                    style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    {tCheckIn("doorScreenFor", { name: location.name })}
                  </Link>
                ))}
                <Link
                  href={adminHref("/admin/check-in/settings", slug)}
                  className="flex min-h-11 items-center rounded-full px-4 text-sm font-semibold"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                >
                  {tCheckIn("settingsTitle")}
                </Link>
              </nav>
            ) : null}

            <DeskScanner token={token} locationId={deskLocationId} />

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
                    <Select className="w-full rounded-xl px-3 py-2 text-sm" onValueChange={(value) => setLocationId(value)} style={fieldStyle} value={deskLocationId}>
                      {/* ADR-186: branch staff check in at one of their branches (the API defaults a single one). */}
                      {branchScoped ? null : <option value="">{i18n("admCheckInNoLocation")}</option>}
                      {activeLocations.map((location) => (
                        <option key={location.id} value={location.id}>{location.name}</option>
                      ))}
                    </Select>
                  </label>
                ) : null}
              </div>
              <button
                className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-50"
                disabled={!member.id || checkIn.isPending}
                onClick={() => checkIn.mutate()}
                style={SPARK_GO_STYLE}
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
                <DateInput
                  aria-label={i18n("admCheckInDate")}
                  className="rounded-xl px-3 py-2 text-sm"
                  max={today}
                  onValueChange={(value) => setDate(value || today)}
                  style={fieldStyle}
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

            <VisitorsPanel token={token} organizationId={membership?.organization.id ?? null} date={today} />
          </>
        ) : (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        )}
      </div>
    </main>
  );
}
