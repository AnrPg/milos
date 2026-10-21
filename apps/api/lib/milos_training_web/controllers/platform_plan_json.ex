defmodule MilosTrainingWeb.PlatformPlanJSON do
  @moduledoc "Renders platform plans and subscriptions (ADR-170)."

  alias MilosTraining.PlatformPlans

  @plan_fields [
    :code,
    :audience,
    :name,
    :description,
    :limits,
    :monthly_price_cents,
    :annual_price_cents,
    :currency,
    :price_status,
    :trial_days,
    :is_default,
    :public,
    :active,
    :position
  ]

  def plan(nil), do: nil
  def plan(plan), do: Map.take(plan, @plan_fields)

  def subscription(subscription, now \\ DateTime.utc_now()) do
    %{
      organization_id: subscription.organization_id,
      plan_code: subscription.plan_code,
      status: PlatformPlans.effective_status(subscription, now),
      stored_status: subscription.status,
      trial_ends_at: subscription.trial_ends_at,
      price_override_cents: subscription.price_override_cents,
      notes: subscription.notes,
      updated_at: subscription.updated_at
    }
  end

  def organization_plan(view) do
    %{
      plan: plan(view.plan),
      status: view.status,
      notice: view.notice,
      trial_ends_at: view.trial_ends_at,
      trial_days_left: view.trial_days_left,
      price_override_cents: view.price_override_cents,
      usage:
        Enum.map(view.usage, fn row ->
          %{
            key: row.key,
            used: row.used,
            limit: if(row.limit == :unlimited, do: nil, else: row.limit),
            hard: row.hard,
            state: Atom.to_string(row.state)
          }
        end)
    }
  end
end
