"use client";

import { useTranslations } from "next-intl";

import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { Select } from "@/components/ui/Select";
import { asksGoodForFriends, asksGuestPass } from "@/lib/event-wizard";

import { formAudience, type EventForm, type EventHostMode } from "../events";
import { CheckRow, FieldGroup, SegmentGrid, fieldClass } from "./fields";
import type { StepProps } from "./types";

type Audience = ReturnType<typeof formAudience>;

/** The audience choice's form fields (ADR-185). */
export function audiencePatch(audience: Audience): Partial<EventForm> {
  if (audience === "group") return { groupOnly: true, openToAll: false };
  return { groupOnly: false, openToAll: audience === "open" };
}

/** The audience options this host offers, with their labels. */
export function useAudienceOptions(mode: EventHostMode) {
  const t = useTranslations("Events");
  return [
    ...(mode === "group" ? [{ value: "group" as const, label: t("whoGroupOnly"), hint: t("whoGroupOnlyHint") }] : []),
    {
      value: "club" as const,
      label: mode === "self" ? t("whoSelfInvite") : mode === "group" ? t("whoClub") : t("membersOnly"),
      hint: mode === "self" ? t("whoSelfInviteHint") : t("membersOnlyHint"),
    },
    { value: "open" as const, label: t("openToAll"), hint: mode === "self" ? t("whoSelfOpenHint") : t("openToAllHint") },
  ];
}

/**
 * Step 5: who can come (the group, the club's members or everyone; for
 * your own event, by invitation or everyone), free or a price paid at the
 * box, guest passes, and «Καλό για φίλους» where a friend can come.
 */
export function WhoStep({ form, set, mode, problems }: StepProps) {
  const t = useTranslations("Events");
  const audience = formAudience(form, mode);
  const options = useAudienceOptions(mode);

  return (
    <div className="flex flex-col gap-5">
      <FieldGroup legend={t("fieldWho")}>
        <SegmentGrid label={t("fieldWho")} value={audience} onChange={(value) => set(audiencePatch(value))} options={options} />
      </FieldGroup>

      <FieldGroup legend={t("fieldPrice")}>
        <SegmentGrid
          label={t("fieldPrice")}
          value={form.paid ? "paid" : "free"}
          onChange={(value) => set({ paid: value === "paid" })}
          options={[
            { value: "free", label: t("free") },
            { value: "paid", label: t("paid"), hint: t("paidHint") },
          ]}
        />
        {form.paid ? (
          <Field label={t("fieldAmount")}>
            <input
              inputMode="decimal"
              value={form.price}
              aria-invalid={Boolean(form.price) && problems.includes("price")}
              onChange={(event) => set({ price: event.target.value.replace(/[^\d.,]/g, "").slice(0, 8) })}
              placeholder="15"
              className={fieldClass}
              style={inputStyle}
            />
          </Field>
        ) : null}
      </FieldGroup>

      {asksGuestPass(form, mode) ? (
        <div className="flex flex-col gap-2">
          <CheckRow checked={form.guestPass} onChange={(checked) => set({ guestPass: checked })}>
            {t("fieldGuestPass")}
          </CheckRow>
          {form.guestPass ? (
            <Field label={t("fieldGuestsPerMember")}>
              <Select value={form.guestsPerMember} onValueChange={(value) => set({ guestsPerMember: Number(value) })} className={fieldClass} style={inputStyle}>
                {[1, 2, 3, 4, 5].map((count) => (
                  <option key={count} value={count}>
                    {t("guestsCount", { count })}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
        </div>
      ) : null}

      {asksGoodForFriends(form, mode) ? (
        <CheckRow checked={form.goodForFriends} onChange={(checked) => set({ goodForFriends: checked })} hint={t("goodForFriendsHint")}>
          {t("fieldGoodForFriends")}
        </CheckRow>
      ) : null}
    </div>
  );
}
