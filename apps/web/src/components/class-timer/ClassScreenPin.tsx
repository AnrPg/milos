"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  type BoxScreen,
  type BoxScreenOverrideView,
  classScreensKey,
  listClassScreens,
  pinClassScreen,
  unpinClassScreen,
} from "@/api/box-screens";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { FRESHNESS } from "@/lib/query-policy";

// ADR-253 update 2026-10-29: «Στην οθόνη» on the class timer's remote. The
// class's own coach pins its timer, leaderboard or WOD on a box screen of the
// class's branch (or the whole box), today, and returns it to automatic. The
// API lists only the screens the person may change; with none the action is
// not shown at all.

const COACH_VIEWS: BoxScreenOverrideView[] = ["timer", "leaderboard", "wod"];

export function ClassScreenPin({ token, slotId }: { token: string | undefined; slotId: string }) {
  const t = useTranslations("BoxScreens");
  const [open, setOpen] = useState(false);
  const screens = useQuery({
    queryKey: classScreensKey(slotId),
    enabled: Boolean(token),
    staleTime: FRESHNESS.live,
    retry: false,
    queryFn: () => listClassScreens(token as string, slotId),
  });

  if (!token || !screens.data || screens.data.screens.length === 0) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        data-testid="class-screen-open"
        className="min-h-11 rounded-xl px-3 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
      >
        {t("onScreen")}
      </button>
      {open ? (
        <ClassScreenDialog
          token={token}
          slotId={slotId}
          screens={screens.data.screens}
          views={COACH_VIEWS.filter((view) => screens.data.views.includes(view))}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

function ClassScreenDialog({
  token,
  slotId,
  screens,
  views,
  onClose,
}: {
  token: string;
  slotId: string;
  screens: BoxScreen[];
  views: BoxScreenOverrideView[];
  onClose: () => void;
}) {
  const t = useTranslations("BoxScreens");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const refresh = () => queryClient.invalidateQueries({ queryKey: classScreensKey(slotId) });

  const pin = useMutation({
    mutationFn: ({ screenId, view }: { screenId: string; view: BoxScreenOverrideView }) => pinClassScreen(token, slotId, screenId, { view }),
    onSuccess: refresh,
  });
  const unpin = useMutation({
    mutationFn: (screenId: string) => unpinClassScreen(token, slotId, screenId),
    onSuccess: refresh,
  });
  const failure = pin.error ?? unpin.error;
  const busy = pin.isPending || unpin.isPending;

  return (
    <Dialog
      title={t("onScreenTitle")}
      description={t("onScreenHint")}
      size="md"
      testId="class-screen-dialog"
      error={failure ? localizeError(failure, ui) : null}
      onClose={onClose}
      footer={
        <DialogButton tone="primary" onClick={onClose} testId="class-screen-done">
          {t("done")}
        </DialogButton>
      }
    >
      <ul className="grid gap-3">
        {screens.map((screen) => {
          const override = screen.override;
          const ours = override?.slot_id === slotId;
          return (
            <li
              key={screen.id}
              className="grid gap-3 rounded-2xl p-4"
              style={{ background: "var(--panel-muted)" }}
              data-testid={`class-screen-${screen.id}`}
            >
              <div className="min-w-0">
                <p className="truncate text-base font-bold" style={{ color: "var(--text)" }}>{screen.name}</p>
                <p className="text-sm" style={{ color: "var(--muted)" }} data-testid="class-screen-shows">
                  {t("shows")}{" "}
                  {override
                    ? ours && views.includes(override.view)
                      ? t("pinned", { view: t(`classView.${override.view as "timer" | "leaderboard" | "wod"}`) })
                      : t("pinned", { view: t(`view.${override.view}`) })
                    : t("automatic")}
                </p>
              </div>
              <div role="group" aria-label={t("showOnScreen")} className="flex flex-wrap gap-2">
                {views.map((view) => {
                  const active = ours && override?.view === view;
                  return (
                    <button
                      key={view}
                      type="button"
                      disabled={busy}
                      aria-pressed={active}
                      data-testid={`class-screen-view-${view}`}
                      onClick={() => {
                        unpin.reset();
                        pin.mutate({ screenId: screen.id, view });
                      }}
                      className="min-h-11 rounded-xl px-3 text-sm font-semibold disabled:opacity-40"
                      style={
                        active
                          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                          : { border: "1px solid var(--border)", color: "var(--text-soft)" }
                      }
                    >
                      {t(`classView.${view as "timer" | "leaderboard" | "wod"}`)}
                    </button>
                  );
                })}
              </div>
              {ours ? (
                <button
                  type="button"
                  disabled={busy}
                  data-testid="class-screen-auto"
                  onClick={() => {
                    pin.reset();
                    unpin.mutate(screen.id);
                  }}
                  className="min-h-11 justify-self-start rounded-xl px-3 text-sm font-semibold disabled:opacity-40"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                >
                  {t("backToAuto")}
                </button>
              ) : null}
            </li>
          );
        })}
      </ul>
    </Dialog>
  );
}
