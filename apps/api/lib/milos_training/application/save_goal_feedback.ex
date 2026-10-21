defmodule MilosTraining.Application.SaveGoalFeedback do
  @moduledoc """
  «Τι ένιωσες» save (ADR-163): the muscles and qualities a member felt
  after one of their own entries, validated against the taxonomy
  (`GoalSet.normalize_feedback/1`) and upserted (one row per entry). The
  row takes the entry's gym, like a comment. A voided training-log entry is
  frozen: its feedback is kept but can no longer change.
  """

  alias MilosTraining.Anatomy
  alias MilosTraining.Application.GoalFeedbackEntry
  alias MilosTraining.Journal

  def call(context, entry_kind, entry_id, params) when is_map(params) do
    with {:ok, entry} <- GoalFeedbackEntry.fetch(context, entry_kind, entry_id),
         :ok <- writable(entry),
         {:ok, felt} <- Anatomy.normalize_feedback(params),
         {:ok, feedback} <-
           Journal.put_goal_feedback(context, %{
             user_id: context.user_id,
             organization_id: entry.organization_id,
             entry_kind: entry.entry_kind,
             entry_id: entry.entry_id,
             felt_muscles: felt.felt_muscles,
             felt_qualities: felt.felt_qualities
           }) do
      {:ok, GoalFeedbackEntry.response(context, entry, feedback)}
    end
  end

  def call(_context, _entry_kind, _entry_id, _params), do: {:error, :bad_request}

  defp writable(%{voided: true}), do: {:error, :training_log_entry_voided}
  defp writable(_entry), do: :ok
end
