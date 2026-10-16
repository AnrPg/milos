defmodule MilosTraining.Wellbeing.Domain.TenantDataPolicy do
  @moduledoc """
  Wellbeing tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "wellbeing",
            purge_order: 60,
            disposition: :purge,
            basis:
              "Injury reports and readiness check-ins are sensitive health data; data minimisation requires deletion once exported.",
            tables: [
              %{table: "injury_status_events", parent: {"injury_reports", "injury_report_id"}},
              %{table: "injury_reports"},
              # ADR-139/140 Πώς νιώθω check-ins: personal rows with gym provenance.
              %{
                table: "wellbeing_check_in_answers",
                rls: {:user_via, "wellbeing_check_ins", "check_in_id"}
              },
              %{table: "wellbeing_check_ins", rls: :user}
            ]
          })

  def policy, do: @policy
end
