defmodule Palee.Scaling.Domain.TenantDataPolicy do
  @moduledoc """
  Scaling tenant data retention and purge policy (ADR-117, ADR-174).

  Scaling suggestions are coaching aids derived from the workout and the
  gym's injury records; nothing carries a retention obligation, so they are
  purged with the gym. They reference no other tenant table.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "scaling",
            purge_order: 4,
            disposition: :purge,
            basis:
              "Scaling suggestions are coaching aids derived from workouts and the gym's injury records, with no retention obligation; deleted once exported.",
            tables: [
              %{table: "scaling_suggestions"}
            ]
          })

  def policy, do: @policy
end
