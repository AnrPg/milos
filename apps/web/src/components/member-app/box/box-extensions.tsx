"use client";

import type { ComponentType } from "react";

import { SquadsBoxSection } from "@/components/community/squads/SquadsSection";
import type { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Box extensions: sections other features add to Box without editing it.
 * BoxHub renders every extension whose `kinds` include the provider's kind,
 * after the membership card and before the announcements.
 */
export type ProviderKind = "gym" | "coach";
export type SelectedMembership = ReturnType<typeof useSelectedMembershipRole>["membership"];
export type BoxExtensionProps = { membership: SelectedMembership; providerKind: ProviderKind };
export type BoxExtension = { id: string; kinds: ProviderKind[]; Component: ComponentType<BoxExtensionProps> };

/** PT squads (ADR-168): invitations and squads; a solo coach also runs theirs here. */
function SquadsBoxExtension({ membership, providerKind }: BoxExtensionProps) {
  return <SquadsBoxSection membership={membership} showCoach={providerKind === "coach"} />;
}

export const BOX_EXTENSIONS: BoxExtension[] = [{ id: "squads", kinds: ["gym", "coach"], Component: SquadsBoxExtension }];
