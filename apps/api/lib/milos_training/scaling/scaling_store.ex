defmodule MilosTraining.Scaling.ScalingStore do
  @moduledoc "Facade over the scaling adapter (ADR-174); every call runs in the caller's session."

  @behaviour MilosTraining.Scaling.Ports.ScalingStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :scaling_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get(context, id), do: call(context, :get, [id])

  @impl true
  def latest_live(context, assignment_id, athlete_id),
    do: call(context, :latest_live, [assignment_id, athlete_id])

  @impl true
  def insert(context, attrs), do: call(context, :insert, [attrs])

  @impl true
  def replace(context, previous, attrs), do: call(context, :replace, [previous, attrs])

  @impl true
  def update(context, suggestion, changes), do: call(context, :update, [suggestion, changes])

  @impl true
  def list(context, filters), do: call(context, :list, [filters])

  @impl true
  def approved_for_member(context, athlete_id, workout_id, from),
    do: call(context, :approved_for_member, [athlete_id, workout_id, from])

  @impl true
  def approved_history(context, athlete_id, limit),
    do: call(context, :approved_history, [athlete_id, limit])
end
