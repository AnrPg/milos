defmodule Palee.Infrastructure.Workouts.EctoGoalStore do
  @moduledoc """
  Ecto adapter for WOD goals (ADR-163). Session-scoped: the tenant policy
  and the `palee_apply_tenant_context()` trigger keep rows in the session's
  gym, and every query also names the workout so a goal row is only ever
  reached through its workout.
  """

  @behaviour Palee.Workouts.Ports.GoalStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo
  alias Palee.Workouts.{MasterWorkout, WorkoutGoal}

  # How far up a chain of copies a workout looks for goals to inherit.
  @max_inheritance_depth 5

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
  def resolve_goals(workout_id) do
    case Ecto.UUID.cast(workout_id) do
      {:ok, workout_id} ->
        case get_goals(workout_id) do
          nil -> workout_id |> inherited([workout_id]) |> as_inherited()
          goals -> %{goals: goals, inherited_from: nil}
        end

      :error ->
        %{goals: nil, inherited_from: nil}
    end
  end

  # Walks `source_workout_id` up to the first ancestor with goals of its own,
  # only through workouts of the session's gym.
  defp inherited(workout_id, seen) do
    case RepoContext.current_setting("app.organization_id") do
      nil -> nil
      organization_id -> inherited(organization_id, workout_id, seen)
    end
  end

  defp inherited(organization_id, workout_id, seen) do
    parent_id =
      MasterWorkout
      |> join(:inner, [workout], parent in MasterWorkout,
        on: parent.id == workout.source_workout_id
      )
      |> where([workout], workout.id == ^workout_id)
      |> where([workout, parent], parent.organization_id == ^organization_id)
      |> select([_workout, parent], parent.id)
      |> Repo.one()

    cond do
      is_nil(parent_id) or parent_id in seen -> nil
      goals = get_goals(parent_id) -> goals
      length(seen) >= @max_inheritance_depth -> nil
      true -> inherited(organization_id, parent_id, [parent_id | seen])
    end
  end

  defp as_inherited(nil), do: %{goals: nil, inherited_from: nil}
  defp as_inherited(goals), do: %{goals: goals, inherited_from: goals.workout_id}

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
