defmodule MilosTraining.Application.GetAdminSettings do
  alias MilosTraining.{Finance, Gamification, Notifications, Organizations, Scheduling}

  def call, do: {:error, :organization_context_required}

  def call(context) do
    {:ok,
     %{
       # TD-092: gamification settings are a tenant row (defaults otherwise).
       gamification: Gamification.with_tenant_context(context, &Gamification.get_settings/0),
       finance: Finance.get_finance_settings(context),
       notifications: Notifications.get_push_settings(),
       scheduling: Scheduling.get_settings(context),
       # ADR-163: workout-authoring defaults (the WOD-goals toggle).
       workouts: Organizations.get_workout_settings(context),
       provider: provider(context)
     }}
  end

  @doc "ADR-162: gym or independent coach; only the owner may change it."
  def provider(context) do
    %{
      kind: Organizations.get_provider_kind(context),
      editable: Organizations.any_role?(context, [:owner])
    }
  end
end
