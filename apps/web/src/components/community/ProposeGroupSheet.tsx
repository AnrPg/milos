"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CLUBS_KEY, groupsKey, proposeGroup, type CommunityClub, type GroupJoinPolicy } from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { ChoicePill, ErrorLine, Sheet, SheetButton } from "./Sheet";

/**
 * «Πρότεινε ομάδα» (board 7 Q2): a name, one line about it, and who gets in
 * («Όποιος θέλει» or «Με αίτημα σε μένα»). The creator runs it; when the gym
 * asks for approval it waits for staff first.
 */
export function ProposeGroupSheet({
  club,
  needsApproval,
  onClose,
}: {
  club: Pick<CommunityClub, "id" | "name" | "organization_slug">;
  needsApproval: boolean;
  onClose: () => void;
}) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [policy, setPolicy] = useState<GroupJoinPolicy>("open");

  const propose = useMutation({
    mutationFn: () =>
      proposeGroup(tokens!.access_token, club.organization_slug!, {
        name: name.trim(),
        description: description.trim() || null,
        join_policy: policy,
      }),
    onSuccess: (group) => {
      void queryClient.invalidateQueries({ queryKey: groupsKey(club.id) });
      void queryClient.invalidateQueries({ queryKey: CLUBS_KEY });
      if (group.status === "active") {
        onClose();
        router.push(`/clubs/${club.id}/groups/${group.id}`);
      }
    },
  });

  const waiting = propose.data?.status === "pending";
  return (
    <Sheet
      labelId="propose-group"
      guide="club.groupSheet"
      eyebrow={club.name}
      title={waiting ? t("proposeSentTitle") : t("proposeTitle")}
      onClose={onClose}
      footer={
        waiting ? (
          <SheetButton primary onClick={onClose}>{t("ok")}</SheetButton>
        ) : (
          <>
            <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
            <SheetButton primary type="submit" form="propose-group-form" disabled={name.trim().length < 2 || propose.isPending}>
              {propose.isPending ? t("sending") : needsApproval ? t("proposeSend") : t("proposeCreate")}
            </SheetButton>
          </>
        )
      }
    >
      {waiting ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("proposeSentBody")}</p>
      ) : (
        <form
          id="propose-group-form"
          className="flex flex-col gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (name.trim().length >= 2) propose.mutate();
          }}
        >
          <Field label={t("groupName")}>
            <input
              value={name}
              maxLength={60}
              required
              onChange={(event) => setName(event.target.value)}
              placeholder={t("groupNamePlaceholder")}
              className="min-h-11 rounded-2xl px-3 text-sm font-normal"
              style={inputStyle}
            />
          </Field>
          <Field label={t("groupAbout")}>
            <input
              value={description}
              maxLength={200}
              onChange={(event) => setDescription(event.target.value)}
              placeholder={t("groupAboutPlaceholder")}
              className="min-h-11 rounded-2xl px-3 text-sm font-normal"
              style={inputStyle}
            />
          </Field>
          <JoinPolicyPicker value={policy} onChange={setPolicy} />
          <p className="text-xs" style={{ color: "var(--dim)" }}>{needsApproval ? t("proposeApprovalNote") : t("proposeFreeNote")}</p>
          <ErrorLine message={propose.error ? clientErrorMessage(propose.error, tUi) : null} />
        </form>
      )}
    </Sheet>
  );
}

export const inputStyle = { background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" } as const;

export function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
      {label}
      {children}
    </label>
  );
}

export function JoinPolicyPicker({ value, onChange }: { value: GroupJoinPolicy; onChange: (value: GroupJoinPolicy) => void }) {
  const t = useTranslations("Clubs");
  return (
    <fieldset className="flex flex-col gap-1">
      <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("groupWhoJoins")}</legend>
      <div role="radiogroup" aria-label={t("groupWhoJoins")} className="flex gap-2">
        <ChoicePill selected={value === "open"} onSelect={() => onChange("open")} hint={t("joinOpenHint")}>
          {t("joinOpen")}
        </ChoicePill>
        <ChoicePill selected={value === "request"} onSelect={() => onChange("request")} hint={t("joinRequestHint")}>
          {t("joinRequest")}
        </ChoicePill>
      </div>
    </fieldset>
  );
}
