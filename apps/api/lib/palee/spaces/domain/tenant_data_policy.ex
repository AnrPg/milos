defmodule Palee.Spaces.Domain.TenantDataPolicy do
  @moduledoc """
  Spaces tenant data retention and purge policy (ADR-117, ADR-202).

  Purged after Scheduling, Housekeeping and Inventory, whose classes,
  cleaning entries, schedules and machine placements point at spaces, and
  before Facility, whose branches the spaces belong to.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "spaces",
            purge_order: 105,
            disposition: :purge,
            basis:
              "Spaces, floor plans and unavailability windows are operational data with no retention obligation.",
            tables: [
              %{table: "space_unavailabilities"},
              %{table: "spaces"},
              %{table: "space_floor_plans"}
            ]
          })

  def policy, do: @policy
end
