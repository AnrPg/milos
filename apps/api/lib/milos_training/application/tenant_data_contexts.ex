defmodule MilosTraining.Application.TenantDataContexts do
  @moduledoc """
  Bounded contexts that own tenant data, ordered for purge (ADR-117).

  Each module exposes `tenant_data_policy/0`, `tenant_data_inventory/1`,
  `export_tenant_data/2` and `purge_tenant_data/1` through its public API.
  Organizations is exported like the others but purged last, by deleting the
  organization row in `Organizations.complete_organization_purge/3`.
  """

  alias MilosTraining.{
    Analytics,
    Appointments,
    Coaching,
    Community,
    Content,
    Execution,
    Facility,
    Feedback,
    Finance,
    Gamification,
    Housekeeping,
    Inventory,
    Journal,
    Messaging,
    Notifications,
    Nutrition,
    Pantheon,
    Scheduling,
    Wellbeing,
    Workouts
  }

  alias MilosTraining.TenantData.Domain.RetentionReview

  @purgeable [
    Analytics,
    Community,
    Notifications,
    Execution,
    Pantheon,
    Journal,
    Feedback,
    Wellbeing,
    Messaging,
    Gamification,
    Finance,
    Scheduling,
    Workouts,
    Coaching,
    Nutrition,
    Content,
    Housekeeping,
    Inventory,
    Appointments,
    Facility
  ]

  @doc "Purgeable contexts as `{module, policy}` in dependency order (dependents first)."
  def purge_sequence do
    @purgeable
    |> Enum.map(&{&1, &1.tenant_data_policy()})
    |> Enum.sort_by(fn {_module, policy} -> policy.purge_order end)
  end

  @doc "Policies of every purgeable context, in purge order."
  def policies, do: purge_sequence() |> Enum.map(&elem(&1, 1)) |> RetentionReview.purge_sequence()
end
