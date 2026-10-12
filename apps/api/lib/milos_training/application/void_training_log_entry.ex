defmodule MilosTraining.Application.VoidTrainingLogEntry do
  @moduledoc """
  Voids a training-log entry (ADR-100). Entries are never deleted.

  Voiding removes the entry from every *future* completion projection (the
  gamification projection rebuilds its completed list from live entries), but
  does not retroactively reverse streaks, badges, PR events, or challenge
  progress already awarded - see ADR-100 Consequences.
  """

  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Execution

  def call(%{organization_id: _} = context, %{id: user_id}, entry_id, params)
      when is_map(params) do
    Execution.with_training_log_context(context, fn ->
      with {:ok, entry} <-
             Execution.void_training_log_entry(entry_id, user_id, params, DateTime.utc_now()) do
        InvalidateLandingPages.for_users([user_id])
        {:ok, entry}
      end
    end)
  end

  def call(_context, _actor, _entry_id, _params), do: {:error, :organization_context_required}
end
