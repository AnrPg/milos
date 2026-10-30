"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";

import { bringCoach, fetchCoachCandidates, setBoxSenderBlocked, type ChatThread } from "@/api/messaging";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { useUiTranslations } from "@/i18n/ui";

/**
 * The box's inbox on one of its threads (ADR-282): «Φέρε τον coach» brings a
 * coach of the box into the conversation (the person's own coaches first),
 * and a newcomer («Νέος») can be blocked, or unblocked again, from ⋯.
 */
export function BoxThreadActions({
  thread,
  token,
  personName,
  onChanged,
}: {
  thread: ChatThread;
  token: string;
  personName: string;
  onChanged: (thread: ChatThread) => void;
}) {
  const i18n = useUiTranslations();
  const [picking, setPicking] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const blocked = Boolean(thread.box_person?.blocked);

  const block = useMutation({
    mutationFn: (next: boolean) => setBoxSenderBlocked(token, thread.id, next),
    onSuccess: ({ blocked: next }) => {
      setConfirmBlock(false);
      onChanged({ ...thread, box_person: { newcomer: thread.box_person?.newcomer ?? true, blocked: next } });
    },
  });

  return (
    <div className="flex shrink-0 items-center gap-1">
      <button
        type="button"
        onClick={() => setPicking(true)}
        className="min-h-11 rounded-xl px-3 text-xs font-bold"
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        data-testid="box-bring-coach"
      >
        {i18n("inboxBringCoach")}
      </button>
      {thread.box_person?.newcomer ? (
        <MoreMenu
          label={i18n("inboxMoreActions")}
          testId="box-thread-more"
          items={[
            blocked
              ? { label: i18n("inboxUnblock"), onSelect: () => block.mutate(false), testId: "box-unblock" }
              : { label: i18n("inboxBlock"), onSelect: () => setConfirmBlock(true), tone: "danger", testId: "box-block" },
          ]}
        />
      ) : null}

      {picking ? (
        <CoachPicker thread={thread} token={token} onClose={() => setPicking(false)} onBrought={onChanged} />
      ) : null}

      {confirmBlock ? (
        <Dialog onClose={() => setConfirmBlock(false)} title={i18n("inboxBlockTitle", { name: personName })} size="sm" variant="center">
          <div className="flex flex-col gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
            <p>{i18n("inboxBlockHint")}</p>
            {block.isError ? <ErrorNotice>{i18n("inboxActionFailed")}</ErrorNotice> : null}
            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setConfirmBlock(false)}
                className="min-h-11 rounded-xl px-4 text-sm font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {i18n("inboxCancel")}
              </button>
              <button
                type="button"
                disabled={block.isPending}
                onClick={() => block.mutate(true)}
                className="min-h-11 rounded-xl px-4 text-sm font-bold disabled:opacity-50"
                style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                data-testid="box-block-confirm"
              >
                {i18n("inboxBlock")}
              </button>
            </div>
          </div>
        </Dialog>
      ) : null}
    </div>
  );
}

function CoachPicker({
  thread,
  token,
  onClose,
  onBrought,
}: {
  thread: ChatThread;
  token: string;
  onClose: () => void;
  onBrought: (thread: ChatThread) => void;
}) {
  const i18n = useUiTranslations();
  const coaches = useQuery({
    queryKey: ["messaging", "threads", thread.id, "coaches"],
    queryFn: () => fetchCoachCandidates(token, thread.id),
  });
  const bring = useMutation({
    mutationFn: (userId: string) => bringCoach(token, thread.id, userId),
    onSuccess: (updated) => {
      onBrought({ ...thread, participants: updated.participants });
      onClose();
    },
  });
  const rows = coaches.data ?? [];

  return (
    <Dialog onClose={onClose} title={i18n("inboxBringCoach")} size="sm" variant="center">
      <div className="flex flex-col gap-2 text-sm">
        <p style={{ color: "var(--text-soft)" }}>{i18n("inboxBringCoachHint")}</p>
        {coaches.isPending ? <p style={{ color: "var(--dim)" }}>{i18n("inboxLoadingCoaches")}</p> : null}
        {coaches.isSuccess && rows.length === 0 ? <p style={{ color: "var(--dim)" }}>{i18n("inboxNoCoaches")}</p> : null}
        <ul className="flex flex-col">
          {rows.map((coach) => (
            <li key={coach.id}>
              <button
                type="button"
                disabled={coach.in_thread || bring.isPending}
                onClick={() => bring.mutate(coach.id)}
                className="flex min-h-12 w-full items-center justify-between gap-3 rounded-xl px-3 text-start disabled:opacity-60"
                style={{ color: "var(--text)" }}
                data-testid="box-coach-option"
              >
                <span className="min-w-0 truncate font-semibold">{coach.nickname ?? "?"}</span>
                <span className="shrink-0 text-xs" style={{ color: "var(--dim)" }}>
                  {coach.in_thread ? i18n("inboxCoachInThread") : coach.coaches_person ? i18n("inboxCoachTheirs") : null}
                </span>
              </button>
            </li>
          ))}
        </ul>
        {bring.isError ? <ErrorNotice>{i18n("inboxActionFailed")}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
