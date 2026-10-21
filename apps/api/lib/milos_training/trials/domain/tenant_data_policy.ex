defmodule MilosTraining.Trials.Domain.TenantDataPolicy do
  @moduledoc """
  Trials tenant data retention and purge policy (ADR-117, ADR-144).

  Trial requests and the box's trial rules are operational data with no
  retention obligation. Purged before Finance because the policy points at a
  membership package.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "trials",
            purge_order: 88,
            disposition: :purge,
            basis:
              "Trial requests and trial rules are operational data with no retention obligation; purged before Finance because the policy references a membership package.",
            tables: [
              %{table: "scheduling_trial_requests"},
              %{table: "scheduling_trial_policies"}
            ]
          })

  def policy, do: @policy
end
