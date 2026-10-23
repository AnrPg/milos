import type { AppointmentBooking, BookingSlot } from "@/api/appointments";
import { bookingSlot } from "@/api/appointments";
import type { OrganizationMembership } from "@/api/organizations";
import type { PlatformPlan, PlanUsage } from "@/api/platform-plans";
import type { ProviderKind } from "@/api/settings";

/**
 * Pure helpers of the solo-coach tier (ADR-170): which Box layout a provider
 * gets, the coach's next session, prices that are still placeholders, plan
 * usage tones and whether the account already runs a practice.
 */

export type BoxLayout = "gym" | "coach";

export function boxLayoutFor(kind: ProviderKind | null | undefined): BoxLayout {
  return kind === "coach" ? "coach" : "gym";
}

/** «Νίκος Π. · Personal coach» (vision §7.10); a gym keeps its own name. */
export function boxTitle(name: string, layout: BoxLayout, coachLabel: string) {
  return layout === "coach" ? `${name} · ${coachLabel}` : name;
}

/** The member's next booked session with this coach, still running or upcoming. */
export function nextAppointment(
  appointments: AppointmentBooking[],
  now: Date,
): { booking: AppointmentBooking; slot: BookingSlot & { starts_at: string } } | null {
  let best: { booking: AppointmentBooking; slot: BookingSlot & { starts_at: string } } | null = null;
  for (const booking of appointments) {
    if (booking.status !== "booked") continue;
    const slot = bookingSlot(booking);
    if (!slot?.starts_at || slot.cancelled_at) continue;
    const ends = new Date(slot.starts_at).getTime() + (slot.duration_minutes ?? 60) * 60_000;
    if (ends <= now.getTime()) continue;
    if (!best || new Date(slot.starts_at) < new Date(best.slot.starts_at)) {
      best = { booking, slot: slot as BookingSlot & { starts_at: string } };
    }
  }
  return best;
}

/** A price people may see: only a confirmed one, formatted; null otherwise. */
export function shownMonthlyPrice(plan: PlatformPlan | null | undefined, locale: string): string | null {
  if (!plan || plan.price_status !== "confirmed" || plan.monthly_price_cents == null) return null;
  return formatCents(plan.monthly_price_cents, plan.currency, locale);
}

export function formatCents(cents: number, currency: string, locale: string) {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
  }).format(cents / 100);
}

export type UsageTone = "ok" | "warn" | "full";

export function usageTone(usage: PlanUsage): UsageTone {
  if (usage.state === "reached" || usage.state === "over") return usage.hard ? "full" : "warn";
  return usage.state === "near" ? "warn" : "ok";
}

/** Share of the limit used, 0..1, or null when unlimited. */
export function usageShare(usage: PlanUsage): number | null {
  if (usage.limit == null || usage.limit <= 0) return null;
  return Math.min(1, usage.used / usage.limit);
}

/** Whether the account already owns an independent coach's practice. */
/** ADR-184: the account owns a gym or a coach practice (active or in demo mode). */
export function ownsBusiness(memberships: OrganizationMembership[]) {
  return memberships.some(
    (membership) =>
      String(membership.organization.provider_kind ?? "gym") !== "organiser" && (membership.roles ?? [membership.role]).includes("owner"),
  );
}

export function ownsCoachPractice(memberships: OrganizationMembership[]) {
  return memberships.some(
    (membership) =>
      membership.organization.provider_kind === "coach" && (membership.roles ?? [membership.role]).includes("owner"),
  );
}

/** «Team Νίκος» from «Νίκος Παπαδόπουλος», as the API does. */
export function defaultTeamName(name: string) {
  const first = name.trim().split(/\s+/u)[0];
  return `Team ${first || name.trim()}`;
}
