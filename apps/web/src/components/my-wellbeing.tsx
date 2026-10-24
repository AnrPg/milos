"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMutation, useQuery } from "@tanstack/react-query";

import {
  fetchMyInjuries,
  markMyInjuryHealed,
  reopenMyInjury,
  reportInjury,
  updateMyInjury,
  type InjuryUpdateRequest,
  type ReportInjuryRequest,
} from "@/api/wellbeing";
import { useSession } from "@/components/session-provider";
import { SemanticLabel } from "@/components/semantic-label";
import { PageHeader } from "@/components/PageHeader";
import { CheckInPanel } from "@/components/member-app/wellbeing/CheckInPanel";
import { InjuryTimeline, InjuryUpdateForm } from "@/components/member-app/wellbeing/InjuryTimeline";
import { useWellness, wellnessWindow, WellnessPanel } from "@/components/member-app/wellness/WellnessPanel";
import { localDate } from "@/components/member-app/wellness/wellness-model";
import { WellnessSupportCard } from "@/components/buddy/WellnessSupportCard";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useSelectedMembershipRole } from "@/lib/membership-role";

export function MyWellbeing() {
  const i18n = useUiTranslations();
  const t = useTranslations("MemberApp.injury");
  const { tokens } = useSession();
  const [bodyArea, setBodyArea] = useState("");
  const [severity, setSeverity] = useState<ReportInjuryRequest["severity"]>("mild");
  const [limitations, setLimitations] = useState("");
  const [updatingId, setUpdatingId] = useState<string | null>(null);
  // «Πώς πήγε;» and Νέα καταχώρηση › Λιγούρα arrive as ?craving=<id|new>.
  const search = useSearchParams();
  // Νέα καταχώρηση › Τραυματισμός arrives as ?injury=new and opens the form.
  const router = useRouter();
  const pathname = usePathname();
  const [reportingByButton, setReportingByButton] = useState(false);
  const reporting = reportingByButton || search.get("injury") === "new";
  const setReporting = (open: boolean) => {
    setReportingByButton(open);
    if (!open && search.get("injury")) router.replace(pathname, { scroll: false });
  };
  // The Journal header names the page; only staff, who see no Journal header, get a title.
  const { role } = useSelectedMembershipRole();
  const craving = search.get("craving");
  // Νέα καταχώρηση › Χρειάζομαι στήριξη arrives as ?support=new (ADR-160).
  const support = search.get("support") === "new";
  const today = localDate(new Date());
  const range = wellnessWindow(today, 0);
  const wellness = useWellness(range.from, range.to);
  const todaySleep = wellness.data?.days.find((day) => day.date === today)?.sleep.status;
  const sleepLogged = Boolean(todaySleep && todaySleep !== "none" && !wellness.data?.preferences.hidden_items.includes("sleep"));

  const injuriesQuery = useQuery({
    queryKey: ["my", "wellbeing", "injuries"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchMyInjuries(tokens!.access_token),
  });

  const reportMutation = useMutation({
    mutationFn: async () =>
      reportInjury(tokens!.access_token, {
        body_area: bodyArea,
        severity,
        training_limitations: limitations,
      }),
    onSuccess: () => {
      setBodyArea("");
      setLimitations("");
      setReporting(false);
      injuriesQuery.refetch();
    },
  });

  const healMutation = useMutation({
    mutationFn: async (id: string) => markMyInjuryHealed(tokens!.access_token, id),
    onSuccess: () => injuriesQuery.refetch(),
  });

  const updateMutation = useMutation({
    mutationFn: async ({ id, update }: { id: string; update: InjuryUpdateRequest }) =>
      updateMyInjury(tokens!.access_token, id, update),
    onSuccess: () => {
      setUpdatingId(null);
      injuriesQuery.refetch();
    },
  });

  const reopenMutation = useMutation({
    mutationFn: async (id: string) => reopenMyInjury(tokens!.access_token, id),
    onSuccess: () => injuriesQuery.refetch(),
  });

  return (
    <main className="min-h-screen bg-[var(--bg)] px-4 py-6 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-4xl space-y-6">
        {role === "admin" ? <PageHeader title={i18n("myWellbeing1916377")} /> : null}

        <WellnessPanel key={craving ?? "panel"} initialCraving={craving} />

        <WellnessSupportCard key={support ? "support-new" : "support"} initialOpen={support} />

        <section id="check-in" className="scroll-mt-24">
          <CheckInPanel skipQuestions={sleepLogged ? ["sleep"] : []} />
        </section>

        {/* ADR-194: the form opens from a labelled button, not always open. */}
        <section id="report-injury" className="scroll-mt-24">
          <button
            type="button"
            onClick={() => setReporting(true)}
            className="min-h-11 rounded-full border border-[var(--border)] bg-[var(--panel)] px-5 text-sm font-bold"
          >
            {i18n("reportInjuryea0dc21")}
          </button>
        </section>
        {reporting ? (
          <Dialog
            title={i18n("reportInjuryea0dc21")}
            onClose={() => setReporting(false)}
            size="sm"
            onSubmit={(event) => {
              event.preventDefault();
              reportMutation.mutate();
            }}
            footer={
              <button
                className="min-h-11 w-full rounded-full bg-[var(--primary)] px-5 text-sm font-bold text-[var(--primary-contrast)] disabled:opacity-60"
                type="submit"
                disabled={reportMutation.isPending}
              >
                {reportMutation.isPending ? i18n("reportingee900db") : i18n("reportInjuryea0dc21")}
              </button>
            }
          >
            <div className="space-y-4">
              <input
                className="min-h-11 w-full rounded-2xl border px-4 py-3"
                aria-label={i18n("bodyAreaEGShoulder667ada5")}
                placeholder={i18n("bodyAreaEGShoulder667ada5")}
                required
                autoFocus
                value={bodyArea}
                onChange={(event) => setBodyArea(event.target.value)}
              />
              <Select
                className="w-full rounded-2xl border px-4 py-3"
                value={severity}
                onValueChange={(value) => setSeverity(value as ReportInjuryRequest["severity"])}
              >
                <option value="mild">{i18n("mild17538a9")}</option>
                <option value="moderate">{i18n("moderateea8b09c")}</option>
                <option value="severe">{i18n("severeb7c1535")}</option>
              </Select>
              <textarea
                className="min-h-28 w-full rounded-2xl border px-4 py-3"
                aria-label={i18n("trainingLimitationsOrNotes9c0ebf6")}
                placeholder={i18n("trainingLimitationsOrNotes9c0ebf6")}
                value={limitations}
                onChange={(event) => setLimitations(event.target.value)}
              />
              <ErrorText error={reportMutation.error} />
            </div>
          </Dialog>
        ) : null}

        <section className="grid gap-3">
          {(injuriesQuery.data?.injuries ?? []).map((injury) => (
            <article key={String(injury.id)} className="rounded-2xl border border-[var(--border)] bg-[var(--panel)] p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-bold">
                    {String(injury.body_area)} · <SemanticLabel value={injury.severity} />
                  </p>
                  <p className="text-sm text-[var(--muted)]">{i18n("statusbae7d5b")} <SemanticLabel value={injury.status} /></p>
                </div>
                <div className="flex flex-wrap gap-2">
                  {injury.status === "active" ? (
                    <>
                      <button
                        className="min-h-11 rounded-full border border-[var(--border)] px-4 py-2 text-sm font-bold"
                        type="button"
                        onClick={() => setUpdatingId(String(injury.id))}
                      >
                        {t("addUpdate")}
                      </button>
                      <button
                        className="min-h-11 rounded-full bg-[var(--primary)] px-4 py-2 text-sm font-bold text-[var(--primary-contrast)]"
                        type="button"
                        onClick={() => healMutation.mutate(String(injury.id))}
                      >
                        {i18n("markHealed65e6ef9")}
                      </button>
                    </>
                  ) : (
                    <button
                      className="min-h-11 rounded-full border border-[var(--border)] px-4 py-2 text-sm font-bold"
                      type="button"
                      onClick={() => reopenMutation.mutate(String(injury.id))}
                    >
                      {t("reopen")}
                    </button>
                  )}
                </div>
              </div>
              {updatingId === injury.id ? (
                <InjuryUpdateForm
                  injury={injury}
                  pending={updateMutation.isPending}
                  error={updateMutation.error instanceof Error ? localizeError(updateMutation.error, i18n) : null}
                  onSubmit={(update) => updateMutation.mutate({ id: String(injury.id), update })}
                  onCancel={() => setUpdatingId(null)}
                />
              ) : null}
              <InjuryTimeline injury={injury} />
            </article>
          ))}
          <ErrorText error={healMutation.error ?? reopenMutation.error} />
        </section>
      </div>
    </main>
  );
}

function ErrorText({ error }: { error: unknown }) {
  const i18n = useUiTranslations();
  if (!(error instanceof Error)) return null;
  return <ErrorNotice>{localizeError(error, i18n)}</ErrorNotice>;
}
