defmodule MilosTraining.Appointments.Domain.TenantDataPolicy do
  @moduledoc """
  Appointments tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "appointments",
            purge_order: 95,
            disposition: :purge,
            basis:
              "Personal-training appointment slots and bookings are operational data with no retention obligation; purged before Facility because slots reference locations.",
            tables: [
              %{table: "appointment_bookings"},
              %{table: "appointment_slots"}
            ]
          })

  def policy, do: @policy
end
