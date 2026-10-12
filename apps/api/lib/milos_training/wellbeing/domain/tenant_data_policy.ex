defmodule MilosTraining.Wellbeing.Domain.TenantDataPolicy do
  @moduledoc """
  Wellbeing tenant data retention and purge policy (ADR-107).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "wellbeing",
            purge_order: 60,
            disposition: :purge,
            basis:
              "Injury reports are sensitive health data; data minimisation requires deletion once exported.",
            tables: [
              %{table: "injury_status_events", parent: {"injury_reports", "injury_report_id"}},
              %{table: "injury_reports"}
            ]
          })

  def policy, do: @policy
end
