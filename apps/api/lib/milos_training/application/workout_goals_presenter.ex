defmodule MilosTraining.Application.WorkoutGoalsPresenter do
  @moduledoc """
  Shapes WOD goals (ADR-163) for the staff editor, the member card and the
  «τι ένιωσες» checklist, and computes the live suggestion of a workout from
  its exercises. Shared by the goal use cases; no persistence of its own.
  """

  alias MilosTraining.{Anatomy, Workouts}

  @doc """
  The deterministic suggestion for a workout: muscles with roles,
  qualities, how many of its exercises were recognised, and the taxonomy
  version it was computed with.
  """
  def suggestion(workout) do
    suggested = workout |> Workouts.goal_exercises() |> Anatomy.suggest_goals()

    %{
      muscles: Enum.map(suggested.muscles, &muscle/1),
      qualities: suggested.qualities,
      matched_exercises: suggested.matched_exercises,
      unmatched_exercises: suggested.unmatched_exercises,
      taxonomy_version: Anatomy.taxonomy_version()
    }
  end

  @doc "Staff view: the saved goals, or the suggestion when none are saved."
  def staff_goals(workout_id, nil, suggestion) do
    %{
      workout_id: workout_id,
      saved: false,
      muscles: suggestion.muscles,
      qualities: suggestion.qualities,
      stimulus: nil,
      visible_to_members: false,
      source: "suggested",
      taxonomy_version: suggestion.taxonomy_version,
      updated_by_id: nil,
      updated_at: nil
    }
  end

  def staff_goals(workout_id, saved, _suggestion) do
    %{
      workout_id: workout_id,
      saved: true,
      muscles: Enum.map(saved.muscles, &muscle/1),
      qualities: saved.qualities,
      stimulus: saved.stimulus,
      visible_to_members: saved.visible_to_members,
      source: saved.source,
      taxonomy_version: saved.taxonomy_version,
      updated_by_id: saved.updated_by_id,
      updated_at: saved.updated_at
    }
  end

  @doc "Member view: only goals the coach saved and made visible, else nil."
  def member_goals(%{visible_to_members: true} = saved) do
    %{
      workout_id: saved.workout_id,
      muscles: Enum.map(saved.muscles, &muscle/1),
      qualities: saved.qualities,
      stimulus: saved.stimulus,
      taxonomy_version: saved.taxonomy_version,
      updated_at: saved.updated_at
    }
  end

  def member_goals(_saved), do: nil

  def muscle(%{id: id, role: role}), do: %{id: id, role: to_string(role)}
end
