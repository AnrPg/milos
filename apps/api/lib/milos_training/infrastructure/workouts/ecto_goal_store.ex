defmodule MilosTraining.Infrastructure.Workouts.EctoGoalStore do
  @moduledoc """
  Ecto adapter for WOD goals (ADR-163). Session-scoped: the tenant policy
  and the `milos_apply_tenant_context()` trigger keep rows in the session's
  gym, and every query also names the workout so a goal row is only ever
  reached through its workout.
  """

  @behaviour MilosTraining.Workouts.Ports.GoalStore

  import Ecto.Query

  alias MilosTraining.Repo
  alias MilosTraining.Workouts.WorkoutGoal

  @impl true
  def get_goals(workout_id) do
    with {:ok, workout_id} <- Ecto.UUID.cast(workout_id),
         %WorkoutGoal{} = goal <- Repo.one(by_workout(workout_id)) do
      normalize(goal)
    else
      _missing -> nil
    end
  end

  @impl true
  def put_goals(workout_id, attrs) do
    existing = Repo.one(by_workout(workout_id)) || %WorkoutGoal{}

    existing
    |> WorkoutGoal.changeset(Map.put(attrs, :master_workout_id, workout_id))
    |> Repo.insert_or_update()
    |> case do
      {:ok, goal} -> {:ok, normalize(goal)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Copies a workout's goals onto its duplicate, in the caller's transaction
  and session (called by the workout store's duplicate).
  """
  def copy_goals(source_workout_id, target_workout_id) do
    case Repo.one(by_workout(source_workout_id)) do
      nil ->
        :ok

      %WorkoutGoal{} = goal ->
        %WorkoutGoal{}
        |> WorkoutGoal.changeset(%{
          master_workout_id: target_workout_id,
          muscles: goal.muscles,
          qualities: goal.qualities,
          stimulus: goal.stimulus,
          visible_to_members: goal.visible_to_members,
          source: goal.source,
          taxonomy_version: goal.taxonomy_version,
          updated_by_id: goal.updated_by_id
        })
        |> Repo.insert()
        |> case do
          {:ok, _copy} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp by_workout(workout_id),
    do: where(WorkoutGoal, [goal], goal.master_workout_id == ^workout_id)

  defp normalize(%WorkoutGoal{} = goal) do
    %{
      workout_id: goal.master_workout_id,
      muscles: Enum.map(goal.muscles || [], &muscle/1),
      qualities: goal.qualities || [],
      stimulus: goal.stimulus,
      visible_to_members: goal.visible_to_members,
      source: goal.source,
      taxonomy_version: goal.taxonomy_version,
      updated_by_id: goal.updated_by_id,
      updated_at: goal.updated_at
    }
  end

  defp muscle(item) do
    %{
      id: Map.get(item, "id") || Map.get(item, :id),
      role: to_string(Map.get(item, "role") || Map.get(item, :role))
    }
  end
end
