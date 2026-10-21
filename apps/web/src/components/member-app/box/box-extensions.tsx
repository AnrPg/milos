import type { ComponentType } from "react";

import type { OrganizationMembership } from "@/api/organizations";
import type { ProviderKind } from "@/api/settings";

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

/**
 * Sections other features add to Box (ADR-170), rendered in order after the
 * membership or session-package card and before announcements. A feature
 * plugs in with one entry here instead of editing either layout; each
 * component decides on its own whether it has anything to show.
 */
export const BOX_EXTENSIONS: BoxExtension[] = [];

export function boxExtensionsFor(kind: ProviderKind, extensions: BoxExtension[] = BOX_EXTENSIONS) {
  return extensions.filter((extension) => extension.kinds.includes(kind));
}
