defmodule Palee.Seasons.Domain.TenantDataPolicy do
  @moduledoc """
  Seasons tenant data retention and purge policy (ADR-117, ADR-167).

  Season offerings and enrollments are operational data; money owed or paid
  for a season lives in Finance (the subscription a confirmation created), so
  nothing here carries a retention obligation. Purged before Finance because
  an offering points at a membership package.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "seasons",
            purge_order: 86,
            disposition: :purge,
            basis:
              "Season offerings and enrollments are operational data with no retention obligation; payments live in Finance. Purged before Finance because an offering references a membership package.",
            tables: [
              %{table: "season_enrollments"},
              %{table: "season_offerings"}
            ]
          })

  def policy, do: @policy
end
