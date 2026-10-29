defmodule Palee.Application.TenantDataContexts do
  @moduledoc """
  Bounded contexts that own tenant data, ordered for purge (ADR-117).

  Each module exposes `tenant_data_policy/0`, `tenant_data_inventory/1`,
  `export_tenant_data/2` and `purge_tenant_data/1` through its public API.
  Organizations is exported like the others but purged last, by deleting the
  organization row in `Organizations.complete_organization_purge/3`.
  """

  alias Palee.{
    AiUsage,
    Analytics,
    Appointments,
    Body,
    Buddies,
    Coaching,
    Community,
    Content,
    Devices,
    Execution,
    Facility,
    Feedback,
    Finance,
    Fiscal,
    Gamification,
    Housekeeping,
    Imports,
    Inventory,
    Journal,
    Media,
    Messaging,
    Notifications,
    Nutrition,
    Pantheon,
    Partners,
    Perks,
    Referrals,
    Scaling,
    Scheduling,
    Seasons,
    Shop,
    Spaces,
    Trials,
    Wallet,
    Wellbeing,
    Wellness,
    Workouts
  }

  alias Palee.TenantData.Domain.RetentionReview

  @purgeable [
    AiUsage,
    Imports,
    Scaling,
    Analytics,
    Partners,
    Community,
    Media,
    Notifications,
    Execution,
    Pantheon,
    Journal,
    Body,
    Buddies,
    Feedback,
    Wellbeing,
    Wellness,
    Devices,
    Messaging,
    Gamification,
    Wallet,
    Perks,
    Seasons,
    Shop,
    Trials,
    Referrals,
    Fiscal,
    Finance,
    Scheduling,
    Workouts,
    Coaching,
    Nutrition,
    Content,
    Housekeeping,
    Inventory,
    Appointments,
    Spaces,
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
