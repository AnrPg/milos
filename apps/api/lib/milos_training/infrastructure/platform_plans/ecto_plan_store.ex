defmodule MilosTraining.Infrastructure.PlatformPlans.EctoPlanStore do
  @moduledoc "Ecto adapter of `PlatformPlans.Ports.PlanStore` (ADR-170)."

  @behaviour MilosTraining.PlatformPlans.Ports.PlanStore

  import Ecto.Query

  alias MilosTraining.PlatformPlans.{OrganizationSubscription, PlatformPlan}
  alias MilosTraining.Repo

  @impl true
  def list_plans(filters) do
    PlatformPlan
    |> maybe_audience(Map.get(filters, :audience))
    |> maybe_public(Map.get(filters, :public_only, false))
    |> order_by([plan], asc: plan.audience, asc: plan.position, asc: plan.code)
    |> Repo.all()
  end

  defp maybe_audience(query, nil), do: query
  defp maybe_audience(query, audience), do: where(query, [plan], plan.audience == ^audience)

  defp maybe_public(query, true), do: where(query, [plan], plan.public and plan.active)
  defp maybe_public(query, _all), do: query

  @impl true
  def get_plan(code), do: Repo.get_by(PlatformPlan, code: code)

  @impl true
  def create_plan(attrs) do
    Repo.transaction(fn ->
      changeset = PlatformPlan.create_changeset(attrs)
      clear_default_if_taking_over(changeset)

      case Repo.insert(changeset) do
        {:ok, plan} -> plan
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @impl true
  def update_plan(code, attrs) do
    Repo.transaction(fn ->
      case Repo.get_by(PlatformPlan, code: code) do
        nil ->
          Repo.rollback(:not_found)

        plan ->
          changeset = PlatformPlan.update_changeset(plan, attrs)
          clear_default_if_taking_over(changeset)

          case Repo.update(changeset) do
            {:ok, plan} -> plan
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  # One default per audience: a plan made the default takes over from the
  # previous one in the same transaction.
  defp clear_default_if_taking_over(changeset) do
    if changeset.valid? and Ecto.Changeset.get_change(changeset, :is_default) == true do
      audience = Ecto.Changeset.get_field(changeset, :audience)
      code = Ecto.Changeset.get_field(changeset, :code)

      PlatformPlan
      |> where([plan], plan.audience == ^audience and plan.is_default and plan.code != ^code)
      |> Repo.update_all(set: [is_default: false, updated_at: DateTime.utc_now()])
    end
  end

  @impl true
  def ensure_subscription(organization_id) do
    case Repo.query("SELECT milos_ensure_platform_subscription($1)", [
           Ecto.UUID.dump!(organization_id)
         ]) do
      {:ok, _result} ->
        :ok

      {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} ->
        {:error, :forbidden}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_subscription(organization_id) do
    OrganizationSubscription
    |> where([subscription], subscription.organization_id == ^organization_id)
    |> preload(:plan)
    |> Repo.one()
  end

  @impl true
  def list_subscriptions([]), do: []

  def list_subscriptions(:all), do: OrganizationSubscription |> preload(:plan) |> Repo.all()

  def list_subscriptions(organization_ids) do
    OrganizationSubscription
    |> where([subscription], subscription.organization_id in ^organization_ids)
    |> preload(:plan)
    |> Repo.all()
  end

  @impl true
  def assign_subscription(organization_id, attrs) do
    existing =
      Repo.get_by(OrganizationSubscription, organization_id: organization_id) ||
        %OrganizationSubscription{organization_id: organization_id}

    existing
    |> OrganizationSubscription.assign_changeset(
      Map.put(attrs, :organization_id, organization_id)
    )
    |> Repo.insert_or_update()
    |> case do
      {:ok, subscription} -> {:ok, Repo.preload(subscription, :plan, force: true)}
      error -> error
    end
  end
end
