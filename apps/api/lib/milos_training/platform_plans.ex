defmodule MilosTraining.PlatformPlans do
  @moduledoc """
  The platform's SaaS plans (ADR-170, vision §5.3): the catalog vendors edit
  (prices start as placeholders, brief §10 Q2), the plan each organization
  is on, and the limits a plan sets. A plan never locks anyone out: only a
  new staff seat beyond `staff_seats` is refused.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.PlatformPlans.Domain.{PlanLimits, SubscriptionPolicy}
  alias MilosTraining.PlatformPlans.PlanStore

  @admin_roles [:owner, :admin]

  @doc "Active public plans, for pricing and the coach onboarding (anyone may read)."
  def list_public_plans(audience \\ nil) do
    {:ok, PlanStore.list_plans(%{audience: audience, public_only: true})}
  end

  @doc "The public default plan of an audience (`coach` → the solo-coach tier)."
  def default_plan(audience) do
    PlanStore.list_plans(%{audience: audience, public_only: false})
    |> Enum.find(& &1.is_default)
  end

  ## Vendors (platform console)

  def list_plans(context) do
    as_vendor(context, fn -> {:ok, PlanStore.list_plans(%{})} end)
  end

  def create_plan(context, attrs), do: as_vendor(context, fn -> PlanStore.create_plan(attrs) end)

  def update_plan(context, code, attrs),
    do: as_vendor(context, fn -> PlanStore.update_plan(code, attrs) end)

  def list_subscriptions(context, organization_ids) do
    as_vendor(context, fn -> {:ok, PlanStore.list_subscriptions(organization_ids)} end)
  end

  @doc "A vendor puts an organization on a plan, with a status and an optional negotiated price."
  def assign_plan(context, organization_id, attrs, now \\ DateTime.utc_now()) do
    as_vendor(context, fn ->
      code = Map.get(attrs, :plan_code, Map.get(attrs, "plan_code"))
      notes = Map.get(attrs, :notes, Map.get(attrs, "notes"))

      with {:ok, assignment} <- SubscriptionPolicy.validate_assignment(attrs, now),
           %{} <- PlanStore.get_plan(code) || {:error, :unknown_plan} do
        PlanStore.assign_subscription(
          organization_id,
          Map.merge(assignment, %{plan_code: code, notes: notes, updated_by_id: context.user_id})
        )
      end
    end)
  end

  ## Organizations

  @doc """
  Starts the default plan of the organization's kind, once (inside the
  creation transaction, ADR-133). Never changes an existing subscription.
  """
  def ensure_subscription(%{organization_id: organization_id} = scope)
      when is_binary(organization_id) do
    RepoContext.run(scope, fn ->
      with :ok <- PlanStore.ensure_subscription(organization_id) do
        {:ok, PlanStore.get_subscription(organization_id)}
      end
    end)
  end

  @doc "The organization's plan, for its owners and admins."
  def get_subscription(context) do
    with :ok <- authorize_admin(context) do
      {:ok,
       RepoContext.run(context, fn -> PlanStore.get_subscription(context.organization_id) end)}
    end
  end

  @doc """
  Whether `adding` more of `key` fits the organization's plan, given `used`.
  An organization without a subscription row is never refused.
  """
  def check_limit(context, key, used, adding \\ 1)
      when key in ["staff_seats", "active_clients"] do
    case RepoContext.run(context, fn -> PlanStore.get_subscription(context.organization_id) end) do
      %{plan: %{limits: limits}} -> PlanLimits.check(limits, key, used, adding)
      _none -> :ok
    end
  end

  @doc "The status people see: a trial past its end reads `trial_expired`."
  def effective_status(subscription, now),
    do: SubscriptionPolicy.effective_status(subscription, now)

  @doc """
  The plan card: the plan, the effective status, the one notice to show,
  and every limit with what is used (`usage` keyed like the limits).
  """
  def describe(subscription, usage, now) do
    plan = subscription && subscription.plan
    limits = (plan && plan.limits) || %{}

    %{
      plan: plan,
      status: subscription && SubscriptionPolicy.effective_status(subscription, now),
      notice: subscription && SubscriptionPolicy.notice(subscription, now),
      trial_ends_at: subscription && subscription.trial_ends_at,
      trial_days_left: subscription && SubscriptionPolicy.trial_days_left(subscription, now),
      price_override_cents: subscription && subscription.price_override_cents,
      usage: PlanLimits.usage(limits, usage)
    }
  end

  defp authorize_admin(context) do
    roles = Map.get(context, :roles) || List.wrap(Map.get(context, :role))
    if Enum.any?(roles, &(&1 in @admin_roles)), do: :ok, else: {:error, :forbidden}
  end

  defp as_vendor(%{vendor: vendor, user_id: user_id}, fun)
       when not is_nil(vendor) and is_binary(user_id),
       do: RepoContext.run(%{user_id: user_id}, fun)

  defp as_vendor(_context, _fun), do: {:error, :vendor_required}
end
