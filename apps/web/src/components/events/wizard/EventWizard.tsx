"use client";

import { useEffect, useId, useMemo, useReducer, useRef, useState, type FormEvent } from "react";
import { useMutation } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import type { EventCohostFailure, EventScope } from "@/api/events";
import { ErrorLine } from "@/components/community/Sheet";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import {
  activeSteps,
  asksCohosts,
  canVisit,
  clockForm,
  eventWizardReducer,
  initialWizardState,
  previousStep,
  stepProblems,
  type EventWizardContext,
  type EventWizardStep,
} from "@/lib/event-wizard";
import { useOrganizationTimeZoneStatus } from "@/lib/organization-slug";
import { formatInZone } from "@/lib/zoned-time";

import type { EventLocation } from "../EventFormParts";
import { useEventError } from "../EventParts";
import { EVENT_ERROR_CODES, eventRequest, type EventForm, type EventHostMode } from "../events";
import { BasicsStep } from "./BasicsStep";
import { CapacityStep } from "./CapacityStep";
import { HostStep } from "./HostStep";
import { ReviewStep } from "./ReviewStep";
import type { EventWizardClubs, EventWizardCohosts, EventWizardHosts, StepProps } from "./types";
import { useEventWizardDraft } from "./useEventWizardDraft";
import { WhenStep } from "./WhenStep";
import { WhereStep } from "./WhereStep";
import { WhoStep } from "./WhoStep";
import { WizardStepBar } from "./WizardStepBar";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { guideAnchor } from "@/lib/guides/anchors";

/** The create or edit body; a new event may carry the co-hosts to ask with it (ADR-185). */
export type EventRequestBody = ReturnType<typeof eventRequest> & { cohost_slugs?: string[] };
export type { EventCohostFailure };

/**
 * «Νέο event» and editing as a wizard, one decision per screen (owner
 * decision 2026-10-23, replacing the long sheet of board 8 Q1): host,
 * basics, when, where, who and price, places and co-hosts, review.
 *
 * - The step bar shows progress and goes back to any visited step; Back
 *   and Next stay at the bottom, and Next says why it cannot go on yet
 *   (lib/event-wizard holds the steps, their checks and the reducer).
 * - A new event's draft is kept on this device per host (`draftKey`) and
 *   offered again when the wizard opens for that host.
 * - Editing opens on the review (or `startStep`), keeps the event's host,
 *   and a weekly event asks: this one, or this and the following.
 * - Full screen on a phone, a dialog from `sm` up (ui/Dialog «screen»);
 *   the member app's bottom bar steps aside while it is open.
 * - `cohosts` lets a business or club host ask co-hosts as it publishes
 *   (ADR-185): the addresses go with the create request as
 *   `cohost_slugs`, and the API writes the event and every request in one
 *   transaction (ADR-185). `onSubmit` returns the addresses it could not
 *   ask, which the wizard lists once the event is out.
 */
export function EventWizard({
  title,
  eyebrow,
  initial,
  initialCoverUrl = null,
  editing = null,
  group = false,
  mode = group ? "group" : "club",
  hosts = null,
  hostHint = null,
  locations,
  clubs = null,
  coverSlug = null,
  gymSlug = null,
  draftKey = null,
  startStep = null,
  cohosts: cohostApi = null,
  onSubmit,
  onClose,
}: {
  title: string;
  eyebrow?: string;
  initial: EventForm;
  initialCoverUrl?: string | null;
  editing?: { seriesId: string | null } | null;
  group?: boolean;
  mode?: EventHostMode;
  /** «Διοργάνωση ως» (ADR-185); the host step shows when there is more than one. */
  hosts?: EventWizardHosts | null;
  hostHint?: string | null;
  locations: EventLocation[];
  clubs?: EventWizardClubs | null;
  /** The box whose photos the cover goes to; no cover without one. */
  coverSlug?: string | null;
  /** ADR-179: the event's gym, whose clock the date and time are read on. */
  gymSlug?: string | null;
  /** Where this host's draft is kept on the device; null keeps none (always when editing). */
  draftKey?: string | null;
  /** Editing: open on this step instead of the review. */
  startStep?: EventWizardStep | null;
  cohosts?: EventWizardCohosts | null;
  onSubmit: (body: EventRequestBody, scope: EventScope) => Promise<{ cohostFailures?: EventCohostFailure[] } | void>;
  onClose: () => void;
}) {
  const t = useTranslations("Events");
  const tw = useTranslations("EventWizard");
  const locale = useLocale();
  const eventError = useEventError();
  const gym = useOrganizationTimeZoneStatus(gymSlug);
  const isEditing = Boolean(editing);
  // Callers pass a fresh array while loading; compare the ids, not the array.
  const locationKey = locations.map((location) => location.id).join("\n");
  const locationIds = useMemo(() => (locationKey ? locationKey.split("\n") : []), [locationKey]);
  const context: EventWizardContext = useMemo(
    () => ({
      mode,
      editing: isEditing,
      hostChoices: hosts?.options.length ?? 0,
      clubChoices: clubs?.options.length ?? 0,
      cohostsAtCreate: Boolean(cohostApi),
      gymTimeZone: gym.zone,
      locationIds: locationIds.length ? locationIds : null,
    }),
    [mode, isEditing, hosts?.options.length, clubs?.options.length, cohostApi, gym.zone, locationIds],
  );
  const [blank] = useState(initial);
  const [state, dispatch] = useReducer(eventWizardReducer, undefined, () =>
    initialWizardState(initial, context, { startStep, coverUrl: initialCoverUrl }),
  );
  const draft = useEventWizardDraft(isEditing ? null : draftKey, state, blank);

  // A new host or newly loaded branches adjust the defaults (while rendering, not in an effect).
  const [seen, setSeen] = useState({ mode, locationKey });
  if (seen.mode !== mode || seen.locationKey !== locationKey) {
    setSeen({ mode, locationKey });
    if (seen.mode !== mode) dispatch({ type: "modeChanged", mode });
    if (seen.locationKey !== locationKey) dispatch({ type: "locationsArrived", locationIds, editing: isEditing });
  }

  const steps = activeSteps(context);
  const step = steps.includes(state.step) ? state.step : steps[0];
  const now = new Date();
  const problems = stepProblems(step, state.form, context, now);
  const reason = problems.length ? t(["problem", problems[0]].join("_")) : null;
  const previous = previousStep({ ...state, step }, context);
  const [uploading, setUploading] = useState(false);
  const [failures, setFailures] = useState<EventCohostFailure[] | null>(null);
  const [nudged, setNudged] = useState(false);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const reasonId = useId();
  const headingId = useId();
  const firstRender = useRef(true);

  // Each new step: focus its heading so keyboards and screen readers start there.
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    headingRef.current?.focus();
  }, [step]);

  const save = useMutation({
    mutationFn: async () => {
      const body: EventRequestBody = eventRequest(clockForm(state.form, context), { mode, editing: isEditing, gymTimeZone: gym.zone });
      // One request: the event and its co-host requests are written together, or neither.
      if (cohostApi && asksCohosts(state.form, context) && state.cohosts.length > 0) body.cohost_slugs = state.cohosts;
      const created = await onSubmit(body, state.scope);
      return (created && created.cohostFailures) || [];
    },
    onSuccess: (failed) => {
      draft.clear();
      if (failed.length) setFailures(failed);
      else onClose();
    },
  });

  const stepLabel = (value: EventWizardStep) =>
    value === "capacity" && asksCohosts(state.form, context) ? tw("step_capacityCohosts") : tw(["step", value].join("_"));
  const heading =
    step === "review" ? tw(isEditing ? "heading_reviewEdit" : "heading_review") : step === "capacity" && asksCohosts(state.form, context) ? tw("heading_capacityCohosts") : tw(["heading", step].join("_"));
  const busy = save.isPending || uploading;

  function advance() {
    if (busy) return;
    if (problems.length) {
      setNudged(true);
      return;
    }
    setNudged(false);
    if (step === "review") save.mutate();
    else dispatch({ type: "next", context, now: new Date() });
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (failures) onClose();
    else advance();
  }

  const stepProps: StepProps = {
    form: state.form,
    set: (patch) => dispatch({ type: "set", patch }),
    mode,
    context,
    problems,
  };
  const hostLabel = hosts?.options.find((option) => option.id === hosts.value)?.label ?? null;
  const clubLabel = clubs?.options.find((club) => club.id === clubs.value)?.name ?? null;

  const primaryLabel = failures
    ? tw("done")
    : step === "review"
      ? save.isPending
        ? tw(isEditing ? "saving" : "publishing")
        : isEditing
          ? t("save")
          : t("publish")
      : state.returnToReview
        ? tw("backToReview")
        : tw("next");

  return (
    <Dialog
      onClose={onClose}
      title={title}
      eyebrow={eyebrow}
      variant="screen"
      size="2xl"
      guide="events.wizard"
      dismissible={!save.isPending}
      plainBody
      onSubmit={submit}
      footer={
        <div className="flex w-full flex-col gap-2">
          {!failures && reason && nudged ? (
            <ErrorNotice id={reasonId} variant="field">
              {reason}
            </ErrorNotice>
          ) : null}
          {!failures && reason && !nudged ? (
            <p id={reasonId} className="text-xs" style={{ color: "var(--dim)" }}>
              {reason}
            </p>
          ) : null}
          <div className="flex w-full gap-2">
            {failures ? null : previous ? (
              <DialogButton onClick={() => dispatch({ type: "back", context })} className="flex-1" disabled={save.isPending}>
                {tw("back")}
              </DialogButton>
            ) : (
              <DialogButton onClick={onClose} className="flex-1">
                {t("cancel")}
              </DialogButton>
            )}
            <button
              {...guideAnchor("events.wizard.next")}
              type="submit"
              aria-disabled={(!failures && (Boolean(reason) || busy)) || undefined}
              aria-describedby={!failures && reason ? reasonId : undefined}
              className="min-h-11 flex-1 rounded-full px-5 text-sm font-semibold transition-opacity aria-disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {primaryLabel}
            </button>
          </div>
        </div>
      }
    >
      {failures ? (
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-4 sm:px-6">
          <div role="status" className="flex flex-col gap-3">
            <h3 ref={headingRef} tabIndex={-1} className="text-lg font-semibold outline-none" style={{ color: "var(--text)" }}>
              {tw("publishedTitle")}
            </h3>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{tw("cohostsPartial")}</p>
            <ul className="flex flex-col gap-2">
              {failures.map((failure) => (
                <li key={failure.slug} className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
                  <span className="font-semibold">{failure.slug}</span>
                  <ErrorNotice variant="text">
                    {(EVENT_ERROR_CODES as readonly string[]).includes(failure.code) ? t(["err", failure.code].join("_")) : tw("cohostNotSent")}
                  </ErrorNotice>
                </li>
              ))}
            </ul>
          </div>
        </div>
      ) : (
        <>
          <div {...guideAnchor("events.wizard.steps")} className="shrink-0 px-5 pb-2 sm:px-6">
            <WizardStepBar
              steps={steps}
              current={step}
              visited={state.visited}
              label={stepLabel}
              canVisit={(target) => !busy && canVisit(state, target, context)}
              onVisit={(target) => dispatch({ type: "goto", step: target, context })}
            />
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-4 sm:px-6">
            {draft.offer ? (
              <div role="region" aria-label={tw("draftFound")} className="mb-4 flex flex-col gap-2 rounded-2xl px-4 py-3" style={{ background: "color-mix(in srgb, var(--primary) 10%, var(--panel))", border: "1px solid var(--primary)" }}>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{tw("draftFound")}</p>
                <p className="text-sm" style={{ color: "var(--text-soft)" }}>
                  {draft.offer.form.title.trim()
                    ? tw("draftBodyTitled", { title: draft.offer.form.title.trim(), when: formatInZone(draft.offer.savedAt, null, locale, "day-time") })
                    : tw("draftBody", { when: formatInZone(draft.offer.savedAt, null, locale, "day-time") })}
                </p>
                <div className="grid grid-cols-2 gap-2">
                  <DialogButton onClick={draft.discard}>{tw("draftDiscard")}</DialogButton>
                  <DialogButton
                    tone="primary"
                    onClick={() => {
                      dispatch({ type: "restore", draft: draft.offer!, context });
                      draft.dismiss();
                    }}
                  >
                    {tw("draftResume")}
                  </DialogButton>
                </div>
              </div>
            ) : null}
            <section {...guideAnchor("events.wizard.body")} aria-labelledby={headingId} className="flex flex-col gap-4">
              <h3 id={headingId} ref={headingRef} tabIndex={-1} className="text-lg font-semibold outline-none" style={{ color: "var(--text)" }}>
                {heading}
              </h3>
              {step === "host" ? <HostStep hosts={hosts} hint={hostHint} clubs={clubs} /> : null}
              {step === "basics" ? (
                <BasicsStep
                  {...stepProps}
                  coverSlug={coverSlug}
                  coverUrl={state.coverUrl}
                  onCover={(mediaId, url) => dispatch({ type: "cover", mediaId, url })}
                  onUploading={setUploading}
                />
              ) : null}
              {step === "when" ? <WhenStep {...stepProps} gym={gym} /> : null}
              {step === "where" ? <WhereStep {...stepProps} locations={locations} /> : null}
              {step === "who" ? <WhoStep {...stepProps} /> : null}
              {step === "capacity" ? (
                <CapacityStep
                  {...stepProps}
                  cohosts={state.cohosts}
                  ownSlug={cohostApi?.ownSlug ?? null}
                  onAddCohost={(raw) => dispatch({ type: "addCohost", raw, ownSlug: cohostApi?.ownSlug ?? null })}
                  onRemoveCohost={(slug) => dispatch({ type: "removeCohost", slug })}
                />
              ) : null}
              {step === "review" ? (
                <ReviewStep
                  {...stepProps}
                  steps={steps}
                  stepLabel={stepLabel}
                  hostLabel={hostLabel}
                  clubLabel={clubLabel}
                  locations={locations}
                  coverUrl={state.coverUrl}
                  cohosts={state.cohosts}
                  gymZone={gym.zone}
                  series={Boolean(editing?.seriesId)}
                  scope={state.scope}
                  onScope={(scope) => dispatch({ type: "scope", scope })}
                  onEdit={(target) => dispatch({ type: "goto", step: target, context })}
                />
              ) : null}
              <ErrorLine message={eventError(save.error)} />
            </section>
            {draft.savedAt && !draft.offer ? (
              <p className="mt-4 text-xs" style={{ color: "var(--dim)" }} aria-live="polite">
                {tw("draftSaved")}
              </p>
            ) : null}
          </div>
        </>
      )}
    </Dialog>
  );
}
