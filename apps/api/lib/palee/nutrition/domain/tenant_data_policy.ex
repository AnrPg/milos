defmodule Palee.Nutrition.Domain.TenantDataPolicy do
  @moduledoc """
  Nutrition tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "nutrition",
            purge_order: 66,
            disposition: :purge,
            basis:
              "Nutrition plans are personal coaching data; data minimisation requires deletion once exported.",
            tables: [
              %{table: "nutrition_plans"}
            ]
          })

  def policy, do: @policy
end
