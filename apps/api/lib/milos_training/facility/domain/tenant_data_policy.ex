defmodule MilosTraining.Facility.Domain.TenantDataPolicy do
  @moduledoc """
  Facility tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "facility",
            purge_order: 120,
            disposition: :purge,
            basis:
              "Locations and check-ins are operational data with no retention obligation; purged after Scheduling and Appointments because classes and appointment slots reference locations.",
            tables: [
              %{table: "facility_check_ins"},
              %{table: "facility_locations"}
            ]
          })

  def policy, do: @policy
end
