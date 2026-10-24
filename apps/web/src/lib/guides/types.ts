import type { DemoSection } from "@/api/business-accounts";

import type { GuideAnchor } from "./anchors";

/**
 * A walkthrough (ADR-193): short steps over the real screens. Each step
 * says one thing (a title of a few words and one sentence), points at one
 * anchor and, where it helps, asks the person to do it themselves («Tap
 * …») and moves on when they have. The copy lives in messages under
 * `Guides.<guide id>.<step id>`, so every locale has the same guide.
 */
export type GuideId = "shop_staff" | "events_organising" | "finance_offers" | "member_club_event";

export type GuideAudience = "staff" | "member";

/** What the person may see; a guide is listed only when its `requires` holds. */
export type GuideAbilities = {
  /** Holds a staff role in the selected business. */
  staff: boolean;
  /** Owner or admin of the selected business (Finance, offers, the shop catalog). */
  manager: boolean;
  /** The selected business is in demo mode (ADR-184). */
  demo: boolean;
  /** Runs events as themselves or for a business (has the organiser console). */
  hosts: boolean;
  /** A member of at least one box's club (a group lives in one). */
  inGymClub: boolean;
};

/**
 * Where a step lives. `admin` paths take the business's `/org/<slug>`
 * prefix; `:gymClub` in a path is the person's box club.
 */
export type GuideRoute = {
  path: string;
  query?: Record<string, string>;
  admin?: boolean;
};

/**
 * The person's part in a step: tap `target` (Next taps it for them) and the
 * guide goes on once `until` shows or `untilGone` disappears; with neither,
 * the tap itself moves it on.
 */
export type GuideAction = {
  target: GuideAnchor;
  until?: GuideAnchor;
  untilGone?: GuideAnchor;
};

export type GuideStep = {
  /** Copy keys: `<id>.title`, `<id>.body` and, with `tip`, `<id>.tip`. */
  id: string;
  /** The chapter the step belongs to, shown above the title (`chapters.<chapter>`). */
  chapter?: string;
  anchor?: GuideAnchor;
  route?: GuideRoute;
  action?: GuideAction;
  /**
   * Real UI labels the copy quotes, as message paths (`{label}` →
   * "ShopConsole.newProduct"), so «Tap …» always names the button exactly
   * as the screen shows it, in every language.
   */
  labels?: Record<string, string>;
  /** A short insight under the body. */
  tip?: boolean;
  /**
   * When the anchor is not on screen (an empty list, a role without that
   * tab): `center` explains it anyway in the middle (the default), `skip`
   * leaves the step out.
   */
  missing?: "center" | "skip";
  /** Only for people with this ability. */
  requires?: keyof GuideAbilities;
  /** Only for people without this ability. */
  unless?: keyof GuideAbilities;
  /**
   * Tapped when the person goes on from this step (closes the editor the
   * step explained), so the next step starts on a clear screen.
   */
  leave?: GuideAnchor;
};

export type Guide = {
  id: GuideId;
  /** Bumped when the steps change enough to offer the guide again. */
  version: number;
  audience: GuideAudience;
  /** Where the guide starts and is offered on a first visit. */
  home: GuideRoute;
  /** Minutes it takes, shown on the list. */
  minutes: number;
  requires: (abilities: GuideAbilities) => boolean;
  /** Offers demo data first when the business is in demo mode. */
  demoSection?: DemoSection;
  steps: GuideStep[];
};
