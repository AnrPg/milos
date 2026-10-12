/**
 * ADR-115 personalized member programming: pure UI rules shared by the staff
 * programming dialog, the class card and the member's workout list.
 */

import type { MemberProgrammingMode } from "@/api/admin-users";

/** The order the staff dialog offers member modes in (safest first). */
export const MEMBER_PROGRAMMING_MODES: readonly MemberProgrammingMode[] = [
  "class_variant",
  "personal",
  "class_workout",
];

/** Modes that attach to a class the member booked on the selected day. */
export function modeRequiresBookedClass(mode: MemberProgrammingMode): boolean {
  return mode === "class_variant" || mode === "class_workout";
}

/** Modes that need the member's package to include personal programming. */
export function modeRequiresProgrammingEntitlement(mode: MemberProgrammingMode): boolean {
  return mode === "class_variant" || mode === "personal";
}

/** Translation key for the staff-dialog success message of a programming run. */
export function programmingSuccessKey(
  role: "member" | "athlete" | "admin",
  mode: MemberProgrammingMode,
): string {
  if (role !== "member") return "featurePersonalWodAssigned";
  if (mode === "class_variant") return "memberProgrammingVariantCreated";
  if (mode === "personal") return "memberProgrammingPersonalAssigned";
  return "featureClassWodAttached";
}
