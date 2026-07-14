defmodule MilosTraining.Workouts.Commands.ArchiveAthleteAssignments do
  alias MilosTraining.Workouts.WorkoutStore

  def call(athlete_id), do: WorkoutStore.archive_active_assignments_for_athlete(athlete_id)
end
