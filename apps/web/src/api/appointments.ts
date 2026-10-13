import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type SlotsResponse =
  paths["/api/org/{organization_slug}/me/appointments/slots"]["get"]["responses"][200]["content"]["application/json"];
type AppointmentsResponse =
  paths["/api/org/{organization_slug}/me/appointments"]["get"]["responses"][200]["content"]["application/json"];

export type OfferedSlot = SlotsResponse["slots"][number];
export type AppointmentBooking = AppointmentsResponse["appointments"][number];

/** Fields of the slot embedded in a booking (the schema leaves it open). */
export type BookingSlot = {
  id?: string;
  coach_id?: string;
  coach_nickname?: string | null;
  kind?: "pt_session" | "assessment";
  format?: "one_to_one" | "semi_private";
  starts_at?: string;
  duration_minutes?: number;
  location_id?: string | null;
  notes?: string | null;
  cancelled_at?: string | null;
};

export function bookingSlot(booking: AppointmentBooking): BookingSlot | null {
  return (booking.slot as BookingSlot | null | undefined) ?? null;
}

export async function fetchOfferedSlots(token: string): Promise<OfferedSlot[]> {
  const data = await apiRequest<SlotsResponse>("/me/appointments/slots", { token });
  return data.slots;
}

export async function fetchMyAppointments(token: string): Promise<AppointmentBooking[]> {
  const data = await apiRequest<AppointmentsResponse>("/me/appointments", { token });
  return data.appointments;
}

export async function bookAppointment(token: string, slotId: string): Promise<AppointmentBooking> {
  const data = await apiRequest<{ appointment: AppointmentBooking }>("/me/appointments", {
    method: "POST",
    token,
    body: { slot_id: slotId },
  });
  return data.appointment;
}

/** Inside the cancellation cutoff the session is used (late cancellation). */
export async function cancelAppointment(token: string, id: string): Promise<AppointmentBooking> {
  const data = await apiRequest<{ appointment: AppointmentBooking }>(
    `/me/appointments/${encodeURIComponent(id)}/cancel`,
    { method: "POST", token },
  );
  return data.appointment;
}
