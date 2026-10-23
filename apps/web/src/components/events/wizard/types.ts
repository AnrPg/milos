import type { EventForm, EventHostMode } from "@/components/events/events";
import type { EventWizardContext, WizardProblem } from "@/lib/event-wizard";

/** «Διοργάνωση ως» (ADR-185): the hosts to pick from, as the caller resolved them. */
export type EventWizardHosts = {
  options: { id: string; label: string; hint?: string }[];
  value: string;
  onChange: (id: string) => void;
};

/** The clubs the chosen host can put the event in. */
export type EventWizardClubs = {
  options: { id: string; name: string }[];
  value: string | undefined;
  onChange: (id: string) => void;
};

/**
 * ADR-185 co-hosts asked as the event is published (business or club hosts
 * whose caller runs events there): the create request carries them.
 */
export type EventWizardCohosts = {
  /** The host's own page address: it cannot co-host its own event. */
  ownSlug: string | null;
};

/** What every step gets. */
export type StepProps = {
  form: EventForm;
  set: (patch: Partial<EventForm>) => void;
  mode: EventHostMode;
  context: EventWizardContext;
  /** What this step still needs (shown by the shell next to Next). */
  problems: WizardProblem[];
};
