defmodule MilosTraining.AiUsage.Domain.TenantDataPolicy do
  @moduledoc """
  AI usage tenant data retention and purge policy (ADR-117, ADR-152).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "ai_usage",
            purge_order: 3,
            disposition: :purge,
            basis:
              "AI usage records are operational metering for the gym and its AI settings hold the gym's own provider key (encrypted); anything invoiced from them lives in Finance, so they are deleted once exported.",
            tables: [
              %{table: "ai_usage_records"},
              %{table: "organization_ai_settings"}
            ]
          })

  def policy, do: @policy
end
