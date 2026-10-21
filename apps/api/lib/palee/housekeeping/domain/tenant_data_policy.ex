defmodule Palee.Housekeeping.Domain.TenantDataPolicy do
  @moduledoc """
  Housekeeping tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "housekeeping",
            purge_order: 85,
            disposition: :purge,
            basis:
              "Cleaning areas and cleaning log entries are operational data with no retention obligation.",
            tables: [
              %{table: "housekeeping_entries"},
              %{table: "housekeeping_areas"}
            ]
          })

  def policy, do: @policy
end
