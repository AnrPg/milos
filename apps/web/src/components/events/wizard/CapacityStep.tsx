"use client";

import { useId, useState } from "react";
import { useTranslations } from "next-intl";

import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { asksCohosts, cohostInputProblem, MAX_COHOSTS } from "@/lib/event-wizard";

import { formAudience } from "../events";
import { FieldGroup, Hint, fieldClass } from "./fields";
import type { StepProps } from "./types";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Step 6: how many places (empty: no limit), and ADR-185 co-hosts. When
 * the caller can send invites, the businesses listed here are asked right
 * after the event is published; otherwise a note says where to add them.
 */
export function CapacityStep({
  form,
  set,
  mode,
  context,
  problems,
  cohosts,
  ownSlug,
  onAddCohost,
  onRemoveCohost,
}: StepProps & {
  cohosts: string[];
  ownSlug: string | null;
  onAddCohost: (raw: string) => void;
  onRemoveCohost: (slug: string) => void;
}) {
  const t = useTranslations("Events");
  const tw = useTranslations("EventWizard");
  const [draft, setDraft] = useState("");
  const [tried, setTried] = useState(false);
  const hintId = useId();
  const errorId = useId();
  const inputProblem = draft.trim() ? cohostInputProblem(draft, cohosts, ownSlug) : null;
  const groupOnly = formAudience(form, mode) === "group";
  const cohostsHere = asksCohosts(form, context);
  // Editing a business's or club's event: its co-hosts are managed on the event's page.
  const cohostsLater = context.editing && mode !== "self" && !groupOnly;

  function add() {
    setTried(true);
    if (!draft.trim() || inputProblem) return;
    onAddCohost(draft);
    setDraft("");
    setTried(false);
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <Field label={t("fieldCapacity")}>
          <input
            inputMode="numeric"
            value={form.capacity}
            aria-invalid={problems.includes("capacity")}
            aria-describedby={hintId}
            onChange={(event) => set({ capacity: event.target.value.replace(/\D/g, "").slice(0, 5) })}
            placeholder={t("fieldCapacityPlaceholder")}
            className={fieldClass}
            style={inputStyle}
          />
        </Field>
        <Hint id={hintId}>{tw("capacityHint")}</Hint>
      </div>

      {cohostsHere ? (
        <FieldGroup legend={tw("cohostsTitle")}>
          <Hint>{tw("cohostsHint")}</Hint>
          {cohosts.length > 0 ? (
            <ul className="flex flex-col gap-2" aria-label={tw("cohostsTitle")}>
              {cohosts.map((slug) => (
                <li
                  key={slug}
                  className="flex min-h-11 items-center gap-2 rounded-2xl px-3"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
                >
                  <span className="min-w-0 grow truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {slug}
                  </span>
                  <button
                    type="button"
                    onClick={() => onRemoveCohost(slug)}
                    aria-label={tw("cohostRemove", { name: slug })}
                    className="min-h-11 shrink-0 px-2 text-sm font-semibold underline"
                    style={{ color: "var(--text-soft)" }}
                  >
                    {t("coverRemove")}
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
          {cohosts.length < MAX_COHOSTS ? (
            <div className="flex items-end gap-2">
              <span className="min-w-0 grow">
                <Field label={tw("cohostSlug")}>
                  <input
                    value={draft}
                    maxLength={200}
                    autoCapitalize="none"
                    autoCorrect="off"
                    spellCheck={false}
                    aria-invalid={tried && Boolean(inputProblem)}
                    aria-describedby={tried && inputProblem ? errorId : undefined}
                    onChange={(event) => setDraft(event.target.value)}
                    onKeyDown={(event) => {
                      // Enter adds the business instead of moving to the next step.
                      if (event.key === "Enter") {
                        event.preventDefault();
                        add();
                      }
                    }}
                    placeholder={tw("cohostSlugPlaceholder")}
                    className={fieldClass}
                    style={inputStyle}
                  />
                </Field>
              </span>
              <button
                type="button"
                onClick={add}
                disabled={!draft.trim()}
                className="min-h-11 shrink-0 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
                style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
              >
                {tw("cohostAdd")}
              </button>
            </div>
          ) : null}
          {tried && inputProblem ? (
            <ErrorNotice id={errorId} variant="field">
              {tw(inputProblem, { count: MAX_COHOSTS })}
            </ErrorNotice>
          ) : cohosts.length >= MAX_COHOSTS ? (
            <Hint>{tw("cohost_limit", { count: MAX_COHOSTS })}</Hint>
          ) : null}
        </FieldGroup>
      ) : cohostsLater ? (
        <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text-soft)", border: "1px solid var(--border)" }}>
          {tw("cohostsOnEventPage")}
        </p>
      ) : null}
    </div>
  );
}
