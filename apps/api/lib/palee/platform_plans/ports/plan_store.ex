defmodule Palee.PlatformPlans.Ports.PlanStore do
  @moduledoc "Persistence port of the platform plan catalog and subscriptions (ADR-170)."

  alias Palee.PlatformPlans.{OrganizationSubscription, PlatformPlan}

  @type filters :: %{optional(:audience) => String.t(), optional(:public_only) => boolean()}

  @callback list_plans(filters()) :: [PlatformPlan.t()]
  @callback get_plan(String.t()) :: PlatformPlan.t() | nil
  @callback create_plan(map()) :: {:ok, PlatformPlan.t()} | {:error, Ecto.Changeset.t()}
  @callback update_plan(String.t(), map()) ::
              {:ok, PlatformPlan.t()} | {:error, Ecto.Changeset.t() | :not_found}
  @callback ensure_subscription(Ecto.UUID.t()) :: :ok | {:error, term()}
  @callback get_subscription(Ecto.UUID.t()) :: OrganizationSubscription.t() | nil
  @callback list_subscriptions([Ecto.UUID.t()] | :all) :: [OrganizationSubscription.t()]
  @callback assign_subscription(Ecto.UUID.t(), map()) ::
              {:ok, OrganizationSubscription.t()} | {:error, Ecto.Changeset.t()}
end
