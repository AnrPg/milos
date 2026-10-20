defmodule MilosTraining.Wellness.Domain.TenantDataPolicy do
  @moduledoc """
  Wellness tenant data retention and purge policy (ADR-117, ADR-159).

  Entries carry the gym they were written in, if any (provenance, like
  Πώς νιώθω). A purged gym takes those rows with it; personal rows and
  preferences belong to the account and are never tenant data.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "wellness",
            purge_order: 61,
            disposition: :purge,
            basis:
              "Water, sleep, meals and cravings are sensitive health-like data; data minimisation requires deletion once exported.",
            tables: [
              %{table: "craving_entries", rls: :user},
              %{table: "wellness_entries", rls: :user}
            ]
          })

  def policy, do: @policy
end
