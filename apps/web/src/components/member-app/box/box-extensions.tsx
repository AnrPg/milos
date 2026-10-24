"use client";

import type { ComponentType } from "react";

import type { OrganizationMembership } from "@/api/organizations";
import type { ProviderKind } from "@/api/settings";
import { SquadsBoxSection } from "@/components/community/squads/SquadsSection";
import { CoachClientsBoxExtension } from "@/components/member-app/box/CoachClients";
import { ShopBoxCard } from "@/components/shop/ShopBoxCard";

export type BoxExtensionProps = {
  membership: OrganizationMembership;
  providerKind: ProviderKind;
};

export type BoxExtension = {
  id: string;
  /** Which Box layouts render it (ADR-170): a gym's, an independent coach's, or both. */
  kinds: ProviderKind[];
  Component: ComponentType<BoxExtensionProps>;
};

/** PT squads (ADR-168): invitations and squads; a solo coach also runs theirs here. */
function SquadsBoxExtension({ membership, providerKind }: BoxExtensionProps) {
  return <SquadsBoxSection membership={membership} showCoach={providerKind === "coach"} />;
}

/**
 * Sections other features add to Box (ADR-170), rendered in order after the
 * membership or session-package card and before announcements. A feature
 * plugs in with one entry here instead of editing either layout; each
 * component decides on its own whether it has anything to show.
 */
export const BOX_EXTENSIONS: BoxExtension[] = [
  // ADR-190: the shop card sits right below Συνδρομή, only while the box sells something.
  { id: "shop", kinds: ["gym", "coach"], Component: ShopBoxCard },
  { id: "squads", kinds: ["gym", "coach"], Component: SquadsBoxExtension },
  // ADR-198: «Πελάτες μου», only for someone who coaches at this provider.
  { id: "coach-clients", kinds: ["gym", "coach"], Component: CoachClientsBoxExtension },
];

export function boxExtensionsFor(kind: ProviderKind, extensions: BoxExtension[] = BOX_EXTENSIONS) {
  return extensions.filter((extension) => extension.kinds.includes(kind));
}
