defmodule MilosTraining.Application.OpenAssignedWorkout do
  @moduledoc """
  Records that an athlete opened an assignment's detail (ADR-123).

  There is no server read path for a single assignment - the week view lists
  them and the detail sheet opens client-side - so the client reports the
  open through this command. It only verifies that the assignment exists in
  the tenant and is linked to the acting athlete, then records
  `workout_assignment_opened`, deduplicated per user, assignment and UTC day.
  Recording is best effort: the command succeeds even if analytics fails.
  """

  alias MilosTraining.Application.TrackAnalyticsEvent
  alias MilosTraining.Workouts

  def call(%{organization_id: organization_id, user_id: user_id} = context, assignment_id)
      when is_binary(organization_id) and is_binary(user_id) do
    with {:ok, assignment_id} <- uuid(assignment_id),
         %{} = assignment <-
           Workouts.get_assigned_workout(context, assignment_id) || {:error, :not_found},
         :ok <- linked(assignment, user_id) do
      TrackAnalyticsEvent.call("workout_assignment_opened", context, assignment)
    end
  end

  def call(_context, _assignment_id), do: {:error, :organization_context_required}

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp linked(assignment, user_id) do
    if user_id in (Map.get(assignment, :athlete_ids) || []),
      do: :ok,
      else: {:error, :not_found}
  end
end
