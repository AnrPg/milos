defmodule MilosTraining.Scheduling.Domain.TenantDataPolicy do
  @moduledoc """
  Scheduling tenant data retention and purge policy (ADR-107).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "scheduling",
            purge_order: 100,
            disposition: :purge,
            basis:
              "Class schedules, bookings and attendance are operational data with no retention obligation; purged before Workouts because classes reference workouts.",
            tables: [
              %{table: "class_attendance_records"},
              %{table: "bookings"},
              %{table: "scheduled_classes"},
              %{table: "class_series"},
              %{table: "class_types"},
              %{table: "scheduling_settings"}
            ]
          })

  def policy, do: @policy
end
