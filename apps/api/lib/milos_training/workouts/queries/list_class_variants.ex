defmodule MilosTraining.Workouts.Queries.ListClassVariants do
  @moduledoc """
  ADR-115: live per-member variants of class occurrences.

  `assignee_id` narrows the result to one user's own variants (the member's
  "Your version"); `nil` returns every assignee's variants (staff view).
  """

  alias MilosTraining.Workouts.WorkoutStore

  def call(_context, [], _assignee_id), do: []

  def call(context, slot_ids, assignee_id) when is_list(slot_ids),
    do: WorkoutStore.list_class_variants(context, Enum.uniq(slot_ids), assignee_id)
end
