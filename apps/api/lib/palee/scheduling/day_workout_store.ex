defmodule Palee.Scheduling.DayWorkoutStore do
  @moduledoc false
  @behaviour Palee.Scheduling.Ports.DayWorkoutStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :day_workout_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun) when is_function(fun, 0),
    do: tenant_call(context, :transaction, [fun])

  @impl true
  def list_rules(context, from, to), do: tenant_call(context, :list_rules, [from, to])
  @impl true
  def get_rule(context, id), do: tenant_call(context, :get_rule, [id])
  @impl true
  def put_rule(context, attrs), do: tenant_call(context, :put_rule, [attrs])
  @impl true
  def delete_rule(context, id), do: tenant_call(context, :delete_rule, [id])
  @impl true
  def list_classes(context, from, to), do: tenant_call(context, :list_classes, [from, to])
  @impl true
  def apply_changes(context, changes), do: tenant_call(context, :apply_changes, [changes])
end
