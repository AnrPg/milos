import { ApiError } from "@/api/client";
import { can, membershipRoles, type MembershipLike } from "@/lib/role-navigation";

// Pure helpers for the role-aware staff home (ADR-103,
// docs/architecture/navigation-by-role.md): which home a membership gets,
// the sections it is made of, and the role-related API errors.

export type StaffHomeSection = "coach" | "front_desk" | "accountant" | "cleaning";

export type StaffHomeLayout =
  | { kind: "loading" }
  | { kind: "admin"; coach: boolean }
  | { kind: "cleaning" }
  | { kind: "sections"; sections: StaffHomeSection[] };

const CLEANING_ONLY = new Set(["record_cleaning", "report_inventory"]);
const SECTION_ORDER: StaffHomeSection[] = ["coach", "front_desk", "accountant"];

export function staffHomeLayout(membership: MembershipLike | null | undefined): StaffHomeLayout {
  if (!membership) return { kind: "loading" };
  const roles = membershipRoles(membership);

  if (can(membership, "grant_staff_roles")) return { kind: "admin", coach: roles.includes("coach") };

  const capabilities = Object.keys(membership.capabilities ?? {});
  if (
    can(membership, "record_cleaning") &&
    capabilities.every((capability) => CLEANING_ONLY.has(capability))
  ) {
    return { kind: "cleaning" };
  }

  const sections: StaffHomeSection[] = SECTION_ORDER.filter((section) => roles.includes(section));
  if (roles.includes("janitor") && can(membership, "record_cleaning")) sections.push("cleaning");
  return { kind: "sections", sections };
}

/** Role and coaching-relationship API errors (ADR-099, ADR-100, ADR-101) and their Ui keys. */
export const ROLE_ERROR_KEYS: Record<string, string> = {
  only_athletes_self_assigned: "rhErrOnlyAthletes",
  not_a_coach: "rhErrNotACoach",
  not_a_client: "rhErrNotAClient",
  not_your_client: "rhErrNotYourClient",
};

export function roleErrorKey(error: unknown): string | null {
  if (!(error instanceof ApiError)) return null;
  const code = error.payload.code;
  return code ? (ROLE_ERROR_KEYS[code] ?? null) : null;
}

/** Gym staff who can be chosen as a coach, by nickname. */
export function coachOptions<T extends { role: string; roles?: readonly string[] | null; nickname?: string | null }>(staff: T[]): T[] {
  return staff
    .filter((member) => (member.roles?.length ? member.roles : [member.role]).includes("coach"))
    .sort((a, b) => (a.nickname ?? "").localeCompare(b.nickname ?? ""));
}

/** Athletes a coach could still take: not already one of theirs. */
export function takeableAthletes<T extends { id: string }>(athletes: T[], clientIds: Iterable<string>): T[] {
  const taken = new Set(clientIds);
  return athletes.filter((athlete) => !taken.has(athlete.id));
}

/** Classes `coachUserId` coaches that start on the same local day as `now`, earliest first. */
export function classesCoachedToday<T extends { scheduled_at: string; coach_user_id?: string | null }>(
  slots: T[],
  coachUserId: string | null | undefined,
  now: Date = new Date(),
): T[] {
  if (!coachUserId) return [];
  return slots
    .filter((slot) => {
      if (slot.coach_user_id !== coachUserId) return false;
      const start = new Date(slot.scheduled_at);
      return (
        start.getFullYear() === now.getFullYear() &&
        start.getMonth() === now.getMonth() &&
        start.getDate() === now.getDate()
      );
    })
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));
}
