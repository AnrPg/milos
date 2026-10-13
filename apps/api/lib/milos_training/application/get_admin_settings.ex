defmodule MilosTraining.Application.GetAdminSettings do
  alias MilosTraining.{Finance, Gamification, Notifications, Scheduling}

  def call, do: {:error, :organization_context_required}

  def call(context) do
    {:ok,
     %{
       # TD-092: gamification settings are a tenant row (defaults otherwise).
       gamification: Gamification.with_tenant_context(context, &Gamification.get_settings/0),
       finance: Finance.get_finance_settings(context),
       notifications: Notifications.get_push_settings(),
       scheduling: Scheduling.get_settings(context)
     }}
  end
end
